# vim: foldmarker=<<<,>>> ft=tcl foldmethod=marker shiftwidth=4 ts=4

# Signals:
#	connected()					- fired when connection is established
#	lost_connection()			- fired when connection is lost
#	send(msgdict)				- called with msg we are sending
#	send,$msgtype(msgdict)		- specific message type, ie send,svc_avail
#	incoming(msgdict)			- called with incoming msg
#	incoming,$msgtype(msgdict)	- specific message type, ie send,req

cflib::pclass create m2::api {
	#superclass cflib::handlers sop::signalsource cflib::baselog
	superclass sop::signalsource cflib::handlers cflib::baselog

	property uri				""			_need_reconnect
	property ip					""			_need_reconnect
	property port				""			_need_reconnect
	property connection_retry	10

	protected_property dominos
	protected_property con
	protected_property unique					0
	protected_property svcs						[dict create]
	protected_property connect_after_id			""
	protected_property queue
	protected_property queue_roundrobin			{}
	protected_property last_connection_attempt	0

	variable {*}{
		signals
		svc_signals
		neighbour_info
	}

	constructor {args} { #<<<
		array set dominos		{}
		array set svc_signals	{}
		set neighbour_info	[dict create \
				type		application \
		]
		if {[info exists ::argv0]} {
			dict set neighbour_info debug_name	[file tail $::argv0]
		}

		sop::domino new dominos(need_reconnect) -name "[self] need_reconnect"
		sop::signal new signals(connected) -name "[self] connected"
		sop::domino new dominos(svc_avail_changed) -name "[self] svc_avail_changed"

		$dominos(svc_avail_changed) attach_output [my code _svc_avail_changed]
		$dominos(need_reconnect) attach_output [my code _attempt_connection]

		package require netdgram::tcp
		oo::define netdgram::connectionmethod::tcp method default_port {} {
			return 5300
		}

		my configure {*}$args
	}

	#>>>
	destructor { #<<<
		my _close_con
	}

	#>>>

	method new_svcs {args} { #<<<
		if {![$signals(connected) state]} {
			error "Not connected"
		}
		my send [m2::msg::new [list \
			type	svc_avail \
			seq		[incr unique] \
			data	$args \
		]]
	}

	#>>>
	method revoke_svcs {args} { #<<<
		if {![$signals(connected) state]} return
		my send [m2::msg::new [list \
			type	svc_revoke \
			seq		[incr unique] \
			data	$args \
		]]
	}

	#>>>
	method svc_signal {svc} { #<<<
		if {![info exists svc_signals($svc)]} {
			sop::signal new svc_signals($svc) -name "svc_avail_$svc"
			$svc_signals($svc) set_state [my svc_avail $svc]
		}
		return $svc_signals($svc)
	}

	#>>>
	method svc_avail {svc} { #<<<
		dict exists $svcs $svc
	}

	#>>>
	method all_svcs {} { #<<<
		dict keys $svcs
	}

	#>>>
	method send_jm {jmid data} { #<<<
		my send [m2::msg::new [list \
			prev_seq	0 \
			seq			$jmid \
			data		$data \
			type		jm \
		]]
	}

	#>>>
	method send {msg} { #<<<
		my invoke_handlers send $msg
		my invoke_handlers send,[dict get $msg type] $msg

		?? {puts "<- Enqueuing msg: [m2::msg::display $msg]"}
		$queue enqueue [m2::msg::serialize $msg] [dict get $msg type] [dict get $msg seq] [dict get $msg prev_seq]
	}

	#>>>
	method unique_id {} { #<<<
		incr unique
	}

	#>>>

	method _got_msg {raw_msg} { #<<<
		set msg		[m2::msg::deserialize $raw_msg]

		switch -- [dict get $msg type] {
			svc_avail {
				foreach svc [dict get $msg data] {
					dict set svcs $svc	1
					if {[info exists svc_signals($svc)]} {
						$svc_signals($svc) set_state 1
					}
				}
				$dominos(svc_avail_changed) tip
			}

			svc_revoke {
				foreach svc [dict get $msg data] {
					dict unset svcs $svc
					if {[info exists svc_signals($svc)]} {
						$svc_signals($svc) set_state 0
					}
				}
				$dominos(svc_avail_changed) tip
			}
		}

		switch -- [dict get $msg type] {
			svc_avail -
			svc_revoke -
			req -
			rsj_req -
			ack -
			nack -
			pr_jm -
			jm -
			jm_can -
			jm_req -
			jm_disconnect {
				my invoke_handlers incoming $msg
				my invoke_handlers incoming,[dict get $msg type] $msg
			}

			default {
				error "Got unexpected msg type: ([dict get $msg type])"
			}
		}
	}

	#>>>
	method _attempt_connection {} { #<<<
		after cancel $connect_after_id; set connect_after_id	""

		set last_connection_attempt	[clock seconds]

		if {[info exists con]} {
			my _close_con
		}
		try {
			if {$uri eq ""} {
				set uri	"tcp://${ip}:${port}"
			}
			set con	[netdgram::connect_uri $uri]
			set queue	[netdgram::queue new]
			$queue attach $con

			oo::objdefine $queue forward closed {*}[my code _connection_lost]
			oo::objdefine $queue forward receive {*}[my code _got_msg]
			oo::objdefine $queue method assign {rawmsg type seq prev_seq} { #<<<
				switch -- $type {
					rsj_req - req {
						set seq
					}

					jm - jm_can {
						if {$prev_seq eq 0} {
							set seq
						} else {
							my variable _pending_jm_setup
							#puts stderr "[self] marking pending ($seq), prev_seq ($prev_seq)"
							dict set _pending_jm_setup $seq $prev_seq 1
							set prev_seq
						}
					}

					default {
						set prev_seq
					}
				}
			}

			#>>>
			oo::objdefine $queue method pick {queues} { #<<<
				my variable _pending_jm_setup
				if {![info exists _pending_jm_setup]} {
					set _pending_jm_setup	[dict create]
				}

				set q		[next $queues]
				set first	$q

				# Skip queues for jms that were setup in requests for which
				# we still haven't sent the ack or nack
				while {[dict exists $_pending_jm_setup $q]} {
					set q		[next $queues]
					if {$q eq $first} {
						set errmsg	"[self] Eeek - all queues have the pending flag set, should never happen.  Queues:"
						foreach p $queues {
							if {[dict exists $_pending_jm_setup $p]} {
								append errmsg "\n\t($p): ([dict get $_pending_jm_setup $p])"
							} else {
								append errmsg "\n\t($p): --"
							}
						}
						if {[info commands "dutils::daemon_log"] ne {}} {
							dutils::daemon_log LOG_ERR $errmsg
						} else {
							puts stderr $errmsg
						}
						# Should never happen
						break
					}
				}

				return $q
			}

			#>>>
			oo::objdefine $queue method sent {type seq prev_seq} { #<<<
				if {$type in {
					ack
					nack
				}} {
					my variable _pending_jm_setup
					if {![info exists _pending_jm_setup]} {
						set _pending_jm_setup	[dict create]
					}

					dict for {s ps} $_pending_jm_setup {
						foreach p [dict keys $ps] {
							if {$p eq $prev_seq} {
								dict unset _pending_jm_setup $s $p
								if {[dict size [dict get $_pending_jm_setup $s]] == 0} {
									dict unset _pending_jm_setup $s
								}
							}
						}
					}
				}
			}

			#>>>

			$con activate
		} on error {errmsg options} {
			if {[info exists queue] && [info object is object $queue]} {
				$queue destroy
				unset queue
			}
			if {[info exists con] && [info object is object $con]} {
				$con destroy
				# $con unset by close_con
			}
			my _schedule_reconnect_attempt
		} on ok {} {
			# Tell the node that we are an application rather than another node.
			# Mostly it doesn't care, but there are odd cases involving multiple
			# listeners on a single jm channel from a single app that cannot be
			# handled efficiently without it.
			my send [m2::msg::new [list \
					type	neighbour_info \
					data	$neighbour_info \
			]]

			$signals(connected) set_state 1
			my invoke_handlers connected
		}
	}

	#>>>
	method _svc_avail_changed {} { #<<<
		try {
			my invoke_handlers svc_avail_changed
		} on error {errmsg options} {
			puts "Error in handler: $errmsg\n[dict get $options -errorinfo]"
			dict incr options -level
			return -options $options $errmsg
		}
	}

	#>>>
	method _close_con {} { #<<<
		after cancel $connect_after_id; set connect_after_id	""
		if {[info exists con]} {
			try {
				if {[info object isa object $con]} {
					$con destroy
				}
			} finally {
				unset con
			}
		}
		set was_connected	[$signals(connected) state]
		$signals(connected) set_state 0
		if {$was_connected} {
			foreach svc [array names svc_signals] {
				$svc_signals($svc) set_state 0
			}
			my invoke_handlers lost_connection
		}
	}

	#>>>
	method _connection_lost {} { #<<<
		$signals(connected) set_state 0
		set svcs	[dict create]
		foreach svc [array names svc_signals] {
			puts "Connection lost, setting svc_signal($svc) to false"
			$svc_signals($svc) set_state 0
		}
		$dominos(svc_avail_changed) tip
		$dominos(svc_avail_changed) force_if_pending
		my invoke_handlers lost_connection
		my _schedule_reconnect_attempt
	}

	#>>>
	method _need_reconnect {} { #<<<
		$dominos(need_reconnect) tip
	}

	#>>>
	method _schedule_reconnect_attempt {} { #<<<
		if {[clock seconds] - $last_connection_attempt > $connection_retry} {
			set after_interval	"idle"
		} else {
			set after_interval	[expr {int($connection_retry * 1000)}]
		}
		set connect_after_id	[after $after_interval \
				[my code _attempt_connection]]
	}

	#>>>
	method neighbour_info {dict} { #<<<
		if {[dict exists $dict type] && [dict get $dict type] ne "application"} {
			error "neighbour info key \"type\" is reserved and must be \"application\""
		}

		set neighbour_info	[dict merge \
				$neighbour_info[unset neighbour_info] \
				$dict]

		my send [m2::msg::new [list \
				type	neighbour_info \
				data	$dict \
		]]
	}

	#>>>
}



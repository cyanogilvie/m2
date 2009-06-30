# vim: foldmarker=<<<,>>> ft=tcl foldmethod=marker shiftwidth=4 ts=4

# Signals:
#	connected()					- fired when connection is established
#	lost_connection()			- fired when connection is lost
#	send(msgobj)				- called with msg we are sending
#	send,$msgtype(msgobj)		- specific message type, ie send,svc_avail
#	incoming(msgobj)			- called with incoming msg
#	incoming,$msgtype(msgobj)	- specific message type, ie send,req

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
	}

	constructor {args} { #<<<
		array set dominos		{}
		array set svc_signals	{}

		sop::domino new dominos(need_reconnect) -name "[self] need_reconnect"
		sop::signal new signals(connected) -name "[self] connected"
		sop::domino new dominos(svc_avail_changed) -name "[self] svc_avail_changed"

		$dominos(svc_avail_changed) attach_output [my code _svc_avail_changed]
		$dominos(need_reconnect) attach_output [my code _attempt_connection]

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
		set msg	[m2::msg new new \
			type	svc_avail \
			seq		[incr unique] \
			data	$args \
		]
		my send $msg
	}

	#>>>
	method revoke_svcs {args} { #<<<
		if {![$signals(connected) state]} return
		set msg	[m2::msg new new \
			type	svc_revoke \
			seq		[incr unique] \
			data	$args \
		]
		my send $msg
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
		return [dict exists $svcs $svc]
	}

	#>>>
	method send_jm {jmid data} { #<<<
		set jm	[m2::msg new new \
			prev_seq	0 \
			seq			$jmid \
			data		$data \
			type		jm \
		]
		my send $jm
	}

	#>>>
	method send {msg} { #<<<
		my invoke_handlers send $msg
		my invoke_handlers send,[$msg type] $msg

		set sdata	[$msg serialize]
		$queue enqueue $sdata [$msg get type] [$msg get seq] [$msg get prev_seq]
	}

	#>>>
	method unique_id {} { #<<<
		incr unique
	}

	#>>>

	method _got_msg {msg} { #<<<
		#puts "got_msg type: ([$msg type])"
		switch -- [$msg type] {
			svc_avail {
				foreach svc [$msg data] {
					dict set svcs $svc	1
					if {[info exists svc_signals($svc)]} {
						$svc_signals($svc) set_state 1
					}
				}
				$dominos(svc_avail_changed) tip
			}

			svc_revoke {
				foreach svc [$msg data] {
					dict unset svcs $svc
					if {[info exists svc_signals($svc)]} {
						$svc_signals($svc) set_state 0
					}
				}
				$dominos(svc_avail_changed) tip
			}
		}

		switch -- [$msg type] {
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
				my invoke_handlers incoming,[$msg type] $msg
			}

			default {
				error "Got unexpected msg type: ([$msg type])"
			}
		}
	}

	#>>>
	method _attempt_connection {} { #<<<
		my log notice
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
			oo::objdefine $queue forward receive {*}[my code _receive_raw]
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
							dict set _pending_jm_setup $seq $prev_seq
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
						if {[info commands "dutils::daemon_log"] ne {}} {
							dutils::daemon_log LOG_ERR "Eeek - all queues have the pending flag set, should never happen"
						} else {
							puts stderr "Eeek - all queues have the pending flag set, should never happen"
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

					dict for {s p} $_pending_jm_setup {
						if {$p eq $prev_seq} {
							dict unset _pending_jm_setup $s
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
			set msg	[m2::msg new new \
					type	neighbour_info \
					data	[list type application] \
			]
			my send $msg

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
	method _receive_raw {raw_msg} { #<<<
		set msg			[m2::msg new deserialize $raw_msg]

		my _got_msg $msg
	}

	#>>>
	method _connection_lost {} { #<<<
		$signals(connected) set_state 0
		set svcs	[dict create]
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
}



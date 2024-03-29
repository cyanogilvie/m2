# vim: foldmarker=<<<,>>> ft=tcl foldmethod=marker shiftwidth=4 ts=4

oo::class create m2::api {
	superclass cflib::props sop::signalsource

	method _properties {} {
		format {%s
			variable uri				""
			variable connection_retry	10
		} [next]
	}

	variable {*}{
		signals
		svc_signals
		neighbour_info
		uri

		dominos
		con
		unique
		svcs
		connect_after_id
		queue
		queue_roundrobin
		last_connection_attempt
	}

	constructor args { #<<<
		my _init_props $args

		if {[llength [info commands log]] == 0} {proc log {lvl msg} {puts stderr $msg}}

		if {[self next] ne ""} next

		set unique					0
		set svcs					[dict create]
		set connect_after_id		""
		set queue_roundrobin		{}
		set last_connection_attempt	0

		if {"::oo::Helpers::cflib" ni [namespace path]} {
			namespace path	[concat [namespace path] {
				::oo::Helpers::cflib
			}]
		}

		package require evlog

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

		$dominos(svc_avail_changed) attach_output [code svc_avail_changed]
		$dominos(need_reconnect) attach_output [code _attempt_connection]

		package require netdgram::tcp
		oo::define netdgram::connectionmethod::tcp method default_port {} {
			return 5300
		}

		my _init

		prop register_handler onchange,uri [code _need_reconnect]
		my _need_reconnect
	}

	#>>>
	destructor { #<<<
		if {[info exists connect_after_id] && $connect_after_id ne ""} {
			after cancel $connect_after_id; set connect_after_id	""
		}
		my _close_con
		my _destroy
		if {[self next] ne ""} next
	}

	#>>>

	# These are like constructor / destructor, but work for mixins
	method _init {} {}
	method _destroy {} {}

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
	method send msg { #<<<
		?? {evlog event m2.queue_msg {[list to $uri msg $msg]}}
		$queue enqueue [m2::msg::serialize $msg] [dict get $msg type] [dict get $msg seq] [dict get $msg prev_seq]
	}

	#>>>
	method unique_id {} { #<<<
		incr unique
	}

	#>>>

	method _got_msg_raw raw_msg { #<<<
		#tailcall my _got_msg [m2::msg::deserialize $raw_msg]
		my _got_msg [m2::msg::deserialize $raw_msg]
	}

	#>>>
	method _got_msg msg { #<<<
		?? {evlog event m2.receive_msg {[list from $uri msg $msg]}}

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

		my _incoming $msg
	}

	#>>>
	method _attempt_connection {} { #<<<
		after cancel $connect_after_id; set connect_after_id	""

		set last_connection_attempt	[clock seconds]

		if {[info exists con]} {
			my _close_con
		}
		set uri	[prop get uri]
		if {$uri eq ""} {
			set uri	"tcp://${ip}:${port}"
		}
		try {
			my _create_con $uri
		} on error {errmsg options} {
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
		}
	}

	#>>>
	method _create_con a_uri { #<<<
		try {
			set con	[netdgram::connect_uri $a_uri]
			set queue	[m2::queue_fancy new]
			#set queue	[m2::queue_fifo new]
			$queue attach $con

			oo::objdefine $queue forward closed {*}[code _connection_lost]
			oo::objdefine $queue forward receive {*}[code _got_msg_raw]

			$con activate
		} on error {errmsg options} {
			?? {
				log error "Error connecting to $a_uri:\n[dict get $options -errorinfo]"
			}
			if {[info exists queue] && [info object is object $queue]} {
				$queue destroy
				unset queue
			}
			if {[info exists con] && [info object is object $con]} {
				$con destroy
				# $con unset by close_con
			}

			return -options $options $errmsg
		}
	}

	#>>>
	method svc_avail_changed {} {}
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
		my _lost_connection
		my _schedule_reconnect_attempt
	}

	#>>>
	method _lost_connection {} {}
	method _need_reconnect {} { #<<<
		$dominos(need_reconnect) tip
	}

	#>>>
	method _schedule_reconnect_attempt {} { #<<<
		if {[clock seconds] - $last_connection_attempt > [prop @connection_retry]} {
			set after_interval	"idle"
		} else {
			set after_interval	[expr {int([prop @connection_retry] * 1000)}]
		}
		set connect_after_id [after $after_interval [code _attempt_connection]]
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
	method station_id {} { #<<<
		[$queue con] human_id
	}

	#>>>
}



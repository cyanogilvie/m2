# vim: foldmarker=<<<,>>> ft=tcl foldmethod=marker shiftwidth=4 ts=4

# Signals:
#	connected()					- fired when connection is established
#	lost_connection()			- fired when connection is lost
#	send(msgobj)				- called with msg we are sending
#	send,$msgtype(msgobj)		- specific message type, ie send,svc_avail
#	incoming(msgobj)			- called with incoming msg
#	incoming,$msgtype(msgobj)	- specific message type, ie send,req

m2::pclass create m2::api {
	#superclass m2::handlers m2::signalsource m2::baselog
	superclass m2::pclassbase m2::signalsource m2::handlers m2::baselog

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

	constructor {args} { #<<<
		array set dominos	{}

		m2::domino new dominos(need_reconnect) -name "[self] need_reconnect"
		m2::signal new signals(connected) -name "[self] connected"
		m2::domino new dominos(svc_avail_changed) -name "[self] svc_avail_changed"

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
		$queue enqueue $sdata $msg
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
				}
				$dominos(svc_avail_changed) tip
			}

			svc_revoke {
				foreach svc [$msg data] {
					dict unset svcs $svc
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
			#oo::objdefine $queue forward assign {*}[my code _assign_queue]
			oo::objdefine $queue method assign {rawmsg msg} {
				switch -- [$msg get type] {
					"rsj_req" - "req" - "jm"	{$msg get seq}
					default						{$msg get prev_seq}
				}
			}
			# Use the default queue pick behaviour of round-robin
			#oo::objdefine $queue forward pick {*}[my code _pick_queue]

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
	method _assign_queue {raw_msg msg} { #<<<
		set m	[$msg get_data]
		switch -- [dict get $m type] {
			"rsj_req" -
			"req" -
			"jm" {
				return [dict get $m seq]
			}

			default {
				return [dict get $m prev_seq]
			}
		}
	}

	#>>>
	method _pick_queue {queues} { #<<<
		# Note: not used, uses the default netdgram::queue::pick behaviour (round-robin)

		# Default behaviour: roundrobin of queues
		my variable roundrobin
		set new_roundrobin	{}

		# Trim queues that have gone away
		foreach queue $roundrobin {
			if {$queue ni $queues} continue
			lappend new_roundrobin $queue
		}

		# Append any new queues to the end of the roundrobin
		foreach queue $queues {
			if {$queue in $new_roundrobin} continue
			lappend new_roundrobin $queue
		}

		# Pull the next queue off head and add it to the tail
		set roundrobin	[lassign $new_roundrobin next]
		lappend roundrobin	$next

		return $next
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



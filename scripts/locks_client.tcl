# vim: foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4 ft=tcl

# Signals fired:
#	lock_lost()				- fired when the lock is lost
#	lock_lost_detail(info)	- also fired on lock loss, but passes data, which
#							may contain a reason

cflib::pclass create m2::locks::client {
	superclass sop::signalsource cflib::handlers

	property tag		""
	property connector	""
	property id			""

	variable {*}{
		lock_jmid
		lock_prev_seq
		heartbeat_interval
		heartbeat_afterid
		signals
	}

	constructor {args} { #<<<
		set heartbeat_interval	""
		set heartbeat_afterid	""

		sop::signal new signals(locked) -name "[self] locked"

		my configure {*}$args

		foreach reqf {tag connector id} {
			if {[set $reqf] eq ""} {
				error "Must set -$reqf"
			}
		}

		my relock
	}

	#>>>
	destructor { #<<<
		if {[info exists lock_jmid]} {
			$connector jm_disconnect $lock_jmid $lock_prev_seq
			unset lock_jmid
			unset lock_prev_seq
			$signals(locked) set_state 0
		}
		after cancel $heartbeat_afterid; set heartbeat_afterid	""
	}

	#>>>

	method relock {} { #<<<
		if {[$signals(locked) state] && [info exists lock_jmid]} {
			log warning "Already have a lock"
			return
		}
		try {
			set lock_info	[$connector req_jm $tag $id [my code _lock_cb]]
		} on error {errmsg options} {
			throw [list lock_failed $errmsg] \
					"Could not get lock on $id: $errmsg"
		} on ok {} {
			$signals(locked) set_state 1
		}

		if {[dict exists $lock_info heartbeat]} {
			my _setup_heartbeat	[dict get $lock_info heartbeat]
		}
	}

	#>>>
	method lock_req {op data} { #<<<
		if {![$signals(locked) state] || ![info exists lock_jmid]} {
			error "No lock held"
		}
		$connector chan_req $lock_jmid [list $op $data]
	}

	#>>>
	method unlock {} { #<<<
		if {![$signals(locked) state] || ![info exists lock_jmid]} {
			#log warning "No lock held"
			return
		}
		try {
			$connector jm_disconnect $lock_jmid $lock_prev_seq
			unset lock_jmid
			unset lock_prev_seq
			$signals(locked) set_state 0

			my invoke_handlers lock_lost
			my invoke_handlers lock_lost_detail "Explicit unlock"
		} on error {errmsg options} {
			log error "Unhandled error: $errmsg\n[dict get $options -errorinfo]"
		}
	}

	#>>>

	# Protected
	method lock_jm_update {data} { #<<<
		# Override this in the derived class to handle app specific jm updates
		log error "got jm update we weren't expecting"
	}

	#>>>

	method _lock_cb {msg} { #<<<
		set jmid	[dict get $msg seq]

		switch -- [dict get $msg type] {
			pr_jm { #<<<
				if {[info exists lock_jmid]} {
					error "Unexpected pr_jm ($jmid), already have lock_jmid: ($lock_jmid)"
				}

				set lock_jmid		$jmid
				set lock_prev_seq	[dict get $msg prev_seq]
				$signals(locked) set_state 1
				#>>>
			}
			jm { #<<<
				my lock_jm_update [dict get $msg data]
				#>>>
			}
			jm_can { #<<<
				if {
					[info exists lock_jmid] &&
					$jmid eq $lock_jmid
				} {
					?? {log debug "lock channel canned: ($lock_jmid)"}
					unset lock_jmid
					unset lock_prev_seq
					$signals(locked) set_state 0
					my invoke_handlers lock_lost
					my invoke_handlers lock_lost_detail [dict get $msg data]
				} else {
					error "Unknown jmid cancelled: ($jmid)"
				}
				#>>>
			}
			default { #<<<
				log error "unexpected type: ([dict get $msg type])"
				#>>>
			}
		}
	}

	#>>>
	method _setup_heartbeat {heartbeat} { #<<<
		set heartbeat_interval	[expr {$heartbeat - 60}]
		if {$heartbeat <= 0} {
			log warning "Really short heartbeat requested: $heartbeat"
			set heartbeat	1
		}

		set heartbeat_afterid	[after [expr {$heartbeat_interval * 1000}] \
				[my code _send_heartbeat]]
	}

	#>>>
	method _send_heartbeat {} { #<<<
		after cancel $heartbeat_afterid; set heartbeat_afterid	""

		if {![info exists lock_jmid]} {
			log warning "No lock channel to send heartbeat over"
			return
		}
		$connector chan_req_async $lock_jmid [list "_heartbeat"] [list apply {
			{msg} {
				# we don't really care
			}
		}]

		set heartbeat_afterid	[after [expr {$heartbeat_interval * 1000}] \
				[my code _send_heartbeat]]
	}

	#>>>
}



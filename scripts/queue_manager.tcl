# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create m2::queue_common {
	superclass netdgram::queue

	variable {*}{
		queue_idx
	}

	method pick a_queues {
		# A less totally fair but faster round-robin implementation
		incr queue_idx
		set queue_idx	[expr {$queue_idx % [llength $a_queues]}]
		lindex $a_queues $queue_idx
	}
}

oo::class create m2::queue_fancy { #<<<
	superclass m2::queue_common

	variable _pending_jm_setup

	constructor {} { #<<<
		if {[self next] ne ""} next

		set _pending_jm_setup	[dict create]
	}

	#>>>

	method assign {rawmsg type seq prev_seq} { #<<<
		try {
			switch -exact -- $type {
				req - jm - jm_can {set seq}

				pr_jm {
					?? {log debug "Flagging pending $seq $prev_seq"}
					dict set _pending_jm_setup $seq $prev_seq 1
					set prev_seq
				}

				default {set prev_seq}
			}
		} on ok q {
			?? {log debug "Picked queue for $type $seq $prev_seq -> $q"}
			set q
		}
	}

	#>>>
	method pick queues { #<<<
		if {[llength $queues] == 1} {return [lindex $queues 0]}

		set q		[next $queues]
		set first	$q

		# Skip queues for jms that were setup in requests for which
		# we still haven't sent the ack or nack
		while {[dict exists $_pending_jm_setup $q]} {
			?? {log debug "Skipping queue $q as it has pending_jm flag set"}
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
				log error $errmsg
				# Should never happen
				break
			}
		}

		?? {log debug "[self] picked $q of ($queues)"}
		set q
	}

	#>>>
	method sent {type seq prev_seq} { #<<<
		?? {log debug "[self] Dequeued $type $seq $prev_seq"}
		if {$type in {
			ack
			nack
		}} {
			dict for {s ps} $_pending_jm_setup {
				foreach p [dict keys $ps] {
					if {$p eq $prev_seq} {
						?? {log debug "[self] Removing pending flag for ($s), $type prev_seq ($prev_seq) matches ($p)"}
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
	method shortcut_ok {type seq prev_seq} { #<<<
		if {$type eq "pr_jm"} {return 0}
		if {$type in {ack nack}} {return 1}
		expr {[dict size $_pending_jm_setup] == 0}
	}

	#>>>
}

#>>>

oo::class create m2::queue_fifo { #<<<
	superclass m2::queue_common

	method assign args {return _fifo}
	method pick queues {return _fifo}
	method shortcut_ok args {return 1}
}

#>>>

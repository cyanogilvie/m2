# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create chat {
	constructor {} { #<<<
		[m2 signal_ref connected] attach_output \
				[namespace code {my _connected_changed}]
	}

	#>>>
	destructor { #<<<
		[m2 signal_ref connected] detach_output \
				[namespace code {my _connected_changed}]
	}

	#>>>
	method _connected_changed {newstate} { #<<<
		puts "Connection state: [expr {$newstate ? "connected" : "not connected"}]"
		if {$newstate} {
			m2 handle_svc "chat" [namespace code {my _handle_chat}]
		} else {
			m2 handle_svc "chat" ""
		}
	}

	#>>>
	method _handle_chat {seq data} { #<<<
		try {
			set args	[lassign $data op]
			switch -- $op {
				join { #<<<
					set channel	[lindex $args 0]
					my log notice "Got request to join channel \"$channel\""
					set jmid	[my _get_or_create_channel $channel]
					m2 pr_jm $jmid $seq [list init [my _channel_history $channel]]
					my log notice "Sending pr_jm ($jmid) with channel history for \"$channel\""
					m2 ack $seq ""
					#>>>
				}

				list { #<<<
					my variable channel_jmids
					m2 ack $seq [dict keys $channel_jmids]
					#>>>
				}

				default { #<<<
					m2 nack $seq "Invalid operation: ($op)"
					#>>>
				}
			}
			m2 ack $seq "hello, $data"
		} on error {errmsg options} {
			my log error "Unhandled error in _handle_chat: $errmsg\n[dict get $options -errorinfo]"
			if {![m2 answered $seq]} {
				m2 nack $seq "Internal error"
			}
		}
	}

	#>>>
	method _get_or_create_channel {channel} { #<<<
		my variable channel_jmids
		if {![info exists channel_jmids]} {
			set channel_jmids	[dict create]
		}

		if {![dict exists $channel_jmids $channel]} {
			my log notice "No channel registered for \"$channel\", creating"
			set jmid	[m2 unique_id]
			dict set channel_jmids $channel $jmid
			m2 chans register_chan $jmid \
					[namespace code [list my _channel_cb $channel]]
			my log notice "Registered channel jmid ($jmid) for channel \"$channel\""
		} else {
			my log notice "Channel \"$channel\" already registered, returning jmid ([dict get $channel_jmids $channel])"
		}

		return [dict get $channel_jmids $channel]
	}

	#>>>
	method _channel_cb {channel op data} { #<<<
		switch -- $op {
			cancelled {
				my log notice "All destinations for channel \"$channel\" disconnected"
			}

			req {
				lassign $data seq prev_seq reqdata
				try {
					lassign $reqdata op args
					my log info "Got chan request for \"$channel\": $op"
					switch -- $op {
						say { #<<<
							set msg	$args
							my log notice "message: ($msg)"
							my _say $channel $msg
							m2 ack $seq ""
							#>>>
						}

						default { #<<<
							m2 nack $seq "Invalid operation ($op)"
							#>>>
						}
					}
				} on error {errmsg options} {
					my log error "Unhandled error in channel request for \"$channel\": $errmsg\n[dict get $options -errorinfo]"
					if {![m2 answered $seq]} {
						m2 nack $seq "Internal error"
					}
				}
			}

			default {
				my log warning "Unexpected channel op: ($op) on \"$channel\""
			}
		}
	}

	#>>>
	method _channel_history {channel} { #<<<
		my variable channel_history
		if {![info exists channel_history]} {
			set channel_history	[dict create]
		}

		if {![dict exists $channel_history $channel]} {
			set history	{}
		} else {
			set history	[dict get $channel_history $channel]
		}

		return $history
	}

	#>>>
	method _say {channel msg} { #<<<
		my variable channel_history

		set jmid	[my _get_or_create_channel $channel]

		my log notice "Broadcasting new message on channel \"$channel\"($jmid): $msg"

		dict lappend channel_history $channel [list [clock microseconds] $msg]

		m2 jm $jmid [list say [clock microseconds] $msg]
	}

	#>>>
	method log {lvl msg} { #<<<
		switch -- $lvl {
			trivia - debug	{set syslog_prio	"LOG_DEBUG"}
			notice			{set syslog_prio	"LOG_INFO"}
			warn - warning	{set syslog_prio	"LOG_WARNING"}
			error			{set syslog_prio	"LOG_ERR"}
			fatal			{set syslog_prio	"LOG_CRIT"}

			default {
				if {$lvl in {
					LOG_EMERG
					LOG_ALERT
					LOG_CRIT
					LOG_ERR
					LOG_WARNING
					LOG_NOTICE
					LOG_INFO
					LOG_DEBUG
				}} {
					set syslog_prio	$lvl
				} else {
					set syslog_prio	"LOG_ERR"
				}
			}
		}
		daemon_log $syslog_prio $msg
	}

	unexport log
	#>>>
}


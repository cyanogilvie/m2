# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

cflib::pclass create gui {
	variable {*}{
		toplevel
		w
		utterance
		signals
	}

	property title "" _set_title

	constructor {args} { #<<<
		sop::gate new signals(ready) -name "[self] ready" -mode and
		sop::signal new signals(chat_available) -name "[self] chat_available"
		$signals(ready) attach_input [m2 signal_ref connected]

		set toplevel	[toplevel .main]
		wm protocol $toplevel WM_DELETE_WINDOW [my code _toplevel_died]
		my hide

		set w		[ttk::frame $toplevel.f]
		pack $w -fill both -expand true

		ttk::notebook $w.tabs

		set utterance	""
		ttk::entry $w.entry -textvariable [namespace which -variable utterance]
		bind $w.entry <Key-Return> [namespace code {my _say}]
		ttk::button $w.say -text "Send" -command [namespace code {my _say}]

		grid $w.tabs -columnspan 2 -row 1 -column 1 -sticky news
		grid $w.entry -row 2 -column 1 -sticky ew
		grid $w.say -row 2 -column 2

		grid rowconfigure $w 1 -weight 1
		grid columnconfigure $w 1 -weight 1

		my configure {*}$args

		wm geometry $toplevel "1024x768"

		m2 register_handler svc_avail_changed \
				[namespace code {my _svc_avail_changed}]
		$signals(ready) attach_output [namespace code {my _ready_changed}]

		bind $w.tabs <<NotebookTabChanged>> [namespace code {my _tab_selected}]
	}

	#>>>
	destructor { #<<<
		if {[info exists toplevel] && [winfo exists $toplevel]} {
			try {
				wm protocol $toplevel WM_DELETE_WINDOW {}
				destroy $toplevel
			} on error {errmsg options} {
				puts stderr "Error destroying $toplevel: $errmsg"
			}
		}
		exit
	}

	#>>>
	method _toplevel_died {} { #<<<
		my destroy
	}

	#>>>
	method _set_title {} { #<<<
		wm title $toplevel $title
	}

	#>>>
	method show {} { #<<<
		wm deiconify $toplevel
	}

	#>>>
	method hide {} { #<<<
		wm withdraw $toplevel
	}

	#>>>
	method _tab_selected {} { #<<<
		my variable current_channel
		set current_channel	[$w.tabs select]
	}

	#>>>
	method _say {} { #<<<
		my variable current_channel channel_jmids
		puts "utterance: ($utterance)"
		if {[string index $utterance 0] eq "/"} {
			my _handle_command $utterance
		} else {
			if {![info exists current_channel]} {
				puts stderr "No current channel"
			} else {
				set jmid	[dict get $channel_jmids $current_channel]
				m2 rsj_req $jmid [list say $utterance] [list apply {
					{msg_data} {
						dict with msg_data {}
						switch -- $type {
							ack {}
							nack {
								puts stderr "Say was denied: $data"
							}

							default {
								puts stderr "Unexpected response to say: ($type)"
							}
						}
					}
				}]
			}
		}
		set utterance	""
	}

	#>>>
	method _handle_command {raw} { #<<<
		my variable current_channel channel_jmids

		set rest	[lassign $raw cmd]

		switch -- $cmd {
			"/join" { #<<<
				set channel	[lindex $rest 0]
				coroutine chan_$channel my _join $channel
				#>>>
			}

			"/leave" { #<<<
				if {![info exists current_channel]} {
					puts stderr "No current channel"
				} else {
					set jmid	[dict get $channel_jmids $current_channel]
					m2 rsj_req $jmid [list leave] [list apply {
						{msg_data} {
							dict with msg_data {}
							switch -- $type {
								ack {
									puts "left \"$current_channel\""
								}

								nack {
									puts stderr "Problem leaving channel: $data"
								}

								default {
									puts stderr "Unexpected response to leave: ($type)"
								}
							}
						}
					}]
				}
				#>>>
			}

			default { #<<<
				puts stderr "Invalid command \"$cmd\""
				#>>>
			}
		}
	}

	#>>>
	method _join {channel} { #<<<
		my variable chanseq channel_jmids
		set myseq	[incr chanseq]
		set chanwin	[ttk::frame $w.tabs.chan$myseq]
		text $chanwin.msgs -background white \
				-yscrollcommand [list $chanwin.vsb set]
		ttk::scrollbar $chanwin.vsb -orient vertical \
				-command [list $chanwin.msgs yview]

		grid $chanwin.msgs -row 1 -column 1 -sticky news
		grid $chanwin.vsb -row 1 -column 2 -sticky ns
		grid columnconfigure $chanwin 1 -weight 1
		grid rowconfigure $chanwin 1 -weight 1

		$w.tabs add $chanwin -text $channel -sticky news

		puts stderr "Sending request to join channel \"$channel\""
		m2 req "chat" [list join $channel] [list apply {
			{coro args} {$coro $args}
		} [info coroutine]]

		while {1} {
			lassign [yield] msg_data

			try {
				dict with msg_data {}
			} on error {errmsg options} {
				puts stderr "Cannot parse response: ($msg_data)"
				continue
			}
			puts "channel \"$channel\": got response ($type)"

			switch -- $type {
				ack { #<<<
					puts "Joined channel \"$channel\""
					#>>>
				}

				nack { #<<<
					puts stderr "Join channel \"$channel\" rejected: $data"
					break
					#>>>
				}

				pr_jm { #<<<
					set payload	[lassign $data op]
					if {$op eq "init"} {
						puts stderr "got jm channel setup: ($seq) for \"$channel\""
						dict set channel_jmids $chanwin $seq
						set history	[lindex $payload 0]
						foreach hist $history {
							lassign $hist timestamp message
							puts stderr "processing hist: ($timestamp) ($message)"
							$chanwin.msgs insert end "$message\n"
						}
					}
					#>>>
				}

				jm { #<<<
					if {$seq == [dict get $channel_jmids $chanwin]} {
						set rest	[lassign $data op]
						switch -- $op {
							say {
								lassign $rest timestamp message
								$chanwin.msgs insert end "$message\n"
							}

							default {
								puts stderr "Not expecting op \"$op\" on jm channel for \"$channel\""
							}
						}
					} else {
						puts stderr "Received jm on unknown channel: ($seq)"
					}
					#>>>
				}

				jm_can { #<<<
					if {$seq == [dict get $channel_jmids $chanwin]} {
						puts stderr "Channel \"$channel\" closed from server"
						dict unset channel_jmids $chanwin
						break
					} else {
						puts stderr "Unknown jm cancelled: ($seq)"
					}
					#>>>
				}

				default { #<<<
					puts stderr "Not expecting response type ($type)"
					#>>>
				}
			}
		}

		$w.tabs forget $chanwin
		destroy $chanwin
	}

	#>>>
	method _svc_avail_changed {} { #<<<
		$signals(chat_available) set_state [m2 svc_avail "chat"]
	}

	#>>>
	method _ready_changed {newstate} { #<<<
		puts "ready state: [expr {$newstate ? "ready" : "not ready"}]"

		if {$newstate} {
			$w.entry state !disabled
			$w.say state !disabled
		} else {
			$w.entry state disabled
			$w.say state disabled
		}
	}

	#>>>
}



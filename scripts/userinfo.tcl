# vim: ft=tcl foldmarker=<<<,>>> foldmethod=marker ts=4 shiftwidth=4

# Handlers fired
#	session_killed()	- When the userinfo chan from the authenticator is
#						  jm_can'ed (authenticator died, user kicked, etc)

oo::class create m2::userinfo {
	superclass sop::signalsource cflib::handlers

	variable {*}{
		username
		auth
		svc
		fqun
		perms
		attribs
		prefs
		userinfo_jmid
		userinfo_prev_seq
		type
		signals
		authchan
	}

	constructor {a_username a_auth a_svc a_authchan} { #<<<
		if {[self next] ne ""} next

		namespace path [concat [namespace path] {
			::oo::Helpers::cflib
		}]

		set username	$a_username
		set auth		$a_auth
		set svc			$a_svc
		set authchan	$a_authchan

		set perms		[dict create]
		set attribs		[dict create]
		set prefs		[dict create]

		set typesplit	[split $username %]
		if {[llength $typesplit] > 1} {
			set type	[lindex $typesplit 0]
			set username	[join [lrange $typesplit 1 end] %]
		} else {
			set type	"user"
		}

		if {$type ni {"user" "svc"}} {
			throw [list invalid_user_type $type] "Invalid type: ($type)"
		}

		set fqun	[join [list $type $username] %]

		sop::signal new signals(userinfo_chan_valid) \
				-name "Userinfo($username) userinfo_chan_valid"
		sop::signal new signals(got_perms) \
				-name "Userinfo($username) got_perms"
		sop::signal new signals(got_attribs) \
				-name "Userinfo($username) got_attribs"
		sop::signal new signals(got_prefs) \
				-name "Userinfo($username) got_prefs"
		sop::gate new signals(got_all) -mode "and" \
				-name "Userinfo($username) got_all"
		$signals(userinfo_chan_valid) attach_output [code _userinfo_chan_valid_changed]
		$signals(got_all) attach_input $signals(got_perms)
		$signals(got_all) attach_input $signals(got_attribs)
		$signals(got_all) attach_input $signals(got_prefs)

		my _setup_userinfo_chan
	}

	#>>>
	destructor { #<<<
		?? {log debug "userinfo object for ($fqun) dieing"}
		if {
			[info exists userinfo_jmid] &&
			[info exists userinfo_prev_seq] &&
			[info exists auth]
		} {
			?? {log debug "jm_disconnecting from userinfo chan ($userinfo_jmid, $userinfo_prev_seq)"}
			$auth jm_disconnect $userinfo_jmid $userinfo_prev_seq
			unset userinfo_jmid
			unset userinfo_prev_seq
		}

		if {[self next] ne ""} next
	}

	#>>>

	method authchan {} { #<<<
		set authchan
	}

	#>>>
	method name {} { #<<<
		return $username
	}

	#>>>
	method perm {permname} { #<<<
		if {![$signals(got_perms) state]} {
			log warning "still waiting for perms list from Authenticator backend..."
			my waitfor got_perms
			log warning "ok, got perms list, proceeding"
		}

		dict exists $perms $permname
	}

	#>>>
	method attrib {attrib args} { #<<<
		if {![$signals(got_attribs) state]} {
			log warning "still waiting for attribs from Authenticator backend..."
			my waitfor got_attribs
			log warning "ok, got attribs, proceeding"
		}

		if {[dict exists $attribs $attrib]} {
			return [dict get $attribs $attrib]
		}
		if {[llength $args] >= 1} {
			return [lindex $args 0]
		}
		throw [list undefined_attrib $attrib] \
				"No value set for attrib ($attrib) for user ($username)"
	}

	#>>>
	method pref {pref args} { #<<<
		if {![$signals(got_prefs) state]} {
			log warning "still waiting for prefs from Authenticator backend..."
			my waitfor got_prefs
			log warning "ok, got prefs, proceeding"
		}

		if {[dict exists $prefs $pref]} {
			return [dict get $prefs $pref]
		}
		if {[llength $args] >= 1} {
			return [lindex $args 0]
		}
		throw [list undefined_pref $pref] \
				"No value set for pref ($pref) for user ($username)"
	}

	#>>>
	method get_pbkey {} { #<<<
		$auth get_user_pbkey $fqun
	}

	#>>>
	method type {} { #<<<
		return $type
	}

	#>>>

	method _setup_userinfo_chan {} { #<<<
		$auth enc_chan_req [list userinfo_setup $fqun] \
				[code _setup_userinfo_chan_resp]
	}

	#>>>
	method _setup_userinfo_chan_resp {msg} { #<<<
		#?? {log debug "Got userinfo chan resp: ([dict get $msg data])\n[m2::msg::display $msg]"}
		switch -- [dict get $msg type] {
			ack { #<<<
				#>>>
			}

			nack { #<<<
				log error "were denied userinfo channel setup: ([dict get $msg data])"
				$signals(userinfo_chan_valid) set_state 0
				#>>>
			}

			pr_jm { #<<<
				if {![info exists userinfo_jmid]} {
					set userinfo_jmid		[dict get $msg seq]
					set userinfo_prev_seq	[dict get $msg prev_seq]
					$signals(userinfo_chan_valid) set_state 1
				} elseif {$userinfo_jmid != [dict get $msg seq]} {
					log error "Got another channel setup ([dict get $msg seq]), already have userinfo_jmid: ($userinfo_jmid)"
				}

				my _update_userinfo [dict get $msg data]
				#>>>
			}

			jm { #<<<
				my _update_userinfo [dict get $msg data]
				#>>>
			}

			jm_can { #<<<
				if {![info exists userinfo_jmid]} {
					log error "no userinfo_jmid set, but got jm_can"
					return
				}
				if {[dict get $msg seq] != $userinfo_jmid} {
					log error "unknown channel cancelled"
					return
				}

				log debug "userinfo_chan cancelled"
				unset userinfo_jmid
				$signals(userinfo_chan_valid) set_state 0
				my invoke_handlers session_killed
				log debug "Userinfo chan canned"
				#>>>
			}

			default { #<<<
				log error "unexpected type: ([dict get $msg type])"
				#>>>
			}
		}
	}

	#>>>
	method _update_userinfo {data} { #<<<
		switch -- [lindex $data 0] {
			perms { #<<<
				foreach permname [lindex $data 1] {
					switch -- [string index $permname 0] {
						"-" {
							dict unset perms [string range $permname 1 end]
						}

						"+" {
							dict set perms [string range $permname 1 end]	1
						}

						default {
							dict set perms $permname	1
						}
					}
				}
				$signals(got_perms) set_state 1
				#>>>
			}

			attribs { #<<<
				foreach {attrib value} [lindex $data 1] {
					switch -- [string index $attrib 0] {
						"-" {
							dict unset attribs [string range $attrib 1 end]
						}

						"+" {
							dict set attribs [string range $attrib 1 end] $value
						}

						default {
							dict set attribs $attrib	$value
						}
					}
				}
				$signals(got_attribs) set_state 1
				#>>>
			}

			prefs { #<<<
				foreach {pref value} [lindex $data 1] {
					switch -- [string index $pref 0] {
						"-" {
							dict unset prefs [string range $pref 1 end]
						}

						"+" {
							dict set prefs [string range $pref 1 end]	$value
						}

						default {
							dict set prefs $pref	$value
						}
					}
				}
				$signals(got_prefs) set_state 1
				#>>>
			}

			default { #<<<
				log error "unexpected update type: ([lindex $data 0])"
				#>>>
			}
		}
	}

	#>>>
	method _userinfo_chan_valid_changed {newstate} { #<<<
		if {$newstate == 0} {
			$signals(got_prefs) set_state 0
			$signals(got_perms) set_state 0
			$signals(got_attribs) set_state 0
		}
	}

	#>>>
}



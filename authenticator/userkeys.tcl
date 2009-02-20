# vim: foldmarker=<<<,>>> foldmethod=marker ts=4 shiftwidth=4 ft=tcl

oo::class create Userkeys {
	superclass cflib::baselog

	variable {*}{
		userkey_expires_hours
		userkey_grace_minutes
		userkeys
		userchans
		expires
	}

	constructor {} { #<<<
		my log debug [self]

		set userkey_expires_hours	4.0
		#set userkey_expires_hours	0.01
		set userkey_grace_minutes	1.0
		#set userkey_grace_minutes	0.2

		set userkeys	[dict create]
		set userchans	[dict create]
		set expires		[dict create]

		users register_handler userreq_session_pbkey_update \
				[namespace code {my userkey_update}]
	}

	#>>>
	destructor { #<<<
		my log debug [self]
		dict for {user afterid} $expires {
			after cancel $afterid
			dict unset expires $user
		}
	}

	#>>>

	method userkey_update {user seq prev_seq rest} { #<<<
		my log debug
		set jmid	[m2 unique_id]
		dict set userkeys $user	[lindex $rest 0]
		m2 pr_jm $jmid $seq ""
		dict set userchans $user $jmid
		m2 chans register_chan $jmid \
				[namespace code [list my _userchan_update $user]]
		m2 ack $seq "Updated"
		my _set_expires $user
	}

	#>>>
	method get_user_pbkey {user} { #<<<
		my log debug

		if {[dict exists $userkeys $user]} {
			return [dict get $userkeys $user]
		} elseif {[regexp {^svc%(.*)$} $user x svc_name]} {
			my log debug "Returning pbkey for svc ($svc_name)"
			return [crypto::rsa_get_public_key [svckeys get_pbkey $svc_name]]
		}

		my log error "No key stored for user"
		error "No such user: ($user)"
	}

	#>>>
	method kick {user} { #<<<
		my log notice "kicking user ($user)"
		dict unset userkeys $user
		dict unset userchans $user
		if {[dict exists $expires $user]} {
			after cancel [dict $expires $user]
			dict unset expires $user
		}
	}

	#>>>

	method _userchan_update {user op data} { #<<<
		switch -- $op {
			cancelled {
				my log notice "got cancel of user chan ($user)"
				dict unset userkeys $user
				dict unset userchans $user
				if {[dict exists $expires $user]} {
					after cancel [dict get $expires $user]
					dict unset expires $user
				}
			}

			req {
				lassign $data seq prev_seq msg
				set type	[lindex $msg 0]
				switch -- $type {
					"session_pbkey_update" {
						my log debug "req($type): got request to update user key"
						dict set userkeys $user		[lindex $msg 1]
						m2 ack $seq "updated session key"
						my _set_expires $user
					}

					default {
						my log error "req($type): invalid request: ($msg)"
						m2 nack $seq "invalid request"
					}
				}
			}

			default {
				my log error "invalid op: ($op)"
			}
		}
	}

	#>>>
	method _set_expires {user} { #<<<
		if {[dict exists $expires $user]} {
			after cancel [dict get $expires $user]
			dict unset expires $user
		}
		set interval	[expr {int($userkey_expires_hours * 3600000)}]
		my log debug "setting send_warn expires for $interval ms"
		dict set expires $user	[after $interval \
				[namespace code [list my _send_warn $user]]]
	}

	#>>>
	method _send_warn {user} { #<<<
		my log debug
		if {[dict exists $expires $user]} {
			after cancel [dict get $expires $user]
			dict unset expires $user
		}

		if {![dict exists $userchans $user]} {
			my log error "no userchan known for $user"
			return
		}

		m2 jm [dict get $userchans $user] "refresh_key"
		my log debug "sent refresh_key warning to $user"

		set interval	[expr {int($userkey_grace_minutes * 60000)}]
		my log debug "setting expunge_key expires for $interval ms"
		dict set expires $user	[after $interval \
				[namespace code [list my _expunge_key $user]]]
	}

	#>>>
	method _expunge_key {user} { #<<<
		my log debug
		if {[dict exists $expires $user]} {
			after cancel [dict get $expires $user]
			dict unset expires $user
		}

		if {[dict exists $userchans $user]} {
			m2 jm_can [dict get $userchans $user] "key expired"
			m2 chans deregister_chan [dict get $userchans $user]
			my log debug "cancelled userchan for user: ($user) ([dict get $userchans $user])"
		}

		dict unset userkeys $user
		dict unset userchans $user
		my log debug "forcibly expired user key: ($user)"
	}

	#>>>
}



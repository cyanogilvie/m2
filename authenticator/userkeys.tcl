# vim: foldmarker=<<<,>>> foldmethod=marker ts=4 shiftwidth=4 ft=tcl

oo::class create Userkeys {
	variable {*}{
		userkey_expires_hours
		userkey_grace_minutes
		userkeys
		userchans
		expires
	}

	constructor {} { #<<<
		if {[self next] ne {}} next

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
		dict for {user afterid} $expires {
			after cancel $afterid
			dict unset expires $user
		}

		if {[self next] ne {}} next
	}

	#>>>

	method userkey_update {user seq prev_seq rest} { #<<<
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
		if {[dict exists $userkeys $user]} {
			return [dict get $userkeys $user]
		} elseif {[regexp {^svc%(.*)$} $user x svc_name]} {
			return [svckeys get_pbkey $svc_name]
		}

		log error "No key stored for user"
		error "No such user: ($user)"
	}

	#>>>
	method kick {user} { #<<<
		log notice "kicking user ($user)"
		dict unset userkeys $user
		dict unset userchans $user
		if {[dict exists $expires $user]} {
			after cancel [dict get $expires $user]
			dict unset expires $user
		}
	}

	#>>>

	method _userchan_update {user op data} { #<<<
		switch -- $op {
			cancelled {
				log notice "got cancel of user chan ($user)"
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
						dict set userkeys $user		[lindex $msg 1]
						m2 ack $seq "updated session key"
						my _set_expires $user
					}

					default {
						log error "req($type): invalid request: ($msg)"
						m2 nack $seq "invalid request"
					}
				}
			}

			default {
				log error "invalid op: ($op)"
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
		dict set expires $user	[after $interval \
				[namespace code [list my _send_warn $user]]]
	}

	#>>>
	method _send_warn {user} { #<<<
		if {[dict exists $expires $user]} {
			after cancel [dict get $expires $user]
			dict unset expires $user
		}

		if {![dict exists $userchans $user]} {
			log error "no userchan known for $user"
			return
		}

		m2 jm [dict get $userchans $user] "refresh_key"

		set interval	[expr {int($userkey_grace_minutes * 60000)}]
		dict set expires $user	[after $interval \
				[namespace code [list my _expunge_key $user]]]
	}

	#>>>
	method _expunge_key {user} { #<<<
		if {[dict exists $expires $user]} {
			after cancel [dict get $expires $user]
			dict unset expires $user
		}

		if {[dict exists $userchans $user]} {
			m2 jm_can [dict get $userchans $user] "key expired"
			m2 chans deregister_chan [dict get $userchans $user]
		}

		dict unset userkeys $user
		dict unset userchans $user
		log debug "forcibly expired user key: ($user)"
	}

	#>>>
}



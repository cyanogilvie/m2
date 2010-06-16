# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create Admin {
	variable {*}{
		connected_users
		admin_jmid
	}

	constructor {} { #<<<
		if {[self next] ne {}} {next}

		set connected_users	{}
	}

	#>>>

	method user_connected {userchans_obj seq} { #<<<
		set fqun	[$userchans_obj get fqun]
		set perms	[$userchans_obj get perms]

		dict set connected_users $fqun userchans $userchans_obj

		if {[info exists admin_jmid]} {
			m2 jm $admin_jmid [list user_connected $fqun]
		}

		if {"system.admin" in $perms} {
			log debug "User has system.admin perm, joining admin channel"
			if {![info exists admin_jmid]} {
				set admin_jmid		[m2 unique_id]
				m2 chans register_chan $admin_jmid \
						[namespace code {my _admin_chan_cb}]
				log debug "admin_jmid didn't exist, created new one: ($admin_jmid)"
			} else {
				log debug "admin_jmid already existed: ($admin_jmid)"
			}

			m2 pr_jm $admin_jmid $seq \
					[list admin_chan [my _get_connected_users]]
		}
	}

	#>>>
	method user_disconnected {userchans_obj} { #<<<
		set fqun	[$userchans_obj get fqun]
		log debug "fqun: \"$fqun\""

		if {[dict exists $connected_users $fqun]} {
			dict unset connected_users $fqun

			if {[info exists admin_jmid]} {
				m2 jm $admin_jmid [list user_disconnected $fqun]
			}
		}
	}

	#>>>

	method _admin_chan_cb {op data} { #<<<
		switch -- $op {
			cancelled {
				unset admin_jmid
			}

			req {
				lassign $data seq prev_seq msg
				lassign $msg op data
				switch -- $op {
					kick_user { #<<<
						try {
							if {[string first % $data] == -1} {
								log debug "no type prefix present: \"$data\""
								set data	"user%$data"
							}
							my _kick_user $data
						} on ok {} {
							m2 ack $seq ""
						} on error {errmsg options} {
							log error "Could not kick user ($data): $errmsg"
							m2 nack $seq $errmsg
						}
						#>>>
					}

					default { #<<<
						m2 nack $seq "Invalid operation: ($op)"
						#>>>
					}
				}
			}

			default {
				log error "Unknown op: ($op)"
			}
		}
	}

	#>>>
	method _get_connected_users {} { #<<<
		dict keys $connected_users
	}

	#>>>
	method _kick_user {fqun} { #<<<
		log notice "Admin::kick_user: \"$fqun\""
		if {![dict exists $connected_users $fqun]} {
			log warning "Asked to kick user who isn't logged in: \"$fqun\"\n\t[join [dict keys $connected_users] \n\t]"
			error "User \"$fqun\" is not logged in.\n\t[join [dict keys $connected_users] \n\t]"
		}

		if {![dict exists $connected_users $fqun userchans]} {
			error "Could not find userchan object for \"$fqun\""
		}

		set userchan_obj	[dict get $connected_users $fqun userchans]
		$userchan_obj kick
	}

	#>>>
}



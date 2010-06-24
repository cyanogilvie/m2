# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

# There are one of these for each logical user logged in, regardless of how
# many times they are logged in (and therefore how may User instances they have)

oo::class create Userchans {
	variable {*}{
		dat
		userinfo_chan
		uinfo
		plugin_name
		plugin_params
		sessions
	}

	constructor {fqun} { #<<<
		if {[self next] ne {}} next

		set dat					[dict create]
		set uinfo				[dict create]
		set active_profile		""
		set auth_backend_params	{}
		set sessions			{}

		dict set dat fqun	$fqun

		dict set dat upath	[my _getupath]

		# Determine delegation <<<
		set plugin_name	""
		set upath		[dict get $dat upath]
		db eval {
			select
				domain_match,
				plugin_name,
				plugin_params
			from
				delegations
			where
				$upath glob domain_match
			order by
				length(domain_match) desc
			limit 1
		} row {
			set plugin_name		$row(plugin_name)
			set plugin_params	$row(plugin_params)
		}

		if {$plugin_name eq ""} {
			throw [list no_delegation [dict get $dat upath]] \
					"No delegation registered for \"[dict get $dat upath]\""
		}
		# Determine delegation >>>

		# Normalize username <<<
		set upath_parts		[split [string trim [dict get $dat upath] /] /]
		set simple_username	[lindex $upath_parts end]
		set subdomain		[join [lrange $upath_parts 1 end-1] /]

		set normalized [plugins plugin_command $plugin_name $plugin_params \
				normalize_username $simple_username]

		# Set these again, this time with the normalized values
		dict set uinfo fqun			$normalized
		proc log {lvl msg args} [format {
			tailcall ::log $lvl "\"%s\" $msg" {*}$args
		} [list $normalized]]
		dict set dat upath			[my _getupath]
		# Normalize username >>>
	}

	#>>>
	destructor { #<<<
		my variable jmid

		if {[info exists jmid]} {
			#m2 chans deregister_chan $jmid
			log debug "Cancelling login_chan jmid: ($jmid)"
			m2 jm_can $jmid ""
			unset jmid
		}
		if {[info exists userinfo_chan]} {
			#m2 chans deregister_chan $userinfo_chan
			log debug "Cancelling userinfo_chan: ($userinfo_chan)"
			m2 jm_can $userinfo_chan ""
			unset userinfo_chan
		}

		log debug "clearing out entry for \"[dict get $dat fqun]\" from online array"
		dict unset ::online [dict get $dat fqun]
		users logoff [dict get $dat fqun]

		admin user_disconnected [self]

		if {[self next] ne {}} next
	}

	#>>>

	method add_session {userobj seq} { #<<<
		my variable jmid
		dict set sessions $userobj $seq

		if {![dict exists $::online [dict get $dat fqun]]} {
			set jmid				[m2 unique_id]
			dict set ::online [dict get $dat fqun]	[self]
			m2 chans register_chan $jmid [namespace code {my _chan_cb}]
			set is_new	1
		} else {
			set is_new	0
		}

		my userinfo_jm_setup $seq

		if {$is_new} {
			admin user_connected [self] $seq
		}

		m2 pr_jm $jmid $seq [list login_chan]
	}

	#>>>
	method remove_session {userobj} { #<<<
		if {![dict exists $sessions $userobj]} {
			log warning "Session removed for ($userobj), but we have no recollection of it: ($sessions)"
			return
		}
		dict unset sessions $userobj

		set remaining	[dict size $sessions]

		#if {$remaining == 0} {
		#	my destroy
		#}

		return $remaining
	}

	#>>>
	method connected_sessions {} { #<<<
		dict size $sessions
	}

	#>>>
	method get {key args} { #<<<
		switch -- [llength $args] {
			0 - 1 {}
			default {
				throw {syntax_error} \
						"Too many arguments, should be key ?defaultval?"
			}
		}
		if {[dict exists $dat $key]} {
			return [dict get $dat $key]
		}

		if {[llength $args] > 0} {
			return [lindex $args 0]
		}

		throw [list invalid_key $key] "No such key: \"$key\""
	}

	#>>>
	method set_dat {key value} { #<<<
		dict set dat $key	$value
	}

	#>>>
	method check_login_person {seq password} { #<<<
		if {[dict exists $::online [dict get $dat fqun]]} {
			throw {duplicate_login} "User already logged in elsewhere"
		}

		set upath_parts	[split [string trim [dict get $dat upath] /] /]
		if {[lindex $upath_parts 0] ne "users"} {
			throw [list unsupported_user_type [lindex $upath_parts 0]] \
					"Can only auth real users"
		}
		set simple_username	[lindex $upath_parts end]
		set subdomain		[join [lrange $upath_parts 1 end-1] /]

		if {
			![plugins plugin_command $plugin_name $plugin_params \
					check_auth $simple_username $subdomain $password]
		} {
			throw {incorrect_password} "deny login: incorrect password"
		}
	}

	#>>>
	method userinfo_jm_setup {seq} { #<<<
		set ucfg	[dict merge {
			perms	{}
			attribs	{}
			prefs	{}
		} [my _get_info]]

		if {![dict exists $ucfg profilenames]} {
			set profilenames	{}
		} else {
			set profilenames	[dict get $ucfg profilenames]
		}

		set profiles		{}
		set profiles_dict	{}
		foreach key [dict keys $ucfg] {
			if {
				[string match "perms.*" $key] ||
				[string match "attribs.*" $key]
			} {
				set profile	[join [lrange [split $key .] 1 end] .]
				if {$profile ni $profiles} {
					lappend profiles	$profile
					if {[dict exists $profilenames $profile]} {
						set name	[dict get $profilenames $profile]
					} else {
						set name	$profile
					}
					lappend profiles_dict	$profile $name
				}
			}
		}
		if {![info exists userinfo_chan]} {
			set userinfo_chan	[m2 unique_id]
			m2 chans register_chan $userinfo_chan \
					[namespace code {my _userinfo_chan_cb}]
		}

		dict set dat prefs	[dict get $ucfg prefs]
		m2 pr_jm $userinfo_chan $seq [list prefs [dict get $dat prefs]]

		if {[llength $profiles] > 0} {
			if {[dict get $dat type] eq "svc"} {
				log warning "Ignoring profiles defined for svc type user"
			} else {
				my variable active_profile
				if {![info exists active_profile]} {
					set active_profile	""
				}
				if {$active_profile eq ""} {
					# Send back a request to choose a profile <<<
					m2 pr_jm $userinfo_chan $seq [list select_profile $profiles_dict]
					my variable profile_wait
					set profile_wait	[info coroutine]
					log debug "Waiting for user to pick profile"
					set warning_id	[after 30000 [list log warning "User taking a long time to select a profile"]]
					set selected	[yield]
					after cancel $warning_id

					log debug "user requested profile: ($selected)"
					if {$selected in $profiles} {
						set profile	$selected
					} else {
						log warning "User selected invalid profile: ($selected)"
						set profile	""
					}
					set active_profile	$profile
					unset profile_wait
					# Send back a request to choose a profile >>>
				} else {
					set profile	$active_profile
				}

				if {[dict exists $ucfg perms.$profile]} {
					dict set ucfg perms	[lsort -unique [concat \
							[dict get $ucfg perms] \
							[dict get $ucfg perms.$profile] \
							]]
				}
				if {[dict exists $ucfg attribs.$profile]} {
					dict set ucfg attribs [dict merge \
							[dict get $ucfg attribs] \
							[dict get $ucfg attribs.$profile] \
					]
				}
			}
		}

		dict set dat perms		[dict get $ucfg perms]
		dict set dat attribs	[dict get $ucfg attribs]

		m2 pr_jm $userinfo_chan $seq [list perms [dict get $dat perms]]
		m2 pr_jm $userinfo_chan $seq [list attribs [dict get $dat attribs]]
	}

	#>>>
	method kick {} { #<<<
		foreach userobj [dict keys $sessions] {
			if {[info object isa object $userobj]} {
				$userobj destroy
			} else {
				log error "Recorded session isn't a valid object any more: $userobj"
				dict unset sessions $userobj
			}
		}
		my _logout
	}

	#>>>

	method _get_info {} { #<<<
		set upath_parts	[split [string trim [dict get $dat upath] /] /]
		#if {[lindex $upath_parts 0] ne "users"} {
		#	throw [list unsupported_user_type [lindex $upath_parts 0]] \
		#			"Can only auth real users"
		#}
		set simple_username	[lindex $upath_parts end]
		set subdomain		[join [lrange $upath_parts 1 end-1] /]

		plugins plugin_command $plugin_name $plugin_params get_info $simple_username $subdomain
	}

	#>>>
	method _change_password {seq prev_seq rest} { #<<<
		try {
			lassign $rest old new1 new2

			if {$new1 ne $new2} {
				throw {denied} "New passwords do not match"
			}

			set upath_parts		[split [string trim [dict get $dat upath] /] /]
			set simple_username	[lindex $upath_parts end]
			set subdomain		[join [lrange $upath_parts 1 end-1] /]

			plugins plugin_command $plugin_name $plugin_params \
					change_credentials \
					$simple_username $subdomain \
					$old $new1
		} trap {denied} {errmsg options} {
			log warning "Change password denied: $errmsg" -suppress rest
			m2 nack $seq $errmsg
		} on error {errmsg options} {
			log error "error updating user details: $errmsg" -suppress rest
			m2 nack $seq "Error updating database"
		} on ok {} {
			m2 ack $seq "Password changed"
		}
	}

	#>>>
	method _set_pref {seq prev_seq rest} { #<<<
		lassign $rest pref newvalue

		try {
			set upath_parts		[split [string trim [dict get $dat upath] /] /]
			set simple_username	[lindex $upath_parts end]
			set subdomain		[join [lrange $upath_parts 1 end-1] /]

			plugins plugin_command $plugin_name $plugin_params \
					set_pref $simple_username $subdomain \
					$pref $newvalue
		} on error {errmsg options} {
			log error "error updating user pref: ($pref) ($newvalue): $errmsg"
			m2 nack $seq "Error updating database"
			return
		}

		if {[info exists userinfo_chan]} {
			m2 jm $userinfo_chan [list prefs [list $pref $newvalue]]
		} else {
			log error "no userchan exists for user, even though we are answering a request from that user"
		}
		m2 ack $seq ""
	}

	#>>>
	method _logout {} { #<<<
		log notice "User logoff or disconnect"
		my destroy
	}

	#>>>
	method _chan_cb {op data} { #<<<
		switch -- $op {
			cancelled {
				my variable jmid

				if {[info exists jmid]} {
					unset jmid
				}
				my _logout
			}

			req {
				lassign $data seq prev_seq msg
				set rest	[lassign $msg type]
				switch -- $type {
					change_password { #<<<
						my _change_password $seq $prev_seq $rest
						#>>>
					}
					set_pref { #<<<
						my _set_pref $seq $prev_seq $rest
						#>>>
					}
					default { #<<<
						try {
							users userreq $type [dict get $dat fqun] \
									$seq $prev_seq $rest
						} trap {no_handlers} {errmsg options} { #<<<
							set registered \
									[lindex [dict get $options -errorcode] 2]
							log error $errmsg

							m2 nack $seq "No handlers available"
							#>>>
						} on error {errmsg options} { #<<<
							log error "\nerror processing userreq: (userreq_$type): $errmsg\n[dict get $options -errorinfo]"
							m2 nack $seq "Internal error"
							#>>>
						}
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
	method _userinfo_chan_cb {op data} { #<<<
		switch -- $op {
			cancelled {
				if {[info exists userinfo_chan]} {
					unset userinfo_chan
				}
			}

			req {
				lassign $data seq prev_seq msg
				set op	[lindex $msg 0]
				switch -- $op {
					select_profile { #<<<
						my variable profile_wait
						if {![info exists profile_wait]} {
							m2 nack $seq "Not waiting for a profile selection"
						} else {
							set profile	[lindex $msg 1]
							m2 ack $seq ""

							$profile_wait $profile
						}
						#>>>
					}

					default { #<<<
						log error "req: unrecognised request on userinfo channel"
						m2 nack $seq "Invalid request"
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
	method _getupath {} { #<<<
		set fqun	[dict get $dat fqun]

		set typesplit	[split $fqun %]
		if {[llength $typesplit] > 1} {
			set type	[lindex $typesplit 0]
			set user	[join [lrange $typesplit 1 end] %]
		} else {
			set type	"user"
			set user	$fqun
		}

		switch -- $type {
			"user" {
				set tmp		[split $user @]
				if {
					[llength $tmp] != 2 ||
					[lindex $tmp 0] eq ""
				} {
					throw [list invalid_username $user] \
							"Malformed user string: ($user)"
				}
				set upath	[join [list "users" [lindex $tmp 1] [lindex $tmp 0]] /]
			}
			
			"svc" {
				set upath	[join [list "svcs" $user] /]
			}
			
			default {
				throw [list invalid_user_type $type] \
						"Invalid user type: ($type)"
			}
		}

		set upath	[string map {// /} $upath]

		return $upath
	}

	#>>>
}



# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create Users {
	superclass cflib::handlers

	variable {*}{
		cookie_expires
		pending_cookies
	}

	constructor {} { #<<<
		if {[self next] ne {}} next

		array set cookie_expires	{}
		array set pending_cookies	{}

		crypto register_handler encreq_login [namespace code {my _login_person}]
		crypto register_handler encreq_login_svc [namespace code {my _login_svc}]
		crypto register_handler encreq_get_user_pbkey [namespace code {my _get_user_pbkey}]
		crypto register_handler encreq_cookie_o_kudasai [namespace code {my _svc_cookie_req}]
		crypto register_handler encreq_userinfo_setup [namespace code {my _userinfo_setup}]
	}

	#>>>
	destructor { #<<<
		foreach cookie_idx [array names cookie_expires] {
			my expire_cookie $cookie_idx
		}

		if {[self next] ne {}} next
	}

	#>>>

	method make_fqun {username} { #<<<
		set typesplit	[split $username %]
		if {[llength $typesplit] > 1} {
			set type	[lindex $typesplit 0]
			set user	[join [lrange $typesplit 1 end] %]
		} else {
			set type	user
			set user	$username
		}

		switch -- $type {
			"user" {
				if {[string first "@" $user] == -1} {
					error "Invalid user format: ($user)"
				}
			}
		}

		return [join [list $type $user] %]
	}

	#>>>
	method logoff {fqun} { #<<<
		my invoke_handlers logoff $fqun
	}

	#>>>
	method userreq {type fqun seq prev_seq rest} { #<<<
		if {![my handlers_available userreq_$type]} {
			throw [list no_handlers $type [my dump_handlers]] \
					"No handlers registered for type: (userreq_$type)"
		} else {
			my invoke_handlers userreq_$type $fqun $seq $prev_seq $rest
		}
	}

	#>>>
	method expire_cookie {cookie_idx} { #<<<
		if {[info exists cookie_expires($cookie_idx)]} {
			after cancel $cookie_expires($cookie_idx)
			array unset cookie_expires $cookie_idx
		}
		array unset pending_cookies $cookie_idx
	}

	#>>>
	method pending_cookie {cookie_idx} { #<<<
		if {[info exists pending_cookies($cookie_idx)]} {
			return $pending_cookies($cookie_idx)
		}

		throw [list invalid_cookie_idx $cookie_idx] \
				"No such cookie: ($cookie_idx)"
	}

	#>>>

	method _login_person {seq prev_seq data} { #<<<
		lassign $data type username password

		try {
			set userobj	[User new $username]
			$userobj login_person $seq $password
		} on ok {} { #<<<
			m2 ack $seq "Chans successful"
			set login_ok	1
			#>>>
		} trap {invalid_user_type} {errmsg options} { #<<<
			set badtype	[lindex $::errorCode 1]
			log error "Invalid user type: ($badtype)\n[dict get $options -errorinfo]" -suppress data
			m2 nack $seq $errmsg
			#>>>
		} trap {duplicate_login} {errmsg options} { #<<<
			log warning "User already logged in elsewhere" -suppress data
			m2 nack $seq "User already logged in elsewhere"
			#>>>
		} trap {not_found} {errmsg options} { #<<<
			set upath	[lindex $::errorCode 1]
			log warning "deny login: cannot retrieve ($upath): $errmsg" \
					-suppress data
			m2 nack $seq "Invalid user or password"
			#>>>
		} trap {invalid_username} {errmsg options} { #<<<
			set username	[lindex $::errorCode 1]
			log warning "deny login: Invalid username ($username): $errmsg" \
					-suppress data
			m2 nack $seq "Invalid user or password"
			#>>>
		} trap {required_field_missing} {errmsg options} { #<<<
			set reqf	[lindex $::errorCode 1]
			log error "required field missing: ($reqf)" -suppress data
			m2 nack $seq "Required field missing: ($reqf)"
			#>>>
		} trap {incorrect_password} {errmsg options} - \
		trap {invalid_authtype} {errmsg options} { #<<<
			log warning $errmsg -suppress data
			m2 nack $seq "Invalid user or password"
			#>>>
		} on error {errmsg options} { #<<<
			log error "Unexpected error trying to log in: $errmsg ($::errorCode)\n[dict get $options -errorinfo]" -suppress data
			#log error "Unexpected error trying to log in: $errmsg ($::errorCode)" -suppress data
			m2 nack $seq "Internal error"
			#>>>
		} finally { #<<<
			if {![info exists login_ok]} {
				if {
					[info exists userobj] &&
					[info object isa object $userobj]
				} {
					try {
						$userobj destroy
						unset userobj
					} on error {errmsg options} {
						log error "Error destroying userobj: $errmsg\n[dict get $options -errorinfo]"
					}
				}
			}
			#>>>
		}
	}

	#>>>
	method _login_svc {seq prev_seq data} { #<<<
		# Keep in sync with Users::login
		try {
			lassign $data -> svc cookie_idx e_cookie

			set userobj	[User new "svc%$svc"]
			$userobj login_svc $seq $svc $cookie_idx $e_cookie
		} on ok {} { #<<<
			m2 ack $seq "Chans successful"
			set login_ok	1
			#>>>
		} trap {bad_cookie} {errmsg options} { #<<<
			log error "cookie is bad" -suppress data
			m2 nack $seq "Cookie bad"
			#>>>
		} on error {errmsg options} { #<<<
			log error "Unexpected error trying to login: $errmsg ([dict get $options -errorcode])\n[dict get $options -errorinfo])" -suppress data
			m2 nack $seq "Internal error"
			#>>>
		} finally { #<<<
			if {![info exists login_ok]} {
				if {
					[info exists userobj] &&
					[info object isa object $userobj]
				} {
					try {
						$userobj destroy
						unset userobj
					} on error {errmsg options} {
						log error "Error destroying userobj: $errmsg\n[dict get $options -errorinfo]"
					}
				}
			}
			#>>>
		}
	}

	#>>>
	method _get_user_pbkey {seq prev_seq data} { #<<<
		set fqun	[lindex $data 1]

		try {
			userkeys get_user_pbkey $fqun
		} on error {errmsg options} {
			log error "error fetching pbkey: [dict get $options -errorinfo]"
			m2 nack $seq "No public key for \"$fqun\""
		} on ok {pbkey} {
			m2 ack $seq $pbkey
		}
	}

	#>>>
	method _svc_cookie_req {seq prev_seq data} { #<<<
		set svc			[lindex $data 1]

		set cookie		[m2 pseudo_bytes 16]	;# WARNING: possible RNG DOS
		set cookie_idx	[m2 unique_id]

		set pending_cookies($cookie_idx)	[list $cookie $svc]
		set cookie_expires($cookie_idx)	[after [cfg get cookie_shelflife] \
				[namespace code [list my expire_cookie $cookie_idx]]]

		m2 ack $seq [list $cookie_idx $cookie]
	}

	#>>>
	method _userinfo_setup {seq prev_seq data} { #<<<
		set fqun		[my make_fqun [lindex $data 1]]
		try {
			if {![dict exists $::online $fqun]} {
				throw [list no_user $fqun] "No active record for \"$fqun\""
			}
			set userchans_obj		[dict get $::online $fqun]

			# This is just for the svcs this user logs into to get the info,
			# it doesn't represent a login session
			$userchans_obj userinfo_jm_setup $seq
		} on ok {} {
			m2 ack $seq ""
		} trap {no_user} {errmsg options} { #<<<
			log error "No logged in user: ($fqun)"
			m2 nack $seq "User $fqun isn't logged in"
			#>>>
		} on error {errmsg options} { #<<<
			log error "Unhandled error setting up userinfo: $errmsg\n[dict get $options -errorinfo]"
			m2 nack $seq "Internal error"
			#>>>
		}
	}

	#>>>
}



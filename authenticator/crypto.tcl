# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create Crypto {
	superclass cflib::handlers cflib::baselog

	variable {*}{
		priv_keys
		session_keys
	}

	constructor {} { #<<<
		my log debug [self]
		array set session_keys {}

		set fqkeyfn			[file join $::base [cfg get prkey]]

		if {![file exists $fqkeyfn]} {
			error "Cannot find authenticator private key: ([cfg get prkey])"
		}

		set priv_key		[crypto::rsa_read_private_key $fqkeyfn]
	}

	#>>>

	method encrypt {session_id msg} { #<<<
		m2 encrypt $session_keys($session_id) $msg
	}

	#>>>
	method decrypt {session_id emsg} { #<<<
		m2 decrypt $session_keys($session_id) $emsg
	}

	#>>>
	method get_session_key {session_id} { #<<<
		my log debug
		if {![info exists session_keys($session_id)]} {
			set session_keys($session_id)	[m2 generate_key]
			my log debug "no session key exists for session, generated: ([mungekey $session_keys($session_id)])"
		} else {
			my log debug "returning existing session key: ([mungekey $session_keys($session_id)])"
		}

		return $session_keys($session_id)
	}

	#>>>
	method purge_session_key {session_id} { #<<<
		my log debug
		array unset session_keys $session_id
	}

	#>>>
	method register_or_get_chan {session_id} { #<<<
		my log debug
		if {![info exists session_keys($session_id)]} {
			set session_keys($session_id)	[m2 generate_key]
			my log debug "allocated chan key: ([mungekey $session_keys($session_id)])"
		} else {
			my log debug "returning existing chan key: ([mungekey $session_keys($session_id)])"
		}

		return $session_keys($session_id)
	}

	#>>>
	method registered_chan {session_id} { #<<<
		info exists session_keys($session_id)
	}

	#>>>
	method crypt_setup {seq data} { #<<<
		my log debug "" -suppress data
		lassign $data e_key e_cookie

		try {
			set session_key	[crypto::rsa_private_decrypt $priv_key $e_key]
			my log debug "session_key: ([mungekey $session_key])" -suppress data
		} on error {errmsg options} {
			my log error "could not decrypt session_key: $errmsg" -suppress data
			m2 nack $seq "Could not decrypt session_key"
			return
		}

		try {
			set cookie		[crypto::rsa_private_decrypt $priv_key $e_cookie]
		} on error {errmsg options} {
			my log error "could not decrypt cookie: $errmsg" -suppress data
			m2 nack $seq "Could not decrypt cookie"
			return
		}

		set session_id	[m2 unique_id]
		my log debug "allocated session_id: $session_id" -suppress data
		
		set session_keys($session_id)	$session_key
		
		m2 pr_jm $session_id $seq ""
		m2 ack $seq [my encrypt $session_id $cookie]
		m2 chans register_chan $session_id \
				[namespace code [list my _session_chan $session_id]]
	}

	#>>>

	method _session_chan {session_id op data} { #<<<
		my log debug
		switch -- $op {
			cancelled {
				array unset session_keys $session_id
			}

			req {
				lassign $data seq prev_seq msg
				set type	[lindex $msg 0]
				if {![my handlers_available encreq_$type]} {
					my log error "no handlers registered for type: (encreq_$type)"
					my log debug "handlers:\n[my dump_handlers]"
					m2 nack $seq "No handlers available"
				} else {
					my log debug "invoking encreq_$type ($msg)"
					try {
						my invoke_handlers encreq_$type \
								$session_id $seq $prev_seq $msg
					} on error {errmsg options} {
						my log error "\nerror in handler: $errmsg\n[dict get $options -errorinfo]"
						m2 nack $seq "Internal error"
					}
				}
			}

			default {
				my log error "unknown op: ($op)"
			}
		}
	}

	#>>>
}



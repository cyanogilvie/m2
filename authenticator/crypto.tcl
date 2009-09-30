# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create Crypto {
	superclass cflib::handlers cflib::baselog

	variable {*}{
		priv_key
	}

	constructor {} { #<<<
		if {[self next] ne {}} next

		my log debug [self]

		set fqkeyfn			[file join $::base [cfg get prkey]]

		if {![file exists $fqkeyfn]} {
			error "Cannot find authenticator private key: ([cfg get prkey])"
		}

		set priv_key		[crypto::rsa::load_asn1_prkey $fqkeyfn]
	}

	#>>>

	method crypt_setup {seq data} { #<<<
		my log debug "" -suppress data
		lassign $data e_key e_cookie
		my log debug "e_key length: ([string length $e_key]), e_cookie length: ([string length $e_cookie])"

		set K	[dict with priv_key {list $p $q $dP $dQ $qInv}]
		set hash	$crypto::rsa::sha1
		set mgf		$crypto::rsa::MGF
		try {
			#set session_key	[crypto::rsa_private_decrypt $priv_key $e_key]
			set session_key	[crypto::rsa::RSAES-OAEP-Decrypt $K $e_key {} $hash $mgf]
			my log debug "session_key: ([mungekey $session_key])" -suppress data
		} on error {errmsg options} {
			my log error "could not decrypt session_key: $errmsg" -suppress data
			m2 nack $seq "Could not decrypt session_key"
			return
		}

		try {
			#set cookie		[crypto::rsa_private_decrypt $priv_key $e_cookie]
			set cookie		[crypto::rsa::RSAES-OAEP-Decrypt $K $e_cookie {} $hash $mgf]
		} on error {errmsg options} {
			my log error "could not decrypt cookie: $errmsg" -suppress data
			m2 nack $seq "Could not decrypt cookie"
			return
		}

		set session_id	[m2 unique_id]
		my log debug "allocated session_id: $session_id" -suppress data
		
		m2 crypto register_chan $session_id $session_key
		m2 chans register_chan $session_id \
				[namespace code [list my _session_chan]]
		m2 pr_jm $session_id $seq ""
		m2 ack $seq [m2 crypto encrypt $session_id $cookie]
	}

	#>>>
	method _session_chan {op data} { #<<<
		my log debug
		switch -- $op {
			cancelled {
				# User session channel cancelled
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
								$seq $prev_seq $msg
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



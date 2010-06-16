# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create Crypto {
	superclass cflib::handlers

	variable {*}{
		priv_key
	}

	constructor {} { #<<<
		if {[self next] ne {}} next

		namespace path [concat [namespace path] {
			::oo::Helpers::cflib
		}]

		set fqkeyfn			[cfg get prkey]

		if {![file exists $fqkeyfn]} {
			error "Cannot find authenticator private key: ([cfg get prkey])"
		}

		set priv_key		[crypto::rsa::load_asn1_prkey $fqkeyfn]
	}

	#>>>

	method crypt_setup {seq data} { #<<<
		try {
			lassign $data e_key e_cookie

			set K	[dict with priv_key {list $p $q $dP $dQ $qInv}]
			set hash	$crypto::rsa::sha1
			set mgf		$crypto::rsa::MGF
			try {
				crypto::rsa::RSAES-OAEP-Decrypt $K $e_key {} $hash $mgf
			} on error {errmsg options} {
				log error "could not decrypt session_key: $errmsg" -suppress data
				throw nack "Could not decrypt session_key"
			} on ok {session_key} {}

			try {
				crypto::rsa::RSAES-OAEP-Decrypt $K $e_cookie {} $hash $mgf
			} on error {errmsg options} {
				log error "could not decrypt cookie: $errmsg" -suppress data
				throw nack "Could not decrypt cookie"
			} on ok {cookie} {}

			set session_id	[m2 unique_id]

			m2 crypto register_chan $session_id $session_key
			m2 chans register_chan $session_id [code _session_chan]
			m2 pr_jm $session_id $seq ""
			m2 ack $seq [m2 crypto encrypt $session_id $cookie]
		} trap nack {errmsg} {
			m2 nack $seq $errmsg
		}
	}

	#>>>
	method _session_chan {op data} { #<<<
		switch -- $op {
			cancelled {
				# User session channel cancelled
				?? {log debug "User session channel cancelled"}
			}

			req {
				lassign $data seq prev_seq msg

				set type	[lindex $msg 0]
				if {![my handlers_available encreq_$type]} {
					log error "no handlers registered for type: (encreq_$type)"
					m2 nack $seq "No handlers available"
				} else {
					try {
						my invoke_handlers encreq_$type $seq $prev_seq $msg
					} on error {errmsg options} {
						log error "error in handler: $errmsg\n[dict get $options -errorinfo]"
						m2 nack $seq "Internal error"
					}
				}
			}

			default {
				log error "unknown op: ($op)"
			}
		}
	}

	#>>>
}



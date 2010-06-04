# vim: ft=tcl foldmarker=<<<,>>> foldmethod=marker ts=4 shiftwidth=4

oo::class create Svckeys {
	superclass cflib::baselog

	constructor {} { #<<<
		if {[self next] ne {}} next

		users register_handler userreq_get_svc_pubkey \
				[namespace code {my _userreq_get_pbkey}]
	}

	#>>>
	destructor { #<<<
		users deregister_handler userreq_get_svc_pubkey \
				[namespace code {my get_pbkey}]

		if {[self next] ne {}} next
	}

	#>>>

	method get_pbkey_asc {svc} { #<<<
		set svcfn	[my _resolve_path $svc]
		if {![file isfile $svcfn]} {
			my log error "no file for svc: fn: ($svcfn)"
			error "No such svc: ($svc)"
		}

		cflib::readfile $svcfn
	}

	#>>>
	method get_pbkey {svc} { #<<<
		set svcfn	[my _resolve_path $svc]
		if {![file isfile $svcfn]} {
			error "No such svc: ($svc) ($svcfn)"
		}

		crypto::rsa::load_asn1_pubkey $svcfn
	}

	#>>>

	method _userreq_get_pbkey {user seq prev_seq data} { #<<<
		set svc 	[file tail $data]

		try {
			my get_pbkey_asc $svc
		} on error {errmsg options} {
			my log error "\nerror getting ascii public key: $errmsg\n[dict get $options -errorinfo]"
			m2 nack $seq $errmsg
		} on ok {pbkey} {
			m2 ack $seq $pbkey
		}
	}

	#>>>
	method _resolve_path {svc} { #<<<
		file join $::base [cfg get svc_keys] $svc
	}

	#>>>
}



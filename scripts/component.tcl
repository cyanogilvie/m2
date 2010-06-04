# vim: ft=tcl foldmarker=<<<,>>> foldmethod=marker ts=4 shiftwidth=4

# signals
#	user_login(userobj)
#	user_logout(userobj)

cflib::pclass create m2::component {
	superclass cflib::handlers cflib::baselog

	property allow_dup	0
	property svc		""
	property auth		""
	property prkeyfn	""
	property login		0

	variable {*}{
		op_handlers
		prkey
		chan_auth
		login_busy
	}

	constructor {args} { #<<<
		set op_handlers	[dict create]
		set chan_auth	[dict create]

		set login_busy		0

		my configure {*}$args

		foreach reqf {svc auth prkeyfn} {
			if {[set $reqf] eq ""} {
				error "Must set -$reqf"
			}
		}

		# This fetches the private key for this service
		set prkey	[crypto::rsa::load_asn1_prkey $prkeyfn]
		
		[$auth signal_ref established] attach_output \
				[my code _established_changed]

		[$auth signal_ref authenticated] attach_output \
				[my code authenticated_changed]

		if {$login} {
			[$auth signal_ref login_allowed] attach_output \
					[my code _login_allowed_changed]
		}
	}

	#>>>
	destructor { #<<<
		if {[info exists auth] && [info object isa object $auth]} {
			[$auth signal_ref established] detach_output \
					[my code _established_changed]

			[$auth signal_ref authenticated] detach_output \
					[my code authenticated_changed]

			if {$login} {
				[$auth signal_ref login_allowed] detach_output \
						[my code _login_allowed_changed]
			}
		}
	}

	#>>>

	method handler {op cb} { #<<<
		if {$cb ne ""} {
			dict set op_handlers $op	$cb
		} else {
			dict unset op_handlers $op
		}
	}

	#>>>
	method auth {} { #<<<
		return $auth
	}

	#>>>

	# Protected
	method authenticated_changed {newstate} { #<<<
		# Override this if you are interested in authenticated state changes
	}

	#>>>

	method _svc_handler {seq data} { #<<<
		try {
			if {[string range $data 0 5] == "setup "} {
				lassign [string range $data 6 end] e_skey e_tail iv
				#my log debug "e_skey (base64): [binary encode base64 $e_skey]"

				set K	[list \
						[dict get $prkey p] \
						[dict get $prkey q] \
						[dict get $prkey dP] \
						[dict get $prkey dQ] \
						[dict get $prkey qInv] \
				]
				set skey	[crypto::rsa::RSAES-OAEP-Decrypt $K $e_skey {} $crypto::rsa::sha1 $crypto::rsa::MGF]
				#my log debug "skey base64: [binary encode base64 $skey]"
				set ks		[crypto::blowfish::init_key $skey]
				set tail	[encoding convertfrom utf-8 [crypto::blowfish::decrypt_cbc $ks $e_tail $iv]]

				lassign $tail cookie fqun
			} else {
				throw {obsolete} "Obsolete user session setup"
			}
		} trap obsolete {errmsg} {
			my log error "Obsolete user session setup: ([string range $data 0 5]) != (setup )"
			$auth nack $seq "Obsolete user session setup"
			return
		} on error {errmsg options} {
			my log error "error decrypting request: [dict get $options -errorinfo]"
			$auth nack $seq ""
			return
		} on ok {} {
			#my log debug "Decrypted _svc_handler \"setup \" request ok, cookie base64: [binary encode base64 $cookie]"
		}

		# Create a user object <<<
		set mycookie	[$auth generate_key 16]
		set userobj		[m2::userinfo new $fqun $auth $svc]
		# Create a user object >>>

		set chan	[$auth unique_id]
		$auth crypto register_chan $chan $skey
		$auth chans register_chan $chan \
				[my code _userchan_cb $userobj $chan $mycookie]
		#my log debug "sending pr_jm ($chan) with cookie ([$auth mungekey $cookie]) encrypted with skey ([$auth mungekey $skey])"
		#my log debug "sending pr_jm ($chan) with cookie [binary encode base64 $cookie] encrypted with skey [binary encode base64 $skey]"
		$auth pr_jm $chan $seq $cookie
		try {
			$userobj get_pbkey
		} on error {errmsg options} {
			my log warning "nacking $seq: $errmsg\n[dict get $options -errorinfo]"
			$auth nack $seq "Cannot get public key for \"$fqun\""
		} on ok {user_pbkey} {
			#my log debug "got user pbkey, encrypting mycookie with it and acking"
			set n	[dict get $user_pbkey n]
			set e	[dict get $user_pbkey e]
			#my log debug "Encrypting cookie2 with n: $n, e: $e"
			#my log debug "cookie2: [binary encode base64 $mycookie]"
			$auth ack $seq [crypto::rsa::RSAES-OAEP-Encrypt $n $e $mycookie {} $crypto::rsa::sha1 $crypto::rsa::MGF]
		}
	}

	#>>>
	method _userchan_cb {user chan mycookie op data} { #<<<
		switch -- $op {
			cancelled { #<<<
				dict unset chan_auth $chan
				my invoke_handlers user_logout $user
				if {[info object isa object $user]} {
					$user destroy
				}
				#>>>
			}
			req { #<<<
				lassign $data seq prev_seq msg

				if {![dict exists $chan_auth $chan]} {
					if {$msg eq $mycookie} {
						dict set chan_auth $chan	1
						my invoke_handlers user_login_bare $user
						[$user signal_ref got_all] attach_output \
								[my code _user_permissioned $auth $seq $user]
					} else {
						$auth nack $seq "Cookie is bad"
					}

					return
				}

				lassign $msg rop rdata

				if {![dict exists $op_handlers $rop]} {
					my log warning "no handlers for op: ($rop)"
					$auth nack $seq "Internal error"
					return
				}

				try {
					?? {my log debug "Calling component req handler for ($rop): [dict get $op_handlers $rop]"}
					coroutine coro_handler_[incr ::coro_seq] \
							{*}[dict get $op_handlers $rop] \
							$auth $user $seq $rdata
					?? {my log debug "done rop: ($rop) cb: ([dict get $op_handlers $rop]), answered: [$auth answered $seq]"}
				} on error {errmsg options} {
					my log error "error processing op ($rop): $errmsg\n[dict get $options -errorinfo]"
					$auth nack $seq "Internal error"
				}
				#>>>
			}
			default { #<<<
				my log error "unexpected op: ($op)"
				#>>>
			}
		}
	}

	#>>>
	method _established_changed {newstate} { #<<<
		if {$newstate} {
			$auth handle_svc $svc [my code _svc_handler]
		} else {
			$auth handle_svc $svc {}
		}
	}

	#>>>
	method _user_permissioned {a_auth seq user newstate} { #<<<
		if {$newstate} {
			try {
				my invoke_handlers user_login $user
			} trap deny {errmsg options} {
				my log notice "Denying user \"[$user name]\" access: $errmsg"
				$a_auth nack $seq "Permission denied"
			} on error {errmsg options} {
				my log error "error invoking user_login handlers: $errmsg\n[dict get $options -errorinfo]"
				$a_auth nack $seq "Internal error"
			} on ok {} {
				$a_auth ack $seq ""
			}
		}
	}

	#>>>
	method _login_allowed_changed {newstate} { #<<<
		if {$login_busy} return
		incr login_busy 1
		if {$newstate} {
			if {![$auth login_svc $svc [string map [list %s $svc] $prkeyfn]]} {
				my log error "Failed to login: [$auth last_login_message]"
			}
		}
		incr login_busy -1
	}

	#>>>
}



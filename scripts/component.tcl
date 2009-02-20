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
			if {![set $reqf] eq ""} {
				error "Must set -$reqf"
			}
		}

		# This fetches the private key for this service
		set prkey	[crypto::rsa_read_private_key $prkeyfn]
		
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

	# Protected
	method authenticated_changed {newstate} { #<<<
		# Override this if you are interested in authenticated state changes
	}

	#>>>

	method _svc_handler {seq data} { #<<<
		my log debug "got ($svc)"
		try {
			if {[string range $data 0 5] == "setup "} {
				lassign [string range $data 6 end] e_skey e_tail

				set skey	[crypto::rsa_private_decrypt $prkey $e_skey]
				set tail	[crypto::decrypt bf_cbc $skey $e_tail]
				
				lassign $tail cookie fqun
			} else {
				lassign [crypto::rsa_private_decrypt $prkey $data] \
						cookie skey fqun
			}
		} on error {errmsg options} {
			my log error "error decrypting request: $errmsg"
			$auth nack $seq
			return
		}

		# Create a user object <<<
		set mycookie	[$auth generate_key 16]
		set userobj		[m2::userinfo new $fqun $auth $svc]
		# Create a user object >>>

		set chan	[$auth unique_id]
		$auth crypto register_chan $chan $skey
		$auth chans register_chan $chan \
				[my code _userchan_cb $userobj $chan $mycookie]
		my log debug "sending pr_jm ($chan) with cookie ([$auth mungekey $cookie]) encrypted with skey ([$auth mungekey $skey])"
		$auth pr_jm $chan $seq $cookie
		try {
			set user_pbkey	[$userobj get_pbkey]
		} on error {errmsg options} {
			my log warning "nacking $seq: $errmsg\n[dict get $options -errorinfo]"
			$auth nack $seq "Cannot get public key for \"$fqun\""
		} else {
			my log debug "got user pbkey, encrypting mycookie with it and acking"
			$auth ack $seq [crypto::rsa_public_encrypt $user_pbkey $mycookie]
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
						$auth ack $seq ""
						my invoke_handlers user_login_bare $user
						[$user signal_ref got_all] attach_output \
								[my code _user_permissioned $user]
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
					uplevel #0 [dict get $op_handlers $rop] \
							[list $auth $user $seq $rdata]
					my log debug "done rop: ($rop) cb: ([dict get $op_handlers $rop])"
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
	method _user_permissioned {user newstate} { #<<<
		if {$newstate} {
			try {
				my invoke_handlers user_login $user
			} on error {errmsg options} {
				my log error "error invoking user_login handlers: $errmsg\n[dict get $options -errorinfo]"
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



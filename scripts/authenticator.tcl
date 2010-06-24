# vim: ft=tcl foldmarker=<<<,>>> foldmethod=marker ts=4 shiftwidth=4

# Handlers fired:
#	connected_users_changed()	- When a user connects or disconnects
#								  (only if authenticated as a user with
#								  system.admin perm)

cflib::pclass create m2::authenticator {
	superclass m2::api2

	property pbkey		"authenticator.pub"
	property profile_cb	""

	variable {*}{
		signals
		pubkey
		keys
		fqun
		last_login_message
		enc_chan
		login_chan
		login_subchans
		session_prkey
		session_pbkey_chan
		perms
		attribs
		prefs
		admin_info
		coro_pref
	}

	constructor {args} { #<<<
		package require crypto

		set coro_pref	"coro_[string map {:: _} [self]]"
		array set keys			{}
		set login_subchans		[dict create]
		array set perms			{}
		array set attribs		{}
		array set prefs			{}

		set fqun				""
		set last_login_message	""
		# Only used if authenticated user has system.admin
		set admin_info	{}

		sop::signal new signals(available) -name "[self] available"
		sop::signal new signals(established) -name "[self] established"
		sop::signal new signals(authenticated) -name "[self] authenticated"
		sop::signal new signals(login_pending) -name "[self] login_pending"
		sop::gate new signals(login_allowed) -name "[self] login_allowed" -mode "and"
		sop::signal new signals(got_perms) -name "[self] got_perms"
		sop::signal new signals(got_attribs) -name "[self] got_attribs"
		sop::signal new signals(got_prefs) -name "[self] got_prefs"

		$signals(login_allowed) attach_input $signals(login_pending) inverted
		$signals(login_allowed) attach_input $signals(authenticated) inverted
		$signals(login_allowed) attach_input $signals(established)
		
		my configure {*}$args

		if {![file exists $pbkey]} {
			error "Cannot find authenticator public key: \"$pbkey\""
		}

		set pubkey		[crypto::rsa::load_asn1_pubkey $pbkey]
		set keys(main)	[my generate_key]

		$signals(connected) attach_output [my code _connected_changed]
		$signals(available) attach_output [my code _available_changed]
		$signals(authenticated) attach_output [my code _authenticated_changed]
		$dominos(svc_avail_changed) attach_output [my code _svc_avail_changed]
	}

	#>>>

	method login {username password args} { #<<<
		if {![$signals(login_allowed) state]} {
			error "Cannot login at this time"
		}

		my rsj_req $enc_chan [list login $username $password] \
				[my code _login_resp [info coroutine]]

		$signals(login_pending) set_state 1
		lassign [yield] ok last_login_message

		if {$ok} {
			set fqun	$username
			log debug "Logged in ok, generating key" -suppress password
			#set handle	[crypto::rsa_generate_key 1024 17]
			#set pbkey	[crypto::rsa_get_public_key $handle]
			#set session_prkey	$handle
			set before	[clock microseconds]
			set K		[crypto::rsa::RSAKG 1024 0x10001]
			set after	[clock microseconds]
			log debug [format "1024 bit key generation time: %.3fms" [expr {($after - $before) / 1000.0}]] -suppress password
			set pbkey	[dict create \
					n		[dict get $K n] \
					e		[dict get $K e]]
			set session_prkey	$K
			my rsj_req [lindex $login_chan 0] \
					[list session_pbkey_update $pbkey] \
					[my code _session_pbkey_chan [info coroutine]]
			set resp	[yield]
			if {[lindex $resp 0]} {
				$signals(authenticated) set_state 1
			} else {
				log error "error updating session key: ([lindex $resp 1])" -suppress password
				m2 jm_disconnect [lindex $login_chan 0] [lindex $login_chan 1]
			}
		} else {
			log warning "Error logging in: ($last_login_message)" -suppress password
		}
		$signals(login_pending) set_state 0

		return [$signals(authenticated) state]
	}

	#>>>
	method login_svc {svc prkeyfn} { #<<<
		if {![$signals(login_allowed) state]} {
			error "Cannot login at this time"
		}

		if {![file exists $prkeyfn]} {
			error "No such file: ($prkeyfn)"
		}
		try {
			set prkey	[crypto::rsa::load_asn1_prkey $prkeyfn]
		} on error {errmsg options} {
			error "Error reading private key ($prkeyfn): $errmsg"
		}

		# Get a cookie from auth backend <<<
		#log debug "authenticator wa cookie o kudasai"
		try {
			my enc_chan_req [list "cookie_o_kudasai" $svc]
		} on error {errmsg options} {
			error "Error: auth server won't give us a cookie: $errmsg"
		} on ok {res} {
			lassign $res cookie_idx cookie
		}
		# Get a cookie from auth backend >>>

		#set e_cookie	[crypto::rsa_private_encrypt $prkey $cookie]
		set e_cookie	[crypto::rsa::RSAES-OAEP-Sign \
				[dict get $prkey n] \
				[dict get $prkey d] \
				$cookie \
				{} \
				$::crypto::rsa::sha1 \
				$::crypto::rsa::MGF]

		my rsj_req $enc_chan \
				[list login_svc $svc $cookie_idx $e_cookie] \
				[my code _login_resp [info coroutine]]

		$signals(login_pending) set_state 1
		lassign [yield] ok last_login_message

		if {$ok} {
			set fqun	"svc%$svc"
			set session_prkey	$prkey
			$signals(authenticated) set_state 1
		} else {
			log warning "Error logging in: ($last_login_message)"
		}
		$signals(login_pending) set_state 0

		$signals(authenticated) state
	}

	#>>>
	method logout {} { #<<<
		if {![$signals(authenticated) state]} {
			error "Authenticator::logout: not logged in"
		}
		if {[info exists login_chan]} {
			?? {log debug "Sending login_chan jm_disconnect: seq: [lindex $login_chan 0], prev_seq: [lindex $login_chan 1]"}
			my jm_disconnect [lindexperms $login_chan 0] [lindex $login_chan 1]
			unset login_chan
		}
		dict for {subchan name} $login_subchans {
			?? {log debug "Sending login subchan disconnect: seq: [lindex $subchan 0], prev_seq: [lindex $subchan 1]"}
			my jm_disconnect [lindex $subchan 0] [lindex $subchan 1]
			switch -- $name {
				userinfo {
					$signals(got_perms) set_state 0
					$signals(got_attribs) set_state 0
					$signals(got_prefs) set_state 0
					unset perms
					unset prefs
					unset attribs
					array set perms		{}
					array set prefs		{}
					array set attribs	{}
				}

				admin_chan {
					set admin_info	{}
				}

				session_chan {
				}

				default {
					log warning "Cancelled unhandled login subchan type \"$name\""
				}
			}
		}
		set login_subchans	[dict create]
		if {[info exists session_pbkey_chan]} {
			?? {log debug "Sending session_pbkey_chan jm_disconnect: seq: [lindex $session_pbkey_chan 0], prev_seq: [lindex $session_pbkey_chan 1]"}
			my jm_disconnect [lindex $session_pbkey_chan 0] [lindex $session_pbkey_chan 1]
			unset session_pbkey_chan
		}
		$signals(authenticated) set_state 0
	}

	#>>>
	method get_svc_pbkey {svc} { #<<<
		if {![$signals(authenticated) state]} {
			error "Not authenticated yet"
		}

		lassign [my _simple_req [list "get_svc_pubkey" $svc]] ok res

		if {$ok} {
			return $res
		} else {
			error $res
		}
	}

	#>>>
	method connect_svc {svc} { #<<<
		m2::connector new [self] $svc
	}

	#>>>
	method decrypt_with_session_prkey {data} { #<<<
		set K	[list \
				[dict get $session_prkey p] \
				[dict get $session_prkey q] \
				[dict get $session_prkey dP] \
				[dict get $session_prkey dQ] \
				[dict get $session_prkey qInv] \
		]
		crypto::rsa::RSAES-OAEP-Decrypt $K $data {} $crypto::rsa::sha1 $crypto::rsa::MGF
	}

	#>>>
	method fqun {} { #<<<
		if {![$signals(authenticated) state]} {
			error "Not authenticated yet"
		}
		return $fqun
	}

	#>>>
	method get_user_pbkey {fqun} { #<<<
		if {![$signals(established) state]} {
			error "No encrypted channel to the authenticator established yet"
		}
		my rsj_req $enc_chan [list get_user_pbkey $fqun] [list apply {
			{coro args} {$coro $args}
		} [info coroutine]]

		while {1} {
			lassign [yield] msg

			switch -- [dict get $msg type] {
				ack {
					return [dict get $msg data]
				}

				nack {
					error [dict get $msg data]
				}

				default {
					log error "got unexpected type: ([dict get $msg type])"
				}
			}
		}
	}

	#>>>
	method last_login_message {} { #<<<
		set last_login_message
	}

	#>>>
	method auth_chan_req {data cb} { #<<<
		if {![$signals(authenticated) state]} {
			error "Not authenticated yet"
		}

		my rsj_req [lindex $login_chan 0] $data $cb
	}

	#>>>
	method enc_chan_req {data {cb {}}} { #<<<
		if {![$signals(established) state]} {
			error "No encrypted channel to the authenticator established yet"
		}

		if {$cb ne {}} {
			tailcall my rsj_req $enc_chan $data $cb
		} else {
			my rsj_req $enc_chan $data [list apply {
				{coro args} {$coro $args}
			} [info coroutine]]

			while {1} {
				lassign [yield] msg

				switch -- [dict get $msg type] {
					ack		{return [dict get $msg data]}
					nack	{error [dict get $msg data]}
					default	{
						log warning "Not expecting response type: ([dict get $msg type])"
					}
				}
			}
		}
	}

	#>>>

	method perm {perm} { #<<<
		if {![$signals(got_perms) state]} {
			log warning "haven't gotten perms update yet, waiting..."
			my waitfor got_perms
			log warning "received perms"
		}

		info exists perms($perm)
	}

	#>>>
	method perms {} { #<<<
		array names perms
	}

	#>>>
	method attrib {attrib args} { #<<<
		if {![$signals(got_attribs) state]} {
			log warning "haven't gotten attribs update yet, waiting..."
			my waitfor got_attribs
			log warning "received attribs"
		}
		if {[info exists attribs($attrib)]} {
			return $attribs($attrib)
		} else {
			if {[llength $args] == 1} {
				lindex $args 0
			} else {
				error "No attrib ($attrib) defined"
			}
		}
	}

	#>>>
	method pref {pref args} { #<<<
		if {![$signals(got_prefs) state]} {
			log warning "haven't gotten prefs update yet, waiting..."
			my waitfor got_prefs
			log warning "received prefs"
		}
		if {[info exists prefs($pref)]} {
			return $prefs($pref)
		} else {
			if {[llength $args] == 1} {
				return [lindex $args 0]
			} else {
				error "No pref ($pref) defined"
			}
		}
	}

	#>>>

	method set_pref {pref newvalue} { #<<<
		if {![$signals(authenticated) state]} {
			error "Not authenticated yet"
		}
		set res	[my _simple_req [list set_pref $pref $newvalue]]
		if {[lindex $res 0]} {
			#log debug "pref updated"
		} else {
			#log error "Authenticator::set_pref: error setting pref ($pref) to ($newvalue): [lindex $res 1]"
			error "error setting pref ($pref) to ($newvalue): [lindex $res 1]"
		}
	}

	#>>>
	method change_password {old new1 new2} { #<<<
		if {![$signals(authenticated) state]} {
			error "Not authenticated yet"
		}
		set res	[my _simple_req [list change_password $old $new1 $new2]]
		if {[lindex $res 0]} {
			#log debug "password updated" -suppress {old new1 new2}
		} else {
			error [lindex $res 1]
		}
	}

	#>>>

	method is_admin {} { #<<<
		if {![$signals(authenticated) state]} {
			error "Not authenticated yet"
		}
		my perm system.admin
	}

	#>>>
	# Only available if authenticated as a user with system.admin perm
	method get_admin_info {} { #<<<
		return $admin_info
	}

	#>>>
	method admin {op data} { #<<<
		if {![my is_admin]} {error "Not an administrator"}

		set admin_chan	[dict get $admin_info admin_chan]
		my rsj_req [lindex $admin_chan 0] [list $op $data] [list apply {
			{coro args} {$coro $args}
		} [info coroutine]

		set aid	[after 1000 [list [info coroutine [list type "timeout"]]]
		while {1} {
			lassign [yield] msg
			after cancel $aid; set aid ""

			switch -- [dict get $msg type] {
				ack		{return [dict get $msg data]}
				nack	{error [dict get $msg data]}
				timeout	{error "timeout"}
				default {
					log warning "Not expecting response type ([dict get $msg type])"
				}
			}
		}
	}

	#>>>

	method _connected_changed {newstatus} { #<<<
		if {!($newstatus)} {
			$signals(available) set_state 0
		}
	}

	#>>>
	method _available_changed {newstatus} { #<<<
		if {$newstatus} {
			coroutine ${coro_pref}crypt_setup my _crypt_setup
		} else {
			$signals(established) set_state 0
		}
	}

	#>>>
	method _crypt_setup {} { #<<<
		set pending_cookie	[my generate_key]

		set n		[dict get $pubkey n]
		set e		[dict get $pubkey e]
		set e_key		[crypto::rsa::RSAES-OAEP-Encrypt $n $e $keys(main) {} $crypto::rsa::sha1 $crypto::rsa::MGF]
		set e_cookie	[crypto::rsa::RSAES-OAEP-Encrypt $n $e $pending_cookie {} $crypto::rsa::sha1 $crypto::rsa::MGF]
		#my req "authenticator" [list crypt_setup \
		#	[crypto::armour $e_key] \
		#	[crypto::armour $e_cookie] \
		#] [list apply {
		#	{coro args} {$coro $args}
		#} [info coroutine]]
		my req "authenticator" [list crypt_setup $e_key $e_cookie] [list apply {
			{coro args} {$coro $args}
		} [info coroutine]]

		while {1} {
			lassign [yield] msg

			switch -- [dict get $msg type] {
				ack - jm { #<<<
					try {
						set pdata			[my decrypt $keys(main) [dict get $msg data]]
						set was_encrypted	1
					} on error {errmsg options} {
						log error "error decrypting message: $errmsg" \
								-suppress {cookie data}
						return
					}
					#>>>
				}

				default { #<<<
					set pdata			[dict get $msg data]
					set was_encrypted	0
					#>>>
				}
			}

			switch -- [dict get $msg type] {
				ack { #<<<
					if {$pdata eq $pending_cookie} {
						$signals(established) set_state 1
					} else {
						log error "cookie challenge from server did not match" -suppress {cookie data}
					}
					#>>>
				}

				nack { #<<<
					log warning "got nack: [dict get $msg data]" -suppress {cookie data}
					break
					#>>>
				}

				pr_jm { #<<<
					my register_jm_key [dict get $msg seq] $keys(main)
					if {![info exists enc_chan]} {
						set enc_chan [dict get $msg seq]
					} else {
						log warning "already have enc_chan??" -suppress {cookie data}
					}
					#>>>
				}

				jm_can { #<<<
					$signals(established) set_state 0
					unset enc_chan
					break
					#>>>
				}
			}
		}
	}

	#>>>
	method _authenticated_changed {newstatus} { #<<<
		if {$newstatus} {
			my invoke_handlers logged_in
		} else {
			my invoke_handlers logged_out
		}
	}

	#>>>
	method _login_resp {coro msg} { #<<<
		switch -- [dict get $msg type] {
			ack { #<<<
				if {![info exists login_chan]} {
					log error "got ack, but no login_chan!"
				}
				after idle [list $coro [list 1 [dict get $msg data]]]
				#>>>
			}

			nack { #<<<
				#log debug "nack'ed, setting result([dict get $msg prev_seq]) := ([list 0 [dict get $msg data]])"
				after idle [list $coro [list 0 [dict get $msg data]]]
				#>>>
			}

			pr_jm { #<<<
				set tag		[lindex [dict get $msg data] 0]
				switch -- $tag {
					login_chan { #<<<
						if {![info exists login_chan]} {
							set login_chan	[list [dict get $msg seq] [dict get $msg prev_seq]]
						} else {
							log error "got a login_chan pr_jm ([dict get $msg seq]) when we already have a login_chan set ($login_chan)"
						}
						#>>>
					}

					select_profile { #<<<
						set defined_profiles	[lindex [dict get $msg data] 1]
						if {[llength $defined_profiles] == 2} {
							set selected_profile	[lindex $defined_profiles 0]
						} else {
							try {
								if {$profile_cb eq ""} {
									log warning "Asked to select a profile but no profile_cb was defined"
									set selected_profile	""
								} else {
									set selected_profile \
											[uplevel #0 $profile_cb [list $defined_profiles]]
								}
							} on error {errmsg options} {
								log error "Unhandled error: $errmsg\n[dict get $options -errorinfo]"
								set selected_profile	""
							}
						}
						try {
							my rsj_req [dict get $msg seq] \
									[list select_profile $selected_profile] \
									[list apply {{args} {}}]
						} on error {errmsg options} {
							log error "Unhandled error trying to send selected profile to the backend: $errmsg\n[dict get $options -errorinfo]"
						}
						#>>>
					}

					perms - attribs - prefs { #<<<
						set key	[list [dict get $msg seq] [dict get $msg prev_seq]]
						dict set login_subchans $key	"userinfo"

						my _update_userinfo [dict get $msg data]
						#>>>
					}

					session_chan { #<<<
						set heartbeat_interval	[lindex [dict get $msg data] 1]
						set key	[list [dict get $msg seq] [dict get $msg prev_seq]]
						# Isn't strictly a sub channel of login_chan...
						dict set login_subchans $key	"session_chan"
						if {$heartbeat_interval ne ""} {
							my _setup_heartbeat $heartbeat_interval [dict get $msg seq]
						}
						#>>>
					}

					admin_chan { #<<<
						set key		[list [dict get $msg seq] [dict get $msg prev_seq]]
						# Isn't strictly a sub channel of login_chan...
						dict set login_subchans $key	"admin_chan"
						dict set admin_info admin_chan		$key
						dict set admin_info connected_users	[lindex [dict get $msg data] 1]
						#>>>
					}

					default { #<<<
						set key	[list [dict get $msg seq] [dict get $msg prev_seq]]
						log warning "unknown login subchan: ($key) ($tag)"
						dict set login_subchans $key	"unknown"
						#>>>
					}
				}
				#>>>
			}

			jm { #<<<
				set key	[list [dict get $msg seq] [dict get $msg prev_seq]]
				if {![dict exists $login_subchans $key]} {
					log error "not sure what to do with jm: ($svc,[dict get $msg seq],[dict get $msg prev_seq]) ([dict get $msg data])"
					return
				}

				switch -- [dict get $login_subchans $key] {
					userinfo { #<<<
						my _update_userinfo [dict get $msg data]
						#>>>
					}
					admin_chan { #<<<
						set op	[lindex [dict get $msg data] 0]
						switch -- $op {
							user_connected { #<<<
								set new_user_fqun	[lindex [dict get $msg data] 1]
								if {$new_user_fqun ni [dict get $admin_info connected_users]} {
									dict lappend admin_info connected_users $new_user_fqun
									invoke_handlers connected_users_changed
								}
								#>>>
							}
							user_disconnected { #<<<
								set old_user_fqun	[lindex [dict get $msg data] 1]
								set idx		[lsearch [dict get $admin_info connected_users] $old_user_fqun]
								if {$idx != -1} {
									dict set admin_info connected_users \
											[lreplace [dict get $admin_info connected_users] $idx $idx]
									my invoke_handlers connected_users_changed
								}
								#>>>
							}
							default { #<<<
								log error "Unrecognised admin update: ($op)"
								#>>>
							}
						}
						#>>>
					}
					default { #<<<
						log error "registered but unhanded login subchan seq: ($key) type: ([dict get $login_subchans $key])"
						#>>>
					}
				}
				#>>>
			}

			jm_can { #<<<
				if {
					[info exists login_chan] &&
					[dict get $msg seq] == [lindex $login_chan 0]
				} {
					unset login_chan
					#log debug "Got login_chan cancel, calling logout"
					my logout
				} else {
					set key	[list [dict get $msg seq] [dict get $msg prev_seq]]
					if {[dict exists $login_subchans $key]} {
						switch -- [dict get $login_subchans $key] {
							userinfo { #<<<
								$signals(got_perms) set_state 0
								$signals(got_attribs) set_state 0
								$signals(got_prefs) set_state 0

								array unset perms
								array unset attribs
								array unset prefs
								#>>>
							}
							admin_chan { #<<<
								set admin_info	""
								#>>>
							}
							session_chan { #<<<
								#>>>
							}
							default { #<<<
								log error "registered but unhandled login subchan cancel: seq: ([dict get $msg seq]) type: ([dict get $login_subchans $key])"
								#>>>
							}
						}

						array unset login_subchan [dict get $msg seq]
					} else {
						log error "unexpected jm_can: seq: ([dict get $msg seq])"
					}
				}
				#>>>
			}
		}
	}

	#>>>
	method _session_pbkey_chan {coro msg} { #<<<
		switch -- [dict get $msg type] {
			ack { #<<<
				#log debug "got ack, setting result([dict get $msg prev_seq]) := ([list 1 [dict get $msg data]])"
				after idle [list $coro [list 1 [dict get $msg data]]]
				#>>>
			}

			nack { #<<<
				log warning "got nack, setting result([dict get $msg prev_seq]) := ([list 0 [dict get $msg data]])"
				after idle [list $coro [list 0 [dict get $msg data]]]
				#>>>
			}

			pr_jm { #<<<
				if {[info exists session_pbkey_chan]} {
					log warning "Already have session_pbkey_chan: ($session_pbkey_chan)"
				}
				set session_pbkey_chan	[list [dict get $msg seq] [dict get $msg prev_seq]]
				#>>>
			}

			jm { #<<<
				if {[dict get $msg seq] != [lindex $session_pbkey_chan 0]} {
					log error "unrecognised jm chan: ([dict get $msg seq])"
					return
				}

				set op	[lindex [dict get $msg data] 0]
				switch -- $op {
					refresh_key { #<<<
						set K		[crypto::rsa::RSAKG 1024 0x10001]
						# TODO: need a replacement for this
						#crypto::rsa_free_key $session_prkey
						set pbkey	[dict create \
								n	[dict get $K n] \
								e	[dict get $K e]]
						set session_prkey	$K
						my rsj_req \
								[lindex $session_pbkey_chan 0] \
								[list session_pbkey_update $pbkey] \
								[my code _session_pbkey_update_result]
						#>>>
					}
					default { #<<<
						log error "jm(session_pbkey_chan): invalid op: ($op), data: ([dict get $msg data])"
						#>>>
					}
				}
				#>>>
			}

			jm_can { #<<<
				if {
					[info exists session_pbkey_chan] &&
					[lindex $session_pbkey_chan 0] == [dict get $msg seq]
				} {
					unset session_pbkey_chan
					my logout
				} else {
					log warning "non session_pbkey_chan jm cancelled"
				}
				#>>>
			}
		}
	}

	#>>>
	method _session_pbkey_update_result {msg} { #<<<
		switch -- [dict get $msg type] {
			ack {
				#log debug "session key update ok: ([dict get $msg data])"
			}

			nack {
				log error "session key update problem: ([dict get $msg data])"
			}

			default {
				log error "unhandled type: [dict get $msg type]"
			}
		}
	}

	#>>>
	method _simple_req {data} { #<<<
		if {![$signals(authenticated) state]} {
			error "Not authenticated yet"
		}

		my rsj_req [lindex $login_chan 0] $data [list apply {
			{coro args} {$coro $args}
		} [info coroutine]]

		while {1} {
			lassign [yield] msg

			switch -- [dict get $msg type] {
				ack		{
					set res	[list 1 [dict get $msg data]]
					break
				}

				nack	{
					set res	[list 0 [dict get $msg data]]
					break
				}

				default	{
					log warning "Not expecting reply type ([dict get $msg type])"
				}
			}
		}

		return $res
	}

	#>>>
	method _svc_avail_changed {} { #<<<
		$signals(available) set_state [my svc_avail authenticator]
	}

	#>>>
	method _update_userinfo {data} { #<<<
		switch -- [lindex $data 0] {
			perms { #<<<
				foreach permname [lindex $data 1] {
					switch -- [string index $permname 0] {
						"-" {
							array unset perms [string range $permname 1 end]
						}

						"+" {
							set perms([string range $permname 1 end])	1
						}

						default {
							set perms($permname)	1
						}
					}
				}
				$signals(got_perms) set_state 1
				#>>>
			}

			attribs { #<<<
				foreach {attrib value} [lindex $data 1] {
					switch -- [string index $attrib 0] {
						"-" {
							array unset attribs [string range $attrib 1 end]
						}

						"+" {
							set attribs([string range $attrib 1 end])	$value
						}

						default {
							set attribs($attrib)	$value
						}
					}
				}
				$signals(got_attribs) set_state 1
				#>>>
			}

			prefs { #<<<
				foreach {pref value} [lindex $data 1] {
					switch -- [string index $pref 0] {
						"-" {
							array unset prefs [string range $pref 1 end]
						}

						"+" {
							set prefs([string range $pref 1 end])	$value
						}

						default {
							set prefs($pref)	$value
						}
					}
				}
				$signals(got_prefs) set_state 1
				#>>>
			}

			default { #<<<
				log error "unexpected update type: ([lindex $data 0])"
				#>>>
			}
		}
	}

	#>>>
	method _setup_heartbeat {heartbeat_interval session_jmid} { #<<<
		set heartbeat_interval	[expr {$heartbeat_interval - 10}]
		if {$heartbeat_interval < 1} {
			log warning "Very short heartbeat interval: $heartbeat_interval"
			set heartbeat_interval	1
		}

		set heartbeat_afterid \
				[after [expr {round($heartbeat_interval * 1000)}] \
				[my code _send_heartbeat $heartbeat_interval $session_jmid]]
	}

	#>>>
	method _send_heartbeat {heartbeat_interval session_jmid} { #<<<
		my rsj_req $session_jmid [list _heartbeat] [list apply {
			{msg} {
				# Not interested
			}
		}]

		set heartbeat_afterid \
				[after [expr {round($heartbeat_interval * 1000)}] \
				[my code _send_heartbeat $heartbeat_interval $session_jmid]]
	}

	#>>>
}



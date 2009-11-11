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
		array set login_subchans	{}
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
			error "Cannot find authenticator public key"
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
		my log debug "awaiting response" -suppress password
		lassign [yield] \
				ok last_login_message
		my log debug "got response: ($ok $last_login_message)" -suppress password

		if {$ok} {
			set fqun	$username
			my log debug "Logged in ok, generating key" -suppress password
			#set handle	[crypto::rsa_generate_key 1024 17]
			#set pbkey	[crypto::rsa_get_public_key $handle]
			#set session_prkey	$handle
			set before	[clock microseconds]
			set K		[crypto::rsa::RSAKG 1024 0x10001]
			set after	[clock microseconds]
			my log debug [format "1024 bit key generation time: %.3fms" [expr {($after - $before) / 1000.0}]] -suppress password
			set pbkey	[dict create \
					n		[dict get $K n] \
					e		[dict get $K e]]
			set session_prkey	$K
			my rsj_req [lindex $login_chan 0] \
					[list session_pbkey_update $pbkey] \
					[my code _session_pbkey_chan [info coroutine]]
			my log debug "awaiting session_pbkey_update response" -suppress password
			set resp	[yield]
			my log debug "got session_pbkey_update response: ($resp)" -suppress password
			if {[lindex $resp 0]} {
				$signals(authenticated) set_state 1
			} else {
				my log debug "error updating session key: ([lindex $resp 1])" -suppress password
				m2 jm_disconnect [lindex $login_chan 0] [lindex $login_chan 1]
			}
		} else {
			my log warning "Error logging in: ($last_login_message)" -suppress password
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
		my log debug "authenticator wa cookie o kudasai"
		try {
			my enc_chan_req [list "cookie_o_kudasai" $svc]
		} on error {errmsg options} {
			error "Error: auth server won't give us a cookie: $errmsg"
		} on ok {res} {
			lassign $res cookie_idx cookie
			my log debug "Got cookie index ($cookie_idx)"
		}
		# Get a cookie from auth backend >>>

		#set e_cookie	[crypto::rsa_private_encrypt $prkey $cookie]
		set e_cookie	[crypto::rsa::RSAES-OAEP-Sign $prkey $cookie]

		my rsj_req $enc_chan \
				[list login_svc $svc $cookie_idx $e_cookie] \
				[my code _login_resp [info coroutine]]

		$signals(login_pending) set_state 1
		my log debug "awaiting response"
		lassign [yield] ok last_login_message
		my log debug "got response: ($ok $last_login_message)"

		if {$ok} {
			set fqun	"svc%$svc"
			set session_prkey	$prkey
			$signals(authenticated) set_state 1
		} else {
			my log warning "Error logging in: ($last_login_message)"
		}
		$signals(login_pending) set_state 0

		return [$signals(authenticated) state]
	}

	#>>>
	method logout {} { #<<<
		if {![$signals(authenticated) state]} {
			error "Authenticator::logout: not logged in"
		}
		if {[info exists login_chan]} {
			my jm_disconnect [lindex $login_chan 0] [lindex $login_chan 1]
			unset login_chan
		}
		foreach subchan [array names login_subchans] {
			my jm_disconnect [lindex $subchan 0] [lindex $subchan 1]
			array unset login_subchans $subchan
		}
		if {[info exists session_pbkey_chan]} {
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
		set K	[dict with session_prkey {list $p $q $dP $dQ $qInv}]
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
		my log debug "sending request on $enc_chan"
		my rsj_req $enc_chan [list get_user_pbkey $fqun] [list apply {
			{coro args} {$coro $args}
		} [info coroutine]]

		while {1} {
			lassign [yield] msg_data
			dict with msg_data {}

			switch -- $type {
				ack {
					my log debug "OK!"
					return $data
				}

				nack {
					my log warning "DENIED!"
					error $data
				}

				default {
					my log error "got unexpected type: ($type)"
				}
			}
		}
	}

	#>>>
	method last_login_message {} { #<<<
		return $last_login_message
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
			return [my rsj_req $enc_chan $data $cb]
		} else {
			my rsj_req $enc_chan $data [list apply {
				{coro args} {$coro $args}
			} [info coroutine]]

			while {1} {
				lassign [yield] msg_data
				dict with msg_data {}

				switch -- $type {
					ack		{return $data}
					nack	{error $data}
					default	{
						my log warning "Not expecting response type: ($type)"
					}
				}
			}
		}
	}

	#>>>

	method perm {perm} { #<<<
		if {![$signals(got_perms) state]} {
			my log warning "haven't gotten perms update yet, waiting..."
			my waitfor got_perms
			my log warning "received perms"
		}

		info exists perms($perm)
	}

	#>>>
	method attrib {attrib args} { #<<<
		if {![$signals(got_attribs) state]} {
			my log warning "haven't gotten attribs update yet, waiting..."
			my waitfor got_attribs
			my log warning "received attribs"
		}
		if {[info exists attribs($attrib)]} {
			return $attribs($attrib)
		} else {
			if {[llength $args] == 1} {
				my log debug "attrib not set, using fallback"
				return [lindex $args 0]
			} else {
				error "No attrib ($attrib) defined"
			}
		}
	}

	#>>>
	method pref {pref args} { #<<<
		if {![$signals(got_prefs) state]} {
			my log warning "haven't gotten prefs update yet, waiting..."
			my waitfor got_prefs
			my log warning "received prefs"
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
			my log debug "pref updated"
		} else {
			#my log error "Authenticator::set_pref: error setting pref ($pref) to ($newvalue): [lindex $res 1]"
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
			my log debug "password updated" -suppress {old new1 new2}
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

		my log trivia "waiting for reply to seq: ($seq)"
		set aid	[after 1000 [list [info coroutine [list type "timeout"]]]
		while {1} {
		lassign [yield] msg_data
			dict with msg_data {}
			after cancel $aid; set aid ""

			switch -- $type {
				ack		{return $data}
				nack	{error $data}
				timeout	{error "timeout"}
				default {
					my log warning "Not expecting response type ($type)"
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
		my log debug "negotiating session_key ([my mungekey $keys(main)]), cookie: ([my mungekey $pending_cookie])"

		set n		[dict get $pubkey n]
		set e		[dict get $pubkey e]
		set e_key		[crypto::rsa::RSAES-OAEP-Encrypt $n $e $keys(main) {} $crypto::rsa::sha1 $crypto::rsa::MGF]
		set e_cookie	[crypto::rsa::RSAES-OAEP-Encrypt $n $e $pending_cookie {} $crypto::rsa::sha1 $crypto::rsa::MGF]
		my log debug "e_key length: ([string length $e_key]), e_cookie length: ([string length $e_cookie])"
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
			lassign [yield] msg_data
			dict with msg_data {}

			switch -- $type {
				ack - jm { #<<<
					try {
						set pdata			[my decrypt $keys(main) $data]
						set was_encrypted	1
						my log debug "decrypted ($type) with key ([my mungekey $keys(main)])" -suppress {cookie data}
					} on error {errmsg options} {
						my log error "error decrypting message: $errmsg" \
								-suppress {cookie data}
						return
					}
					#>>>
				}

				default { #<<<
					set pdata			$data
					set was_encrypted	0
					#>>>
				}
			}

			switch -- $type {
				ack { #<<<
					if {$pdata eq $pending_cookie} {
						$signals(established) set_state 1
					} else {
						my log debug "cookie challenge from server did not match" -suppress {cookie data}
					}
					#>>>
				}

				nack { #<<<
					my log warning "got nack: $data" -suppress {cookie data}
					break
					#>>>
				}

				pr_jm { #<<<
					my register_jm_key $seq $keys(main)
					if {![info exists enc_chan]} {
						set enc_chan $seq
					} else {
						my log warning "already have enc_chan??" -suppress {cookie data}
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
	method _login_resp {coro msg_data} { #<<<
		dict with msg_data {}

		switch -- $type {
			ack { #<<<
				if {![info exists login_chan]} {
					my log error "got ack, but no login_chan!"
				}
				after idle [list $coro [list 1 $data]]
				#>>>
			}

			nack { #<<<
				my log debug "nack'ed, setting result($prev_seq) := ([list 0 $data])"
				after idle [list $coro [list 0 $data]]
				#>>>
			}

			pr_jm { #<<<
				set tag		[lindex $data 0]
				my log debug "tag: ($tag)"
				switch -- $tag {
					login_chan { #<<<
						if {![info exists login_chan]} {
							set login_chan	[list $seq $prev_seq]
						} else {
							my log error "got a login_chan pr_jm ($seq) when we already have a login_chan set ($login_chan)"
						}
						#>>>
					}

					select_profile { #<<<
						set defined_profiles	[lindex $data 1]
						if {[llength $defined_profiles] == 2} {
							set selected_profile	[lindex $defined_profiles 0]
						} else {
							try {
								if {$profile_cb eq ""} {
									my log warning "Asked to select a profile but no profile_cb was defined"
									set selected_profile	""
								} else {
									set selected_profile \
											[uplevel #0 $profile_cb [list $defined_profiles]]
								}
							} on error {errmsg options} {
								my log error "Unhandled error: $errmsg\n[dict get $options -errorinfo]"
								set selected_profile	""
							}
						}
						try {
							my rsj_req $seq \
									[list select_profile $selected_profile] \
									[list apply {{args} {}}]
						} on error {errmsg options} {
							my log error "Unhandled error trying to send selected profile to the backend: $errmsg\n[dict get $options -errorinfo]"
						}
						#>>>
					}

					perms - attribs - prefs { #<<<
						set key	[list $seq $prev_seq]
						set login_subchans($key)	"userinfo"

						my _update_userinfo $data
						#>>>
					}

					session_chan { #<<<
						set heartbeat_interval	[lindex $data 1]
						set key	[list $seq $prev_seq]
						# Isn't strictly a sub channel of login_chan...
						set login_subchans($key)	"session_chan"
						if {$heartbeat_interval ne ""} {
							my _setup_heartbeat $heartbeat_interval $seq
						}
						#>>>
					}

					admin_chan { #<<<
						set key		[list $seq $prev_seq]
						# Isn't strictly a sub channel of login_chan...
						set login_subchans($key)	"admin_chan"
						dict set admin_info admin_chan		$key
						dict set admin_info connected_users	[lindex $data 1]
						#>>>
					}

					default { #<<<
						set key	[list $seq $prev_seq]
						my log warning "unknown login subchan: ($key) ($tag)"
						set login_subchans($key)	"unknown"
						#>>>
					}
				}
				#>>>
			}

			jm { #<<<
				set key	[list $seq $prev_seq]
				if {![info exists login_subchans($key)]} {
					my log error "not sure what to do with jm: ($svc,$seq,$prev_seq) ($data)"
					return
				}

				switch -- $login_subchans($key) {
					userinfo { #<<<
						my _update_userinfo $data
						#>>>
					}
					admin_chan { #<<<
						set op	[lindex $data 0]
						switch -- $op {
							user_connected { #<<<
								set new_user_fqun	[lindex $data 1]
								if {$new_user_fqun ni [dict get $admin_info connected_users]} {
									dict lappend admin_info connected_users $new_user_fqun
									my log debug "Firing connected_users_changed handler (user_connected): [dump_handlers]"
									invoke_handlers connected_users_changed
								}
								#>>>
							}
							user_disconnected { #<<<
								set old_user_fqun	[lindex $data 1]
								set idx		[lsearch [dict get $admin_info connected_users] $old_user_fqun]
								if {$idx != -1} {
									dict set admin_info connected_users \
											[lreplace [dict get $admin_info connected_users] $idx $idx]
									my log debug "Firing connected_users_changed handler (user_disconnected): [dump_handlers]"
									invoke_handlers connected_users_changed
								}
								#>>>
							}
							default { #<<<
								my log error "Unrecognised admin update: ($op)"
								#>>>
							}
						}
						#>>>
					}
					default { #<<<
						my log error "registered but unhanded login subchan seq: ($key) type: ($login_subchans($key))"
						#>>>
					}
				}
				#>>>
			}

			jm_can { #<<<
				if {
					[info exists login_chan] &&
					$seq == [lindex $login_chan 0]
				} {
					unset login_chan
					my log debug "Got login_chan cancel, calling logout"
					my logout
				} else {
					set key	[list $seq $prev_seq]
					if {[info exists login_subchans($key)]} {
						switch -- $login_subchans($key) {
							userinfo { #<<<
								my log debug "userinfo channel cancelled"
								$signals(got_perms) set_state 0
								$signals(got_attribs) set_state 0
								$signals(got_prefs) set_state 0

								array unset perms
								array unset attribs
								array unset prefs
								#>>>
							}
							admin_chan { #<<<
								my log debug "admin_chan cancelled"
								set admin_info	""
								#>>>
							}
							session_chan { #<<<
								my log debug "session_chan cancelled"
								#>>>
							}
							default { #<<<
								my log error "registered but unhandled login subchan cancel: seq: ($seq) type: ($login_subchans($key))"
								#>>>
							}
						}

						array unset login_subchan $seq
					} else {
						my log error "unexpected jm_can: seq: ($seq)"
					}
				}
				#>>>
			}
		}
	}

	#>>>
	method _session_pbkey_chan {coro msg_data} { #<<<
		dict with msg_data {}

		switch -- $type {
			ack { #<<<
				my log debug "got ack, setting result($prev_seq) := ([list 1 $data])"
				after idle [list $coro [list 1 $data]]
				#>>>
			}

			nack { #<<<
				my log warning "got nack, setting result($prev_seq) := ([list 0 $data])"
				after idle [list $coro [list 0 $data]]
				#>>>
			}

			pr_jm { #<<<
				if {[info exists session_pbkey_chan]} {
					my log warning "Already have session_pbkey_chan: ($session_pbkey_chan)"
				}
				set session_pbkey_chan	[list $seq $prev_seq]
				#>>>
			}

			jm { #<<<
				if {$seq != [lindex $session_pbkey_chan 0]} {
					my log error "unrecognised jm chan: ($seq)"
					return
				}

				set op	[lindex $data 0]
				switch -- $op {
					refresh_key { #<<<
						my log debug "jm(session_pbkey_chan): got notification to renew session keypair"
						my log debug "jm(session_pbkey_chan): generating keypair"
						set K		[crypto::rsa::RSAKG 1024 0x10001]
						my log debug "jm(session_pbkey_chan): done generating keypair"
						# TODO: need a replacement for this
						#crypto::rsa_free_key $session_prkey
						set pbkey	[dict create \
								n	[dict get $K n] \
								e	[dict get $K e]]
						set session_prkey	$K
						my log debug "jm(session_pbkey_chan): sending public key to backend"
						my rsj_req \
								[lindex $session_pbkey_chan 0] \
								[list session_pbkey_update $pbkey] \
								[my code _session_pbkey_update_result]
						#>>>
					}
					default { #<<<
						my log error "jm(session_pbkey_chan): invalid op: ($op), data: ($data)"
						#>>>
					}
				}
				#>>>
			}

			jm_can { #<<<
				if {
					[info exists session_pbkey_chan] &&
					[lindex $session_pbkey_chan 0] == $seq
				} {
					my log debug "got cancel on session_pbkey_chan"
					unset session_pbkey_chan
					my logout
				} else {
					my log warning "non session_pbkey_chan jm cancelled"
				}
				#>>>
			}
		}
	}

	#>>>
	method _session_pbkey_update_result {msg_data} { #<<<
		dict with msg_data {}

		switch -- $type {
			ack {
				my log debug "session key update ok: ($data)"
			}

			nack {
				my log error "session key update problem: ($data)"
			}

			default {
				my log error "unhandled type: $type"
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
			lassign [yield] msg_data
			dict with msg_data {}

			switch -- $type {
				ack		{
					set res	[list 1 $data]
					break
				}

				nack	{
					set res	[list 0 $data]
					break
				}

				default	{
					my log warning "Not expecting reply type ($type)"
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
							my log debug "setting attribs([string range $attrib 1 end]) to ($value)"
							set attribs([string range $attrib 1 end])	$value
						}

						default {
							my log debug "setting attribs($attrib) to ($value)"
							set attribs($attrib)	$value
						}
					}
				}
				$signals(got_attribs) set_state 1
				#>>>
			}

			prefs { #<<<
				foreach {pref value} [lindex $data 1] {
					my log debug "Applying pref update: ($pref) ($value)"
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
				my log error "unexpected update type: ([lindex $data 0])"
				#>>>
			}
		}
	}

	#>>>
	method _setup_heartbeat {heartbeat_interval session_jmid} { #<<<
		set heartbeat_interval	[expr {$heartbeat_interval - 10}]
		if {$heartbeat_interval < 1} {
			my log warning "Very short heartbeat interval: $heartbeat_interval"
			set heartbeat_interval	1
		}

		set heartbeat_afterid \
				[after [expr {round($heartbeat_interval * 1000)}] \
				[my code _send_heartbeat $heartbeat_interval $session_jmid]]
	}

	#>>>
	method _send_heartbeat {heartbeat_interval session_jmid} { #<<<
		my rsj_req $session_jmid [list _heartbeat] [list apply {
			{msg_data} {
				# Not interested
			}
		}]

		set heartbeat_afterid \
				[after [expr {round($heartbeat_interval * 1000)}] \
				[my code _send_heartbeat $heartbeat_interval $session_jmid]]
	}

	#>>>
}



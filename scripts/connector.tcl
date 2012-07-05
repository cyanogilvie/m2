# vim: ft=tcl foldmarker=<<<,>>> foldmethod=marker ts=4 shiftwidth=4

cflib::pclass create m2::connector {
	superclass sop::signalsource cflib::refcounted

	property lifecycle	"manual"	_lifecycle_changed	;# or "refcounted"

	variable {*}{
		auth
		svc
		pbkey
		dominos
		e_chan
		e_chan_prev_seq
		skey
		cookie
		old_lifecycle
		signals
	}

	constructor {a_auth a_svc} { #<<<
		set auth	$a_auth
		set svc		$a_svc
		set old_lifecycle	""

		if {"::tcl::mathop" ni [namespace path]} {
			namespace path [concat [namespace path] {
				::tcl::mathop
			}]
		}
		if {"::oo::Helpers::cflib" ni [namespace path]} {
			namespace path [concat [namespace path] {
				::oo::Helpers::cflib
			}]
		}

		#set log_cmd	[my code log]	;# Let Refcounted log to us

		array set signals	{}
		array set dominos	{}

		#sop::signal new signals(available) -name "$svc [self] available"
		set signals(available)	[$auth svc_signal $svc]
		sop::signal new signals(connected) -name "$svc [self] connected"
		sop::signal new signals(authenticated) -name "$svc [self] authenticated"
		sop::signal new signals(got_svc_pbkey) -name "$svc [self] got_svc_pbkey"
		sop::gate new signals(connect_ready) -name "$svc [self] connect_ready" \
				-mode "and"
		sop::domino new dominos(need_reconnect) -name "$svc [self] need reconnect"
		$signals(connect_ready) attach_input [$auth signal_ref authenticated]
		$signals(connect_ready) attach_input $signals(got_svc_pbkey)
		$signals(connect_ready) attach_input $signals(available)

		[$auth signal_ref authenticated] attach_output \
				[my code _authenticated_changed]

		$dominos(need_reconnect) attach_output [my code _reconnect]
		$signals(connect_ready) attach_output [my code _connect_ready_changed]
	}

	#>>>
	destructor { #<<<
		[$auth signal_ref authenticated] detach_output \
				[my code _authenticated_changed]
		$dominos(need_reconnect) detach_output [my code _reconnect]
		$signals(connect_ready) detach_output [my code _connect_ready_changed]
		my disconnect
	}

	#>>>

	method req_async {op data cb} { #<<<
		my waitfor authenticated
		$auth rsj_req $e_chan [list $op $data] [my code _req_async_resp $cb]
	}

	#>>>
	method req {op rdata} { #<<<
		my waitfor authenticated

		$auth rsj_req $e_chan [list $op $rdata] [list apply {
			{coro args} {$coro $args}
		} [info coroutine]]

		while {1} {
			lassign [yield] msg
			set data	[dict get $msg data]
			if {[dict get $msg oob_type] eq "profiling"} {
				foreach stamp [dict get $msg oob_data] {
					lassign $stamp usec_abs point station_id
					if {![info exists start_usec]} {
						set start_usec	$usec_abs
					}
					if {![info exists last_usec]} {
						set last_usec	$usec_abs
					}
					set usec_from_start	[- $usec_abs $start_usec]
					set usec_from_last	[- $usec_abs $last_usec]
					set last_usec		$usec_abs
					puts [format "%11.4f %10.4f %7s %s" \
							[/ $usec_from_start 1000.0] \
							[/ $usec_from_last 1000.0] \
							$point \
							$station_id]
				}
			}

			switch -- [dict get $msg type] {
				ack		{return $data}
				nack	{throw [list connector_req_failed $op $data] $data}
				default {
					log warning "Not expecting response type: ([dict get $msg type])"
				}
			}
		}
	}

	#>>>
	method req_jm {op data cb} { #<<<
		my waitfor authenticated
		$auth rsj_req $e_chan [list $op $data] \
				[my code _req_resp [info coroutine] $cb]

		lassign [yield] ok resp

		if {$ok} {
			return $resp
		} else {
			throw [list connector_req_failed $op $resp] $resp
		}
	}

	#>>>
	method chan_req_async {jmid data cb} { #<<<
		my waitfor authenticated
		$auth rsj_req $jmid $data [my code _req_async_resp $cb]
	}

	#>>>
	method chan_req {jmid rdata} { #<<<
		my waitfor authenticated
		$auth rsj_req $jmid $rdata [list apply {
			{coro args} {$coro $args}
		} [info coroutine]]

		while {1} {
			lassign [yield] msg_data
			set data	[dict get $msg_data data]

			switch -- [dict get $msg_data type] {
				ack		{return $data}
				nack	{throw [list chan_req_failed $jmid $rdata $data] $data}
				default {
					log warning "Not expecting response type: ([dict get $msg_data type])"
				}
			}
		}
	}

	#>>>
	method chan_req_jm {jmid data cb} { #<<<
		my waitfor authenticated
		$auth rsj_req $jmid $data [my code _req_resp [info coroutine] $cb]

		lassign [yield] ok resp

		if {$ok} {
			return $resp
		} else {
			throw [list chan_req_failed $jmid $data $resp] $resp
		}
	}

	#>>>
	method jm_disconnect {seq prev_seq} { #<<<
		$auth jm_disconnect $seq $prev_seq
	}

	#>>>
	method disconnect {} { #<<<
		if {[$signals(connected) state]} {
			$signals(authenticated) set_state 0
			$signals(connected) set_state 0
			if {[info exists e_chan]} {
				my jm_disconnect $e_chan $e_chan_prev_seq
				unset e_chan
				unset e_chan_prev_seq
			}
		}
	}

	#>>>
	method unique_id {} { #<<<
		$auth unique_id
	}

	#>>>
	method auth {} { #<<<
		return $auth
	}

	#>>>

	method _lifecycle_changed {} { #<<<
		if {
			$lifecycle eq "refcounted" &&
			$old_lifecycle ne "refcounted"
		} {
			my autoscoperef
			log notice "Switching to refcounted mode.  current refcount: ([my refcount])"
		} elseif {
			$lifecycle ne "refcounted" &&
			$old_lifecycle eq "refcounted"
		} {
			log warning "There is really no going back from a refcounted mode.  You'd better have registered a reference to me or I won't be around much longer"
		}
		set old_lifecycle	$lifecycle
	}

	#>>>
	method _connect_ready_changed {newstate} { #<<<
		if {$newstate} {
			$dominos(need_reconnect) tip
		}
	}

	#>>>
	method _reconnect {} { #<<<
		if {[$signals(connected) state]} {
			my disconnect
		}
		set skey	[$auth generate_key]
		set cookie	[crypto::blowfish::csprng 8]
		set n		[dict get $pbkey n]
		set e		[dict get $pbkey e]
		set msg		[crypto::rsa::RSAES-OAEP-Encrypt $n $e $skey {} $crypto::rsa::sha1 $crypto::rsa::MGF]
		set ks		[crypto::blowfish::init_key $skey]
		set iv		[crypto::blowfish::csprng 8]
		set tail	[crypto::blowfish::encrypt_cbc $ks [encoding convertto utf-8 [list $cookie [$auth fqun] $iv]] $iv]

		$auth req $svc "setup [list $msg $tail $iv]" [my code _resp]
	}

	#>>>
	method _resp {msg_data} { #<<<
		switch -- [dict get $msg_data type] {
			ack { #<<<
				if {![info exists e_chan]} {
					log error "Incomplete encrypted channel setup: got ack but no pr_jm"
					return
				}
				$signals(connected) set_state 1
				set svc_cookie	[$auth decrypt_with_session_prkey [dict get $msg_data data]]

				set seq		[$auth rsj_req $e_chan $svc_cookie [my code _auth_resp]]
				#>>>
			}
			nack { #<<<
				if {[info exists e_chan]} {
					unset e_chan
				}
				if {[info exists e_chan_prev_seq]} {
					unset e_chan_prev_seq
				}
				log error "Got nacked: ([dict get $msg_data data])"
				#>>>
			}
			pr_jm { #<<<
				if {![info exists e_chan]} {
					set pdata	[$auth decrypt $skey [dict get $msg_data data]]
					if {$pdata eq $cookie} {
						set e_chan			[dict get $msg_data seq]
						set e_chan_prev_seq	[dict get $msg_data prev_seq]
						$auth register_jm_key $e_chan $skey
					} else {
						log error "did not get correct response from component: expecting: ([$auth mungekey $cookie]) got: ([$auth mungekey $pdata]), decrypted with ([$auth mungekey $skey])\nencrypted data: ([$auth mungekey [dict get $msg_data data]])" -suppress data
					}
				}
				#>>>
			}
			jm_can { #<<<
				if {[info exists e_chan] && $e_chan == [dict get $msg_data seq]} {
					$signals(connected) set_state 0
					$signals(authenticated) set_state 0
					unset e_chan
					unset e_chan_prev_seq
				}
				#>>>
			}
			default { #<<<
				log warning "Not expecting response type ([dict get $msg_data type])"
				#>>>
			}
		}
	}

	#>>>
	method _auth_resp {msg_data} { #<<<
		switch -- [dict get $msg_data type] {
			ack {
				$signals(authenticated) set_state 1
			}

			nack {
				log error "got nack: ([dict get $msg_data data])"
			}

			default {
				log error "unexpected type: ([dict get $msg_data type])"
			}
		}
	}

	#>>>
	method _req_async_resp {cb msg_data} { #<<<
		try {
			uplevel #0 $cb [list $msg_data]
		} on error {errmsg options} {
			log error "error invoking cb ($cb): $errmsg\n[dict get $options -errorinfo]"
		}
	}

	#>>>
	method _req_resp {coro cb msg_data} { #<<<
		switch -- [dict get $msg_data type] {
			ack {
				after idle [list $coro [list 1 [dict get $msg_data data]]]
			}

			nack {
				after idle [list $coro [list 0 [dict get $msg_data data]]]
			}

			jm_req -
			pr_jm -
			jm -
			jm_can {
				if {$cb ne {}} {
					try {
						coroutine coro_resp_[incr ::coro_seq] {*}$cb $msg_data
					} on error {errmsg options} {
						if {[string match "*invalid command name \"::item*\"" $errmsg]} {
							log error "error invoking cb ($cb): item object died too soon?" -suppress data
						} else {
							log error "error invoking cb ($cb): $errmsg\n[dict get $options -errorinfo]" -suppress data
						}
					}
				} else {
					log warning "got $type, but no cb set." -suppress data
				}
			}

			default {
				log error "unexpected type: ([dict get $msg_data type])" -suppress data
			}
		}
	}

	#>>>
	method _authenticated_changed {newstate} { #<<<
		if {$newstate} {
			auth get_svc_pbkey_async $svc [code _get_svc_pbkey_resp]
		} else {
			$signals(got_svc_pbkey) set_state 0
			if {[info exists pbkey]} {unset pbkey}
		}
	}

	#>>>
	method _get_svc_pbkey_resp msg { #<<<
		switch -exact -- [dict get $msg type] {
			ack {
				set pbkey_asc	[dict get $msg data]

				set pbkey		[crypto::rsa::load_asn1_pubkey_from_value $pbkey_asc]
				$signals(got_svc_pbkey) set_state 1
			}

			nack {
				log error "error fetching public key for ($svc):\n[dict get $msg data]"
			}
		}
	}

	#>>>
}



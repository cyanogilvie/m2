# vim: ft=tcl foldmarker=<<<,>>> foldmethod=marker ts=4 shiftwidth=4

cflib::pclass create m2::connector {
	superclass sop::signalsource cflib::baselog cflib::refcounted

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

		my log debug [self]

		#set log_cmd	[my code log]	;# Let Refcounted log to us

		array set signals	{}
		array set dominos	{}

		sop::signal new signals(available) -name "$svc [self] available"
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

		$auth register_handler svc_avail_changed [my code _svc_avail_changed]
		my _svc_avail_changed		;# Initialize the state
	}

	#>>>
	destructor { #<<<
		my log debug "[self] svc: [expr {[info exists svc] ? $svc : {not set}}]"
		[$auth signal_ref authenticated] detach_output \
				[my code _authenticated_changed]
		$auth deregister_handler svc_avail_changed [my code _svc_avail_changed]
		$dominos(need_reconnect) detach_output [my code _reconnect]
		$signals(connect_ready) detach_output [my code _connect_ready_changed]
		my disconnect
		my log debug "[self] done"
	}

	#>>>

	method req_async {op data cb} { #<<<
		my waitfor authenticated
		$auth rsj_req $e_chan [list $op $data] [my code _req_async_resp $cb]
	}

	#>>>
	method req {op rdata} { #<<<
		my log debug
		my waitfor authenticated

		$auth rsj_req $e_chan [list $op $rdata] [list apply {
			{coro args} {$coro $args}
		} [info coroutine]]

		while {1} {
			lassign [yield] msg_data
			dict with msg_data {}

			switch -- $type {
				ack		{return $data}
				nack	{throw [list connector_req_failed $op $data] $data}
				default {
					my log warning "Not expecting response type: ($type)"
				}
			}
		}
	}

	#>>>
	method req_jm {op data cb} { #<<<
		my log debug
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
		my log debug
		my waitfor authenticated
		$auth rsj_req $jmid $data [my code _req_async_resp $cb]
	}

	#>>>
	method chan_req {jmid rdata} { #<<<
		my log debug
		my waitfor authenticated
		$auth rsj_req $jmid $rdata [list apply {
			{coro args} {$coro $args}
		} [info coroutine]]

		while {1} {
			lassign [yield] msg_data
			dict with msg_data {}

			switch -- $type {
				ack		{return $data}
				nack	{throw [list chan_req_failed $jmid $rdata $data] $data}
				default {
					my log warning "Not expecting response type: ($type)"
				}
			}
		}
	}

	#>>>
	method chan_req_jm {jmid data cb} { #<<<
		my log debug
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
		my log debug
		$auth jm_disconnect $seq $prev_seq
	}

	#>>>
	method disconnect {} { #<<<
		my log debug
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
			my log notice "Switching to refcounted mode.  current refcount: ([my refcount])"
		} elseif {
			$lifecycle ne "refcounted" &&
			$old_lifecycle eq "refcounted"
		} {
			my log warning "There is really no going back from a refcounted mode.  You'd better have registered a reference to me or I won't be around much longer"
		}
		set old_lifecycle	$lifecycle
	}

	#>>>
	method _resp {msg_data} { #<<<
		dict with msg_data {}

		switch -- $type {
			ack { #<<<
				if {![info exists e_chan]} {
					my log error "Incomplete encrypted channel setup: got ack but no pr_jm"
					return
				}
				$signals(connected) set_state 1
				set svc_cookie	[$auth decrypt_with_session_prkey $data]
				
				my log debug "sending proof of identity" -suppress data
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
				my log error "Got nacked: ($data)"
				#>>>
			}
			pr_jm { #<<<
				if {![info exists e_chan]} {
					set pdata	[$auth decrypt $skey $data]
					if {$pdata eq $cookie} {
						set e_chan			$seq
						set e_chan_prev_seq	$prev_seq
						my log debug "got matching cookie, storing e_chan ($e_chan) and registering it with auth::register_jm_key using ([$auth mungekey $skey])" -suppress data
						$auth register_jm_key $e_chan $skey
					} else {
						my log error "did not get correct response from component: expecting: ([$auth mungekey $cookie]) got: ([$auth mungekey $pdata]), decrypted with ([$auth mungekey $skey])\nencrypted data: ([$auth mungekey $data])" -suppress data
					}
				}
				#>>>
			}
			jm_can { #<<<
				if {[info exists e_chan] && $e_chan == $seq} {
					$signals(connected) set_state 0
					$signals(authenticated) set_state 0
					unset e_chan
					unset e_chan_prev_seq
				}
				#>>>
			}
			default { #<<<
				my log warning "Not expecting response type ($type)"
				#>>>
			}
		}
	}

	#>>>
	method _connect_ready_changed {newstate} { #<<<
		if {$newstate} {
			my log debug "setting reconnect in motion"
			$dominos(need_reconnect) tip
		} else {
			my log debug
		}
	}

	#>>>
	method _svc_avail_changed {} { #<<<
		my log debug [self]
		set is_avail	[$auth svc_avail $svc]
		my log notice "$svc available: ($is_avail)"
		$signals(available) set_state $is_avail
	}

	#>>>
	method _reconnect {} { #<<<
		my log debug "reconnecting to $svc"
		if {[$signals(connected) state]} {
			my disconnect
		}
		set skey	[$auth generate_key]
		set cookie	[$auth generate_key 8]
		set msg		[crypto::rsa_public_encrypt $pbkey $skey]
		set tail	[crypto::encrypt bf_cbc $skey [list $cookie [$auth fqun]]]

		$auth req $svc "setup [list $msg $tail]" [my code _resp]
	}

	#>>>
	method _auth_resp {msg_data} { #<<<
		dict with msg_data {}

		my log debug
		switch -- $type {
			ack {
				my log debug "got ack: ($data)"
				$signals(authenticated) set_state 1
			}

			nack {
				my log error "got nack: ($data)"
			}

			default {
				my log error "unexpected type: ($type)"
			}
		}
	}

	#>>>
	method _req_async_resp {cb msg_data} { #<<<
		dict with msg_data {}

		my log debug
		try {
			uplevel #0 $cb [list $msg_data]
		} on error {errmsg options} {
			my log error "error invoking cb ($cb): $errmsg\n$::errorInfo"
		}
	}

	#>>>
	method _req_resp {coro cb msg_data} { #<<<
		dict with msg_data {}

		my log debug
		switch -- $type {
			ack {
				after idle [list $coro [list 1 $data]]
			}

			nack {
				after idle [list $coro [list 0 $data]]
			}

			jm_req -
			pr_jm -
			jm -
			jm_can {
				if {$cb ne {}} {
					try {
						uplevel $cb [list $msg_data]
					} on error {errmsg options} {
						if {[string match "*invalid command name \"::item*\"" $errmsg]} {
							my log error "error invoking cb ($cb): item object died too soon?" -suppress data
						} else {
							my log error "error invoking cb ($cb): $errmsg\n$::errorInfo" -suppress data
						}
					}
				} else {
					my log warning "got $type, but no cb set." -suppress data
				}
			}

			default {
				my log error "unexpected type: ($type)" -suppress data
			}
		}
	}

	#>>>
	method _authenticated_changed {newstate} { #<<<
		my log debug
		if {$newstate} {
			try {
				my log debug "requesting public key for ($svc) ..."
				#set pbkey	[crypto::rsa_load_public_key [$auth get_svc_pbkey $svc]]
				set pbkey_asc	[$auth get_svc_pbkey $svc]
				my log debug "got public key ascii format for ($svc), loading into key ..."
				set pbkey		[crypto::rsa_load_public_key $pbkey_asc]
				my log debug "got public key for ($svc)"
			} on error {errmsg options} {
				my log error "error fetching public key for ($svc):\n[dict get $options -errorinfo]"
			} else {
				$signals(got_svc_pbkey) set_state 1
			}
		} else {
			$signals(got_svc_pbkey) set_state 0
			if {[info exists pbkey]} {unset pbkey}
		}
	}

	#>>>
}



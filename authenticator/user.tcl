# vim: foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create User {
	variable {*}{
		fqun
		userchans_obj
		session_jmid
		heartbeat_afterid
	}

	constructor {name} { #<<<
		if {[self next] ne {}} next

		set heartbeat_afterid	""

		set fqun					[users make_fqun $name]
		proc log {lvl msg args} [format {
			tailcall ::log $lvl "\"%s\" $msg" {*}$args
		} [list $fqun]]

		set userchans_obj	[my _get_userchans_obj]
	}

	#>>>
	destructor { #<<<
		after cancel $heartbeat_afterid; set heartbeat_afterid	""

		if {[info exists userchans_obj]} {
			if {[info object isa object $userchans_obj]} {
				set remaining		[$userchans_obj remove_session [self]]
				if {$remaining == 0} {
					if {
						[info exists fqun] &&
						[dict exists $::userchans $fqun]
					} {
						log notice "Clearing \"$fqun\" out of the list of userchans"
						dict unset ::userchans $fqun

						# This is iffy - it should die from the chan_cb
						# cancelled, but it'll never get it if we're here
						# because our far side missed a heartbeat, so we force
						# the issue
						$userchans_obj kick
						userkeys kick $fqun
					}
				}
			} else {
				if {
					[info exists fqun] &&
					[dict exists $::userchans $fqun]
				} {
					log notice "Clearing \"$fqun\" out of the list of userchans"
					dict unset ::userchans $fqun
				}
			}
			unset userchans_obj
		} else {
			log warning "No associated userchans_obj"
		}
		if {[info exists session_jmid]} {
			m2 chans deregister_chan $session_jmid
			log notice "Cancelling session_jmid: ($session_jmid)"
			m2 jm_can $session_jmid ""
			unset session_jmid
		}

		if {[self next] ne {}} next
	}

	#>>>

	method type {} { #<<<
		my get type
	}

	#>>>
	method get {key args} { #<<<
		$userchans_obj get $key {*}$args
	}

	#>>>
	method login_person {seq password} { #<<<
		# Keep in sync with User::login_svc
		$userchans_obj set_dat type "user"
		$userchans_obj check_login_person $seq $password
		$userchans_obj add_session [self] $seq

		set session_jmid	[m2 unique_id]
		m2 chans register_chan $session_jmid \
				[namespace code {my _session_chan_cb}]
		m2 pr_jm $session_jmid $seq \
				[list session_chan [cfg get heartbeat_interval]]
		set heartbeat_afterid	[after [expr {
			round([cfg get heartbeat_interval] * 1000)
		}] [namespace code {my _flatline}]]
	}

	#>>>
	method login_svc {seq svc cookie_idx e_cookie} { #<<<
		# Keep in sync with User::login_person
		$userchans_obj set_dat type "svc"

		set svc_pbkey	[svckeys get_pbkey $svc]
		set n			[dict get $svc_pbkey n]
		set e			[dict get $svc_pbkey e]
		set d_e_cookie	[crypto::rsa::RSAES-OAEP-Verify $n $e $e_cookie {} $crypto::rsa::sha1 $crypto::rsa::MGF]

		set pending		[users pending_cookie $cookie_idx]
		lassign $pending cookie pend_svc
		users expire_cookie $cookie_idx

		if {
			$d_e_cookie ne $cookie ||
			$svc ne $pend_svc
		} {
			throw {bad_cookie} "cookie is bad"
		}

		$userchans_obj add_session [self] $seq

		set session_jmid	[m2 unique_id]
		m2 chans register_chan $session_jmid \
				[namespace code {my _session_chan_cb}]
		m2 pr_jm $session_jmid $seq \
				[list session_chan [cfg get heartbeat_interval]]
	}

	#>>>

	method _logout {} { #<<<
		log notice "User session logoff or disconnect"
		my destroy
	}

	#>>>
	method _get_userchans_obj {} { #<<<
		if {![dict exists $::userchans $fqun]} {
			dict set ::userchans $fqun [Userchans new $fqun]
		}

		dict get $::userchans $fqun
	}

	#>>>
	method _session_chan_cb {op data} { #<<<
		switch -- $op {
			cancelled {
				if {[info exists session_jmid]} {
					unset session_jmid
				}
				my _logout
			}

			req {
				lassign $data seq prev_seq msg
				set rest	[lassign $msg op]

				my _reset_heartbeat

				if {$op eq "_heartbeat"} {
					m2 ack $seq ""
					return
				}

				m2 nack $seq "No requests allowed on session channel"
			}

			default {
				log error "Unknown op: ($op)"
			}
		}
	}

	#>>>
	method _reset_heartbeat {} { #<<<
		after cancel $heartbeat_afterid; set heartbeat_afterid	""
		set heartbeat_afterid	[after [expr {
			round([cfg get heartbeat_interval] * 1000)
		}] [namespace code {my _flatline}]]
	}

	#>>>
	method _flatline {} { #<<<
		log warning "User session $fqun missed heartbeat.  Declaring dead"
		my destroy
	}

	#>>>
}



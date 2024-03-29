# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create m2::api2 {
	superclass m2::api
	#superclass m2::threaded_api

	method _properties {} {
		format {%s
			variable oob_type		none
			variable threaded_io	0
		} [next]
	}

	variable {*}{
		e_pending
		sent_key
		svc_handlers
		pending
		jm
		jm_prev_seq
		jm_keys
		ack_pend
		session_keys
		pending_keys
		chans
		outstanding_reqs
	}

	constructor args { #<<<
		my _init_props $args

		set e_pending			[dict create]
		set sent_key			[dict create]
		set svc_handlers		[dict create]
		set pending				[dict create]
		set jm					[dict create]
		set jm_prev_seq			[dict create]
		set jm_keys				[dict create]
		set ack_pend			[dict create]
		set session_keys		[dict create]
		set pending_keys		[dict create]
		set chans				[dict create]
		set outstanding_reqs	[dict create]

		if {[prop get threaded_io]} {
			oo::objdefine [self] mixin m2::threaded_api
		}

		next

		if {"::tcl::mathop" ni [namespace path]} {
			namespace path [concat [namespace path] {
				::tcl::mathop
			}]
		}
	}

	#>>>

	method _incoming msg { #<<<
		set m_seq		[dict get $msg seq]
		set m_prev_seq	[dict get $msg prev_seq]

		# Decrypt any encrypted data, store jm_keys for new jm channels <<<
		switch -- [dict get $msg type] {
			ack { #<<<
				dict unset ack_pend $m_prev_seq
				if {[dict exists $pending_keys $m_prev_seq]} {
					#log debug "Decrypting ack with [my mungekey [dict get $pending_keys $m_prev_seq]]" -suppress {data}
					dict set msg data [my decrypt [dict get $pending_keys $m_prev_seq] [dict get $msg data]]
				}
				dict unset pending_keys $m_prev_seq
				#>>>
			}

			nack { #<<<
				dict unset ack_pend $m_prev_seq
				dict unset pending_keys $m_prev_seq
				#>>>
			}

			pr_jm { #<<<
				dict incr jm $m_prev_seq 1

				if {
					![dict exists $jm_prev_seq $m_seq] ||
					$m_prev_seq ni [dict get $jm_prev_seq $m_seq]
				} {
					dict lappend jm_prev_seq $m_seq	$m_prev_seq
				}

				if {[dict exists $pending_keys $m_prev_seq]} {
					dict set msg data [my decrypt [dict get $pending_keys $m_prev_seq] [dict get $msg data]]
					if {![dict exists $jm_keys $m_seq]} {
						?? {
							if {[string length [dict get $msg data]] != 56} {
								log warning "pr_jm: warning strange looking key: ([dict get $msg data])"
							}
						}
						#log debug "pr_jm: registering key for ($m_seq): ([my mungekey [dict get $msg data]])"
						my register_jm_key $m_seq	[dict get $msg data]
						return
					} else {
						if {[string length [dict get $msg data]] == 56} {
							if {[dict get $msg data] eq [dict get $jm_keys $m_seq]} {
								log error "pr_jm: jm($m_seq) got channel key setup twice!"
								return
							} else {
								log warning "pr_jm: got what may be another key on this jm ($m_seq), that differs from the first"
							}
						} else {
							#log debug "pr_jm: already have key for ($m_seq): ([my mungekey [dict get $jm_keys $m_seq]])"
						}
					}
				} else {
					#log debug "pr_jm: no pending_keys($m_prev_seq)"
				}
				#>>>
			}

			jm { #<<<
				if {[dict exists $jm_keys $m_seq]} {
					dict set msg data [my decrypt [dict get $jm_keys $m_seq] [dict get $msg data]]
				}
				#>>>
			}

			jm_req { #<<<
				#log debug "Got jm_req: seq: ($m_seq) prev_seq: ($m_prev_seq)" -suppress {data}
				if {[dict exists $jm_keys $m_prev_seq]} {
					#log debug "Decrypting data with [my mungekey [dict get $jm_keys $m_prev_seq]]" -suppress data
					dict set msg data [my decrypt [dict get $jm_keys $m_prev_seq] [dict get $msg data]]
				}
				#>>>
			}
		}
		# Decrypt any encrypted data, store jm_keys for new jm channels >>>

		switch -- [dict get $msg type] {
			req { #<<<
				if {[dict exists $svc_handlers [dict get $msg svc]]} {
					# Add profiling stamp if requested <<<
					if {[dict get $msg oob_type] eq "profiling"} {
						dict set msg oob_data [my _add_profile_stamp "req_in" \
								[dict get $msg oob_data]]
					}
					# Add profiling stamp if requested >>>
					dict set outstanding_reqs $m_seq	$msg
					try {
						coroutine coro_req_[incr ::coro_seq] \
								{*}[dict get $svc_handlers [dict get $msg svc]] \
								$m_seq [dict get $msg data]
					} on error {errmsg options} {
						log error "req: error handling svc: ([dict get $msg svc]):$errmsg\n[dict get $options -errorinfo]"
						my nack $m_seq "Internal error"
					}
				} else {
					log error "req: no handlers for svc: ([dict get $msg svc])"
					my nack $m_seq "No handlers for [dict get $msg svc])"
				}
				#>>>
			}

			jm_can { #<<<
				dict unset jm_prev_seq	$m_seq
				dict unset jm_keys		$m_seq
				foreach prev_seq $m_prev_seq {
					dict incr jm $prev_seq	-1
					if {[dict exists $pending $prev_seq]} {
						set cb		[dict get $pending $prev_seq]
						if {$cb ne {}} {
							try {
								coroutine coro_jm_can_[incr ::coro_seq] \
										{*}$cb $msg
							} on error {errmsg options} {
								log error "API2::incoming/jm_can: error invoking handler: ($cb)\n[dict get $options -errorinfo]"
								log error "jm_can: error invoking handler: $errmsg\n[dict get $options -errorinfo]"
							}
						}
					} else {
						#log debug "API2::incoming/jm_can: unknown jm: prev_seq: ($prev_seq), seq: ($m_seq)"
					}
					if {[dict get $jm $prev_seq] <= 0} {
						dict unset pending $prev_seq
						dict unset jm $prev_seq
					}
				}
				#>>>
			}

			jm_disconnect { #<<<
				try {
					#log trivia "API2::incoming: got jm_disconnect:\nseq: ($m_seq)\nprev_seq: ($m_prev_seq)"
					my chans cancel $m_seq
				} on error {errmsg options} {
					log error "error processing jm_disconnect: $errmsg\n[dict get $options -errorinfo]"
				}
				#>>>
			}

			rsj_req { #<<<
				try {
					# Add profiling stamp if requested <<<
					if {[dict get $msg oob_type] eq "profiling"} {
						dict set msg oob_data [my _add_profile_stamp "req_in" \
								[dict get $msg oob_data]]
					}
					# Add profiling stamp if requested >>>
					dict set outstanding_reqs $m_seq	$msg
					#log trivia "API2::incoming: got [dict get $msg svc]: ([dict get $msg seq]) ([dict get $msg prev_seq]) ([dict get $msg data])"
					#log debug "API2::incoming: channel request"
					if {[my crypto registered_chan $m_prev_seq]} {
						dict set msg data	[my crypto decrypt $m_prev_seq [dict get $msg data]] 
						my register_pending_encrypted $m_seq $m_prev_seq
					}
					my chans chanreq $m_seq $m_prev_seq [dict get $msg data]
				} on error {errmsg options} {
					log error "error processing [dict get $msg svc] rsj_req: $errmsg\n[dict get $options -errorinfo]"
					my nack $m_seq "internal error"
				}
				#>>>
			}

			jm_req { #<<<
				try {
					dict set outstanding_reqs $m_seq	$msg
					# FIXME: this leaks session_keys (not unset on ack/nack)
					if {[dict exists $jm_keys $m_prev_seq]} {
						dict set session_keys $m_prev_seq	[dict get $jm_keys $m_prev_seq]
						my register_pending_encrypted $m_seq $m_prev_seq
					}
					if {![dict exists $jm_prev_seq $m_prev_seq]} {
						error "Cannot find jm_prev_seq($m_prev_seq)"
					}
					set jm_prev	[dict get $jm_prev_seq $m_prev_seq]
					if {
						[dict exists $pending $jm_prev]
						&& [dict get $pending $jm_prev] ne ""
					} {
						set cb	[dict get $pending $jm_prev]
						coroutine coro_jm_req_[incr ::coro_seq] \
								{*}$cb $msg
					} else {
						#log debug "no handler for seq: ($m_seq), prev_seq: ($m_prev_seq)"
					}
				} on error {errmsg options} {
					log error "error processing jm_req: $errmsg\n[dict get $options -errorinfo]"
					if {![my answered $m_seq]} {
						my nack $m_seq "internal error"
					}
				}
				#>>>
			}

			ack -
			nack -
			jm -
			pr_jm { #<<<
				# m(prev_seq) is a list of previous sequences for junkmails
				# (there may be more than one of our requests that were
				# subscribed to this junkmail)
				foreach prev_seq $m_prev_seq {
					if {[dict exists $pending $prev_seq]} {
						set cb		[dict get $pending $prev_seq]
						if {$cb ne {}} {
							try {
								#log debug "API2::incoming/([dict get $msg type]): invoking callback ($cb) for seq: ($m_seq) prev_seq: ($m_prev_seq)"
								#log debug "API2::incoming/([dict get $msg type]): invoking callback for seq: ($m_seq) prev_seq: ($m_prev_seq)"
								# Add profiling stamp if requested <<<
								if {[dict get $msg oob_type] eq "profiling"} {
									dict set msg oob_data [my _add_profile_stamp \
											"[dict get $msg type]_in" \
											[dict get $msg oob_data]]
								}
								# Add profiling stamp if requested >>>
								coroutine coro_resp_[incr ::coro_seq] \
										{*}$cb $msg
							} on error {errmsg options} {
								#log debug "API2::incoming/([dict get $msg type]): error invoking callback ($cb): $errmsg\n[dict get $options -errorinfo]" 
								log error "error invoking callback: $errmsg\n[dict get $options -errorinfo]" 
							}
						} else {
							#log debug "no handler for seq: ($m_seq), prev_seq: ($prev_seq)"
						}
					} else {
						log warning "API2::incoming/([dict get $msg type]): unexpected response: [dict get $msg svc] [dict get $msg type] prev_seq: ($prev_seq) seq: ($m_seq)"
					}
					if {![dict exists $jm $prev_seq]} {
						#log debug "API2::incoming/([dict get $msg type]): lost jm($prev_seq):\n[m2::msg::display $msg]"
						return
					}
					if {
						[dict get $jm $prev_seq] <= 0 &&
						![dict exists $ack_pend $prev_seq]
					} {
						dict unset pending	$prev_seq
						dict unset jm		$prev_seq
					}
				}
				#>>>
			}

			svc_avail -
			svc_revoke	{}

			default {
				log warning "API2::incoming/default: unhandled type: ([dict get $msg type])"
			}
		}
		#log debug "API2::incoming: leaving incoming"
	}

	#>>>
	method ack {prev_seq data} { #<<<
		#log debug "request pending? [dict exists $outstanding_reqs $prev_seq]" -suppress {data}
		if {![dict exists $outstanding_reqs $prev_seq]} {
			log warning "$prev_seq doesn't refer to an open request.  Perhaps it was already answered?"
			return
		}
		if {[dict exists $e_pending $prev_seq]} {
			#log debug "encrypting ack with [my mungekey [dict get $session_keys [dict get $e_pending $prev_seq]]] from $prev_seq" -suppress {data}
			#log debug "== encrypting ack with [binary encode base64 [dict get $session_keys [dict get $e_pending $prev_seq]]] from $prev_seq" -suppress {data}
			set e_data	[my crypto encrypt [dict get $e_pending $prev_seq] $data]
		} else {
			#log debug "== No key registered for prev_seq: ($prev_seq) [binary encode base64 $data]"
			set e_data	$data
		}
		set msg		[m2::msg::new [list \
				svc			"" \
				type		ack \
				seq			[my unique_id] \
				prev_seq	$prev_seq \
				data		$e_data \
		]]

		# decref the outstanding req, and process any oob messages <<<
		if {[dict exists $outstanding_reqs $prev_seq]} {
			set origmsg	[dict get $outstanding_reqs $prev_seq]
			switch -- [dict get $origmsg oob_type] {
				1 {}
				profiling {
					set profile_so_far	[my _add_profile_stamp "ack_out" \
							[dict get $origmsg oob_data]]
					dict set msg oob_type profiling
					dict set msg oob_data $profile_so_far
				}
			}
		}
		# decref the outstanding req, and process any oob messages >>>

		dict unset outstanding_reqs $prev_seq
		dict unset e_pending $prev_seq
		dict unset sent_key $prev_seq,*

		my send $msg
	}

	#>>>
	method nack {prev_seq data} { #<<<
		#log debug "request pending? [dict exists $outstanding_reqs $prev_seq]" -suppress data
		if {![dict exists $outstanding_reqs $prev_seq]} {
			log warning "$prev_seq doesn't refer to an open request.  Perhaps it was already answered?"
			return
		}
		set msg		[m2::msg::new [list \
				svc			"" \
				type		nack \
				seq			[my unique_id] \
				prev_seq	$prev_seq \
				data		$data \
		]]

		# decref the outstanding req, and process any oob messages <<<
		if {[dict exists $outstanding_reqs $prev_seq]} {
			set origmsg	[dict get $outstanding_reqs $prev_seq]
			switch -- [dict get $origmsg oob_type] {
				1 {}
				profiling {
					set profile_so_far	[my _add_profile_stamp "nack_out" \
							[dict get $origmsg oob_data]]
					dict set msg oob_type profiling
					dict set msg oob_data $profile_so_far
				}
			}
		}
		# decref the outstanding req, and process any oob messages >>>

		dict unset outstanding_reqs $prev_seq
		dict unset e_pending $prev_seq
		dict unset sent_key $prev_seq,*

		my send $msg
	}

	#>>>
	method jm {seq data} { #<<<
		if {[my crypto registered_chan $seq]} {
			set e_data	[my crypto encrypt $seq $data]
		} else {
			set e_data	$data
		}
		my send [m2::msg::new [list \
				svc			"" \
				type		jm \
				seq			$seq \
				prev_seq	0 \
				data		$e_data \
		]]
	}

	#>>>
	method pr_jm {seq prev_seq data} { #<<<
		if {[dict exists $e_pending $prev_seq]} {
			set e_data	[my crypto encrypt [dict get $e_pending $prev_seq] $data]
			# Send jm key if applicable <<<
			if {![dict exists $sent_key $prev_seq,$seq]} {
				set key     	[my crypto register_or_get_chan $seq]
				#log debug "sending chan key: ([my mungekey $key])"
				my send [m2::msg::new [list \
						svc			"" \
						type		pr_jm \
						seq			$seq \
						prev_seq	$prev_seq \
						data		[my crypto encrypt [dict get $e_pending $prev_seq] $key] \
				]]
				dict set sent_key $prev_seq,$seq	1
			}
			# Send jm key if applicable >>>
		} else {
			if {[my crypto registered_chan $seq]} {
				set e_data	[my crypto encrypt $seq $data]
			} else {
				set e_data	$data
			}
		}
		my send [m2::msg::new [list \
				svc			"" \
				type		pr_jm \
				seq			$seq \
				prev_seq	$prev_seq \
				data		$e_data \
		]]
	}

	#>>>
	method jm_can {seq data} { #<<<
		my send [m2::msg::new [list \
				svc			"" \
				type		jm_can \
				seq			$seq \
				prev_seq	0 \
				data		$data \
		]]
	}

	#>>>
	method req {svc data cb {withkey ""}} { #<<<
		set seq		[my unique_id]
		if {$withkey ne ""} {
			set data	[my encrypt $withkey $data]
		}
		set msg		[m2::msg::new [list \
				svc			$svc \
				type		req \
				seq			$seq \
				data		$data \
		]]
		if {[prop get oob_type] eq "profiling"} {
			set profile_so_far	[my _add_profile_stamp "req_out" {}]
			dict set msg oob_type	"profiling"
			dict set msg oob_data	$profile_so_far
		}
		my send $msg

		dict set pending $seq		$cb
		dict set ack_pend $seq		1
		dict set jm $seq			0

		return $seq
	}

	#>>>
	method rsj_req {jm_seq data cb} { #<<<
		set seq		[my unique_id]
		#log debug "key: ([expr {[dict exists $jm_keys $jm_seq] ? [my mungekey [dict get $jm_keys $jm_seq]] : "none"}])"
		if {[dict exists $jm_keys $jm_seq]} {
			#log debug "([my mungekey [dict get $jm_keys $jm_seq]])"
			dict set pending_keys $seq	[dict get $jm_keys $jm_seq]
			set e_data		[my encrypt [dict get $jm_keys $jm_seq] $data]
		} else {
			set e_data		$data
		}

		set msg	[m2::msg::new [list \
				svc			"" \
				type		rsj_req \
				seq			$seq \
				prev_seq	$jm_seq \
				data		$e_data \
		]]
		if {[prop get oob_type] eq "profiling"} {
			set profile_so_far	[my _add_profile_stamp "req_out" {}]
			dict set msg oob_type	"profiling"
			dict set msg oob_data	$profile_so_far
		}
		my send $msg

		dict set pending $seq		$cb
		dict set ack_pend $seq		1
		dict set jm $seq			0

		return $seq
	}

	#>>>
	method jm_req {jm_seq data cb} { #<<<
		set seq		[my unique_id]
		if {[my crypto registered_chan $jm_seq]} {
			set e_data	[my crypto encrypt $jm_seq $data]
			#log debug "Encrypted data with key [my mungekey [dict get $session_keys $jm_seq]]"
			dict set pending_keys $seq	[dict get $session_keys $jm_seq]
		} else {
			set e_data	$data
		}
		my send [m2::msg::new [list \
				svc			"" \
				type		jm_req \
				seq			$seq \
				prev_seq	$jm_seq \
				data		$e_data \
		]]

		dict set pending $seq		$cb
		dict set ack_pend $seq		1
		dict set jm $seq			0

		return $seq
	}

	#>>>
	method jm_disconnect {jm_seq {prev_seq ""}} { #<<<
		# TODO: handle case where jm_prev_seq($jm_seq) is a list of > 1 element
		#log debug "key: ([expr {[dict exists $jm_keys $jm_seq] ? [my mungekey [dict get $jm_keys $jm_seq]] : "none"}])"
		if {$prev_seq eq ""} {
			log warning "Called without a prev_seq.  Not good"
		}
		if {![dict exists $jm_prev_seq $jm_seq]} {
			log warning "No jm found to disconnect"
			return
		}
		my send [m2::msg::new [list \
				type		jm_disconnect \
				svc			"" \
				seq			$jm_seq \
				prev_seq	[expr {($prev_seq == "") ? 0 : $prev_seq}] \
		]]

		dict unset jm_keys		$jm_seq
		if {[dict exists $jm_prev_seq $jm_seq]} {
			if {$prev_seq ne ""} {
				set idx		[lsearch [dict get $jm_prev_seq $jm_seq] $prev_seq]
				if {$idx == -1} {
					log warning "supplied prev_seq ($prev_seq) is invalid"
				} else {
					dict incr jm $prev_seq	-1
					if {[dict get $jm $prev_seq] <= 0} {
						dict unset pending $prev_seq
						dict unset jm $prev_seq
					} else {
						#puts "after jm_disconnect: jm($prev_seq): [dict get $jm $prev_seq]"
					}
					dict set jm_prev_seq $jm_seq	[lreplace [dict get $jm_prev_seq $jm_seq] $idx $idx]
					if {[llength [dict get $jm_prev_seq $jm_seq]] == 0} {
						dict unset jm_prev_seq	$jm_seq
					}
				}
			} else {
				if {[llength [dict get $jm_prev_seq $jm_seq]] > 1} {
					log error "Cancelling all channels because prev_seq is unspecified"
				}
				foreach jm_prev [dict get $jm_prev_seq $jm_seq] {
					log warning "removing pending($jm_prev): exists? [dict exists $pending $jm_prev]: \"[expr {[dict exists $pending $jm_prev]?[dict get $pending $jm_prev]:""}]\""
					dict incr jm $jm_prev	-1
					if {[dict get $jm $jm_prev] <= 0} {
						dict unset pending $jm_prev
						dict unset jm $jm_prev
					}
				}
				dict unset jm_prev_seq	$jm_seq
			}
		} else {
			log warning "can't find jm_prev_seq($jm_seq), pending:"
			array set _pending $pending
			parray _pending
			log warning "jm_prev_seq:"
			array set _jm_prev_seq $jm_prev_seq
			parray _jm_prev_seq
		}
	}

	#>>>
	method register_jm_key {jm_seq key} { #<<<
		#log debug "([my mungekey $key])" -suppress key
		dict set jm_keys $jm_seq	$key
	}

	#>>>
	method register_pending_encrypted {seq session_id} { #<<<
		#log debug "Registering [my mungekey [dict get $session_keys $session_id]] for seq: $seq"
		dict set e_pending $seq		$session_id
	}

	#>>>
	method handle_svc {svc cb} { #<<<
		if {$cb ne ""} {
			dict set svc_handlers $svc	$cb
			my new_svcs $svc
		} else {
			my revoke_svcs $svc
			dict unset svc_handlers $svc
		}
	}

	#>>>
	method encrypt {key data} { #<<<
		my variable key_schedules
		if {![info exists key_schedules] || ![dict exists $key_schedules $key]} {
			# FIXME: leaks - not cleaned out
			dict set key_schedules $key [crypto::blowfish::init_key $key]
		}
		set ks	[dict get $key_schedules $key]

		set iv		[crypto::blowfish::csprng 8]
		#return z$iv[crypto::blowfish::encrypt_cbc $ks [zlib deflate [encoding convertto utf-8 $data] 3] $iv]
		return $iv[crypto::blowfish::encrypt_cbc $ks [encoding convertto utf-8 $data] $iv]
	}

	#>>>
	method decrypt {key data} { #<<<
		my variable key_schedules
		if {![info exists key_schedules] || ![dict exists $key_schedules $key]} {
			# FIXME: leaks - not cleaned out
			dict set key_schedules $key [crypto::blowfish::init_key $key]
		}
		set ks	[dict get $key_schedules $key]

		set iv		[string range $data 0 7]
		set rest	[string range $data 8 end]
		#encoding convertfrom utf-8 [zlib inflate [crypto::blowfish::decrypt_cbc $ks $rest $iv]]
		encoding convertfrom utf-8 [crypto::blowfish::decrypt_cbc $ks $rest $iv]
	}

	#>>>
	method generate_key {{bytes 56}} { #<<<
		#crypto::rand_bytes $bytes
		#crypto::rand_pseudo_bytes $bytes
		# Hmmmm
		crypto::blowfish::csprng $bytes
	}

	#>>>
	method pseudo_bytes {{bytes 56}} { #<<<
		#crypto::rand_pseudo_bytes $bytes
		crypto::blowfish::csprng $bytes
	}

	#>>>
	method crypto {op args} { #<<<
		switch -- $op {
			register_or_get_chan { #<<<
				set session_id	[lindex $args 0]

				if {![dict exists $session_keys $session_id]} {
					dict set session_keys $session_id	[my generate_key]
				}

				return [dict get $session_keys $session_id]
				#>>>
			}

			register_chan { #<<<
				lassign $args session_id key

				if {[dict exists $session_keys $session_id]} {
					error "Already registered with key: ([my mungekey [dict get $session_keys $session_id]]), refusing to override with ([my mungekey $key])"
				}

				dict set session_keys $session_id	$key
				return [dict get $session_keys $session_id]
				#>>>
			}

			encrypt { #<<<
				lassign $args session_id msg

				#log debug "encrypting with session_id: $session_id, key [my mungekey [dict get $session_keys $session_id]]" -suppress {args}
				tailcall my encrypt [dict get $session_keys $session_id] $msg
				#>>>
			}

			decrypt { #<<<
				lassign $args session_id msg

				tailcall my decrypt [dict get $session_keys $session_id] $msg
				#>>>
			}

			registered_chan { #<<<
				lassign $args session_id

				return [dict exists $session_keys $session_id]
				#>>>
			}

			default {
				error "Not implemented: ($op)"
			}
		}
	}

	#>>>
	method mungekey {key} { #<<<
		#return "disabled"

		set build	0
		binary scan $key c* bytes
		foreach byte $bytes {
			incr build	$byte
		}
		return [format "%i" $build] 
	}

	#>>>
	method chans {op args} { #<<<
		switch -- $op {
			cancel { #<<<
				lassign $args seq

				if {![dict exists $chans $seq]} {
					log error "cancel: Unrecognised channel cancelled: ($seq)"
					return
				}

				switch -- [lindex [dict get $chans $seq] 0] {
					custom {
						set cb			[lindex [dict get $chans $seq] 1]
						if {$cb ne {}} {
							coroutine coro_chan_cancelled_[incr ::coro_seq] \
									{*}$cb cancelled {}
						}
					}

					default {
						log error "cancel: Unexpected type of channel cancelled: ([lindex [dict get $chans $seq] 0])"
					}
				}

				dict unset chans $seq
				#>>>
			}

			is_chanreq { #<<<
				lassign $args prev_seq

				dict exists $chans $prev_seq
				#>>>
			}

			chanreq { #<<<
				lassign $args seq prev_seq data

				if {![dict exists $chans $prev_seq]} {
					log error "chanreq: Unrecognised channel for chanreq: ($prev_seq)"
					return
				}

				switch -- [lindex [dict get $chans $prev_seq] 0] {
					custom { #<<<
						set cb			[lindex [dict get $chans $prev_seq] 1]
						if {$cb ne {}} {
							try {
								coroutine coro_chanreq_[incr ::coro_seq] \
									{*}$cb req [list $seq $prev_seq $data [self]]
							} on error {errmsg options} {
								log error "Error in chan_cb ($cb): $errmsg\n[dict get $options -errorinfo]"
								dict incr options -level
								return -options $options $errmsg
							}
						}
						#>>>
					}

					default { #<<<
						log error "chanreq: Unexpected type of channel in chanreq: ([lindex [dict get $chans $prev_seq] 0]) ($data)"
						my nack $seq "Unexpected type of channel in chanreq: ([lindex [dict get $chans $prev_seq] 0])"
						#>>>
					}
				}
				#>>>
			}

			register_chan { #<<<
				lassign $args seq cb

				if {[dict exists $chans $seq]} {
					log error "register_chan: chan already exists: ($seq)"
					return
				}
				#log debug "register_chan: Registering chan: ($seq) ($cb)"
				dict set chans $seq	[list custom $cb]
				#>>>
			}

			deregister_chan { #<<<
				lassign $args seq

				if {![dict exists $chans $seq]} {
					log error "deregister_chan: unrecognised chan: ($seq)"
					return
				}
				if {[lindex [dict get $chans $seq] 0] ne "custom"} {
					log error "deregister_chan: not custom chan: ($seq) ([lindex [dict get $chans $seq] 0])"
					return
				}
				#log debug "deregister_chan: Deregistering chan: ($seq)"
				dict unset chans $seq
				#>>>
			}

			default {
				error "Not implemented: ($op)"
			}
		}
	}

	#>>>
	method answered {seq} { #<<<
		! [dict exists $outstanding_reqs $seq]
	}

	#>>>
	method _add_profile_stamp {point so_far} { #<<<
		lappend so_far [list \
				[clock microseconds] \
				$point \
				[my cached_station_id]]
		set so_far
	}

	#>>>
	method _lost_connection {} { #<<<
		# TODO: nack all outstanding requests
		set msg	[m2::msg::new {
			type	jm_can
			svc		sys
		}]
		dict for {m_seq m_prev_seq} $jm_prev_seq {
			dict set msg seq		$m_seq
			dict set msg prev_seq	$m_prev_seq
			my _incoming $msg
		}
		dict for {seq info} $chans {
			set rest	[lassign $info type]
			if {$type eq "custom"} {
				set cb	[lindex $rest 0]
				if {$cb ne {}} {
					try {
						coroutine coro_chan_cancelled_[incr ::coro_seq] \
								{*}$cb cancelled {}
					} on error {errmsg options} {
						log error "_lost_connection channel cancel handler failed: [dict get $options -errorinfo]"
					}
				}
			} else {
				log error "Unhandled channel type \"$type\""
			}
		}
		set chans	[dict create]
	}

	#>>>
	method cached_station_id {} { #<<<
		my variable station_id
		if {![info exists station_id]} {
			set station_id	[my station_id]
		}
		return $station_id
	}

	#>>>
}



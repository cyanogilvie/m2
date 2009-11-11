# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> foldmarker=<<<,>>>

# TODO: handle connection collapse

# Signals:
#	onclose()		- fired when socket is closed and object is dieing

oo::class create m2::port {
	superclass cflib::handlers cflib::baselog

	variable {*}{
		server
		use_keepalive
		req
		jm
		jm_prev
		jm_ports
		jm_sport

		mysvcs
		outbound
		signals
		queue
		advertise
		neighbour_info
		dieing
		connected
	}

	constructor {mode parms a_queue a_params} { #<<<
		next
		my variable params
		set params	$a_params

		set use_keepalive		0
		set advertise			0
		set dieing				0

		array set signals	{}

		set jm				[dict create]
		set jm_prev			[dict create]
		set req				[dict create]
		set jm_ports		[dict create]
		set jm_sport		[dict create]
		set mysvcs			[dict create]
		set neighbour_info	[dict create \
			type	node \
		]

		set connected		0

		#configure {*}$parms
		if {[dict exists $parms -server]} {
			set server	[dict get $parms -server]
		} else {
			error "Must set -server"
		}

		switch -- $mode {
			inbound				{set outbound	0; set advertise	1}
			outbound			{set outbound	1; set advertise	0}
			outbound_advertise	{set outbound	1; set advertise	1}
			default		{error "Invalid mode: ($mode)"}
		}

		set queue	$a_queue

		$server register_port [self] $outbound $advertise

		oo::objdefine $queue method assign {rawmsg type seq prev_seq} { #<<<
			switch -- $type {
				rsj_req - req {
					set seq
				}

				pr_jm {
					my variable _pending_jm_setup
					puts stderr "[self] marking pending ($seq), prev_seq ($prev_seq)"
					dict set _pending_jm_setup $seq $prev_seq 1
					set prev_seq
				}
				
				jm - jm_can {
					set seq
				}

				default {
					set prev_seq
				}
			}
		}

		#>>>
		oo::objdefine $queue method pick {queues} { #<<<
			my variable _pending_jm_setup
			if {![info exists _pending_jm_setup]} {
				set _pending_jm_setup	[dict create]
			}

			set q		[next $queues]
			set first	$q

			# Skip queues for jms that were setup in requests for which
			# we still haven't sent the ack or nack
			while {[dict exists $_pending_jm_setup $q]} {
				set q		[next $queues]
				if {$q eq $first} {
					set errmsg	"[self] Eeek - all queues have the pending flag set, should never happen.  Queues:"
					foreach p $queues {
						if {[dict exists $_pending_jm_setup $p]} {
							append errmsg "\n\t($p): ([dict get $_pending_jm_setup $p])"
						} else {
							append errmsg "\n\t($p): --"
						}
					}
					if {[info commands "dutils::daemon_log"] ne {}} {
						dutils::daemon_log LOG_ERR $errmsg
					} else {
						puts stderr $errmsg
					}
					# Should never happen
					break
				}
			}

			return $q
		}

		#>>>
		oo::objdefine $queue method sent {type seq prev_seq} { #<<<
			if {$type in {
				ack
				nack
			}} {
				my variable _pending_jm_setup
				if {![info exists _pending_jm_setup]} {
					set _pending_jm_setup	[dict create]
				}

				dict for {s ps} $_pending_jm_setup {
					foreach p [dict keys $ps] {
						if {$p eq $prev_seq} {
							puts stderr "[self] Removing pending flag for ($s), $type prev_seq ($prev_seq) matches ($p)"
							dict unset _pending_jm_setup $s $p
							if {[dict size [dict get $_pending_jm_setup $s]] == 0} {
								dict unset _pending_jm_setup $s
							}
						}
					}
				}
			}
		}

		#>>>
		oo::objdefine $queue forward receive {*}[namespace code {my _receive}]
		oo::objdefine $queue forward closed {*}[namespace code {my _closed}]

		set connected	1
		log debug "m2::Port::constructor, self: ([self]), queue: ($queue) connection from ($params)"

		if {$advertise} {
			my _send_all_svcs
		}
	}

	#>>>
	destructor { #<<<
		my variable params

		if {![info exists params]} {set params	""}
		if {![info exists queue]} {set queue	""}
		log debug "m2::Port::destructor, self: ([self]), queue: ($queue) connection from ($params) closed"
		try {
			if {[info exists queue] && [info object is object $queue]} {
				set con	[$queue con]
				# $queue dies when $con does, close_con unsets $con
				if {[info object isa object $con]} {
					$con destroy
				} else {
					log warning "con $con died mysteriously under queue $queue"
					$queue destroy
				}
				unset queue
			}
		} on error {errmsg options} {
			log error "Error closing queue / con: $errmsg\n[dict get $options -errorinfo]"
		}
		#log debug "m2::Port::destructor: ($con)"
		foreach svc [dict keys $mysvcs] {
			$server revoke_svc $svc [self]
			dict unset mysvcs $svc
		}

		# nack all outstanding requests <<<
		set msg	[m2::msg new new \
				type		nack \
				svc			sys \
				data		"Port collapsed" \
		]
		dict for {seq details} $req {
			lassign $details oldmsg srcport
			$msg set seq		[$server unique_id]
			$msg set prev_seq	[$oldmsg get seq]
			try {
				$srcport send [self] $msg
			} on error {errmsg options} {
				my log warning "Failed to sent swansong nack: $errmsg"
			} on ok {errmsg options} {
				my log notice "Send swansong nack"
			}
			dict unset req $seq
			$oldmsg decref
		}
		# nack all outstanding requests >>>

		# jm_can and dismantle all jm originating with us
		set msg		[m2::msg new new \
			type	jm_can \
			svc		sys \
		]
		dict for {upid jmid} $jm {
			# Send the jm_can along to all recipients
			$msg seq		$jmid
			#puts stderr "jm_can: [$msg display]"
			foreach dport [dict get $jm_ports $jmid] {
				$msg prev_seq	[dict get $jm_prev $dport,$jmid]
				my _send_dport $dport $msg
			}

			# Dismantle our state for this jm channel
			dict unset jm $upid
			dict unset jm_prev $dport,$jmid
			dict unset jm_ports $jmid
		}
		
		$server unregister_port [self]
		#invoke_handlers onclose
		dict for {type cbs} [my dump_handlers] {
			if {$type eq "onclose"} {
				foreach cb $cbs {
					try {
						uplevel #0 $cb
					} on error {errmsg options} {
						puts stderr "m2::Port([self])::destructor: error calling onclose handler: ($cb): $errmsg\n[dict get $options -errorcode]"
					}
				}
			}
		}
		#set end_sample	[lf sample]
		if {[self next] ne {}} {next}
	}

	#>>>

	method send {srcport msg} { #<<<
		#puts "Port::send: ($srcport) -> ([self])"
		set m_seq		[$msg get seq]
		set m_prev_seq	[$msg get prev_seq]
		switch -- [$msg get type] {
			req { #<<<
				set newid	[$server unique_id]

				set newmsg	[m2::msg new clone $msg]
				$newmsg shift_seqs $newid

				$msg incref
				dict set req [$newmsg seq]		[list $msg $srcport]

				my _dispatch $newmsg
				#>>>
			}

			nack -
			ack { #<<<
				my _dispatch $msg
				#>>>
			}

			svc_avail -
			svc_revoke { #<<<
				#puts stderr "[$msg get type] writing"
				my _dispatch $msg
				#>>>
			}
			
			pr_jm -
			jm { #<<<
				#puts stderr "[$msg get type] writing:\n[$msg display]"
				if {![dict exists $jm_sport $m_seq]} {
					dict set jm_sport $m_seq	$srcport
				}
				my _dispatch $msg
				#>>>
			}
			
			jm_can { #<<<
				dict unset jm_sport $m_seq
				#puts stderr "[$msg get type] writing"
				my _dispatch $msg
				#>>>
			}

			jm_disconnect { #<<<
				# TODO: more efficiently
				dict for {up down} $jm {
					if {$down == $m_seq} {
						return [my _remove_jm_dport	$srcport $up $m_prev_seq]
					}
				}
				#parray jm
				error "No upstream path found for jm_disconnect: [$msg display]"
				#>>>
			}

			rsj_req { #<<<
				# TODO: more efficiently
				dict for {up down} $jm {
					if {$down == $m_prev_seq} {
						set newmsg	[m2::msg new clone $msg]
						$newmsg prev_seq	$up
						$newmsg seq			[$server unique_id]

						$msg incref
						dict set req [$newmsg seq]		[list $msg $srcport]

						my _dispatch $newmsg

						return
					}
				}
				error "No upstream path found for rsj_req: [$msg display]"
				#>>>
			}

			jm_req { #<<<
				set newid	[$server unique_id]

				#if {![dict exists $jm $m_prev_seq]} {
				#	log error "No jm([$msg prev_seq]) mc:"
				#	parray mc
				#	log error "jm:"
				#	parray jm
				#	error "No jm"
				#}
				#set jmid	[dict get $jm $m_prev_seq]
				set jmid	[$srcport downstream_jmid $m_prev_seq]
				set newmsg	[m2::msg new clone $msg]
				$newmsg prev_seq	$jmid
				$newmsg seq			$newid

				$msg incref
				dict set req $newid		[list $msg $srcport]

				my _dispatch $newmsg
				#>>>
			}

			default { #<<<
				error "Invalid msg type: ([$msg get type])"
				#>>>
			}
		}
	}

	#>>>
	method about {} { #<<<
	}

	#>>>
	method downstream_jmid {seq} { #<<<
		dict get $jm $seq
	}

	#>>>

	method type {} { #<<<
		dict get $neighbour_info type
	}

	#>>>
	method _receive {raw_msg} { #<<<
		set msg		[m2::msg new deserialize $raw_msg]
		my _got_msg $msg
	}

	#>>>
	method _got_msg {msg} { #<<<
		# Add profiling stamp if requested <<<
		if {[$msg get oob_type] eq "profiling"} {
			$msg set oob_data [my _add_profile_stamp \
					"[$msg get type]_in" \
					[$msg get oob_data]]
		}
		# Add profiling stamp if requested >>>

		set m_seq		[$msg get seq]
		set m_prev_seq	[$msg get prev_seq]

		switch -- [$msg get type] {
			svc_avail { #<<<
				foreach svc [$msg get data] {
					dict set mysvcs $svc	1
					$server announce_svc $svc [self]
				}
				#>>>
			}

			svc_revoke { #<<<
				foreach svc [$msg get data] {
					$server revoke_svc $svc [self]
					dict unset mysvcs $svc
				}
				#>>>
			}

			neighbour_info { #<<<
				#log debug "-- [my cached_station_id] got neighbour_info: [$msg get data]"
				set neighbour_info \
						[dict merge $neighbour_info [$msg get data]]
				#log debug "---- [my cached_station_id], neighbour_info type: ([dict get $neighbour_info type]), keys: ([dict keys $neighbour_info])"
				#>>>
			}

			req { #<<<
				set dport	[$server port_for_svc [$msg get svc] [self]]
				my _send_dport $dport $msg
				#>>>
			}

			ack { #<<<
				set pseq	$m_prev_seq
				set tmp		[dict get $req $pseq]
				lassign $tmp oldmsg dport
				$msg set prev_seq	[$oldmsg get seq]
				$msg set seq		[$server unique_id]

				#puts stderr "m2::Port::got_msg: passing ack along"
				my _send_dport $dport $msg
				dict unset req $pseq
				$oldmsg decref
				#>>>
			}

			nack { #<<<
				set pseq	$m_prev_seq
				set tmp		[dict get $req $pseq]
				lassign $tmp oldmsg dport
				$msg set prev_seq	[$oldmsg get seq]
				$msg set seq		[$server unique_id]

				# TODO: roll back any pr_jm setups in progress

				#puts stderr "m2::Port::got_msg: passing nack along"
				my _send_dport $dport $msg
				dict unset req $pseq
				$oldmsg decref
				#>>>
			}

			pr_jm -
			jm { #<<<
				set pseq	$m_prev_seq
				#log debug "------ [$msg get type], pseq: ($pseq) \[[my cached_station_id]\]"
				if {[dict exists $req $pseq]} {
					$msg type		pr_jm
					set tmp			[dict get $req $pseq]
					set oldmsgseq	[[lindex $tmp 0] seq]
					set dport		[lindex $tmp 1]

					if {![dict exists $jm $m_seq]} {
						dict set jm $m_seq	[$server unique_id]
					}
					set jmid	[dict get $jm $m_seq]
					#log debug "--------- sending pr_jm downstream with id: ($jmid)"
					#log debug "--------- dport ($dport) type is \"[$dport type]\" \[[$dport cached_station_id]\]"
					if {[$dport type] eq "application"} {
						if {
							![dict exists $jm_prev $dport,$jmid] || 
							$oldmsgseq ni [dict get $jm_prev $dport,$jmid]
						} {
							dict lappend jm_prev $dport,$jmid	$oldmsgseq
						}
					} else {
						dict set jm_prev $dport,$jmid		{}
					}
					if {
						![dict exists $jm_ports $jmid] ||
						$dport ni [dict get $jm_ports $jmid]
					} {
						dict lappend jm_ports $jmid	$dport
						$dport register_handler onclose [namespace code [list my _remove_jm_dport $dport $m_seq ""]]
						# TODO: need to arrange for this onclose handler to be
						# deregistered if we die
					}

					$msg set prev_seq	[list $oldmsgseq]
					$msg set seq		$jmid

					#puts stderr "pr_jm: [$msg display]"

					my _send_dport $dport $msg
				} else {
					if {![dict exists $jm $m_seq]} {
						log error "No junkmail: ($m_seq)"
						#if {[array exists jm]} {
						#	parray jm
						#}
						return
					}
					set jmid		[dict get $jm $m_seq]
					#puts "jm($m_seq): ($jmid)"

					$msg set type		jm
					$msg set seq		$jmid

					foreach dport [dict get $jm_ports $jmid] {
						$msg set prev_seq	[dict get $jm_prev $dport,$jmid]
						#puts stderr "jm -> $dport: [$msg display]"
						my _send_dport $dport $msg
					}
				}
				#>>>
			}

			rsj_req { #<<<
				if {![dict exists $jm_sport $m_prev_seq]} {
					error "No such junkmail for rsj_req: [$msg display]"
				}
				
				[dict get $jm_sport $m_prev_seq] send [self] $msg
				#>>>
			}

			jm_req { #<<<
				if {![dict exists $jm $m_prev_seq]} {
					log error "No junkmail: ($m_prev_seq):"
					#parray mc
					#log error "jm:"
					#parray jm
					return
				}
				set jmid	[dict get $jm $m_prev_seq]

				set rand_dest	[expr {round(rand() * ([llength [dict get $jm_ports $jmid]] - 1))}]
				set dport		[lindex [dict get $jm_ports $jmid] $rand_dest]
				#puts "randomly picked idx $rand_dest of [llength [dict get $jm_ports $jmid]]: ($dport)"

				#$msg seq	$jmid
				#$msg prev_seq	[dict get $jm_prev $dport,$jmid]
				my _send_dport $dport $msg
				#>>>
			}

			jm_can { #<<<
				if {![dict exists $jm $m_seq]} {
					#parray jm
					error "No such junkmail channel ([$msg seq])"
				}
				set jmid		[dict get $jm $m_seq]
				
				# Send the jm_can along to all recipients
				$msg set seq		$jmid
				#puts stderr "jm_can: [$msg display]"
				foreach dport [dict get $jm_ports $jmid] {
					$msg set prev_seq	[dict get $jm_prev $dport,$jmid]
					$dport deregister_handler onclose [namespace code [list my _remove_jm_dport $dport $m_seq ""]]
					my _send_dport $dport $msg
				}

				# Dismantle our state for this jm channel
				dict unset jm $m_seq
				dict unset jm_prev $dport,$jmid
				dict unset jm_ports $jmid
				#>>>
			}

			jm_disconnect { #<<<
				if {![dict exists $jm_sport $m_seq]} {
					error "No such junkmail for jm_disconnect: [$msg display]"
				}
				
				if {[[dict get $jm_sport $m_seq] send [self] $msg]} {
					# The above returns true if we don't receive this channel any more
					dict unset jm_sport $m_seq
				}
				#>>>
			}

			default { #<<<
				error "Invalid msg type: ([$msg get type])"
				#>>>
			}
		}
	}

	#>>>
	method _send_all_svcs {} { #<<<
		set msg		[m2::msg new new \
			type	svc_avail \
			seq		[$server unique_id] \
			data	[$server all_svcs] \
		]

		my send [self] $msg
	}

	#>>>
	method _remove_jm_dport {dport upstream_jmid prev_seq} { #<<<
		set jmid	[dict get $jm $upstream_jmid]
		if {$prev_seq == "" || $prev_seq == 0} {
			dict unset jm_prev		$dport,$jmid
		} else {
			if {[dict exists $jm_prev $dport,$jmid]} {
				set idx		[lsearch [dict get $jm_prev $dport,$jmid] $prev_seq]
				if {$idx == -1} {
					log warning "Asked to remove an invalid jm_prev: ($prev_seq)"
				} else {
					dict set jm_prev $dport,$jmid	[lreplace [dict get $jm_prev $dport,$jmid] $idx $idx]
					if {[llength [dict get $jm_prev $dport,$jmid]] == 0} {
						dict unset jm_prev	$dport,$jmid
					}
				}
			}
		}
		if {[dict exists $jm_prev $dport,$jmid]} {
			return 0
		}
		$dport deregister_handler onclose [namespace code [list my _remove_jm_dport $dport $upstream_jmid ""]]

		set idx		[lsearch [dict get $jm_ports $jmid] $dport]
		if {$idx == -1} return
		dict set jm_ports $jmid		[lreplace [dict get $jm_ports $jmid] $idx $idx]
		#puts stderr "m2::Port::remove_jm_dport: removing dport: ($dport) ($upstream_jmid) ($jmid)"
		if {[llength [dict get $jm_ports $jmid]] == 0} {
			#puts stderr "m2::Port::remove_jm_dport: all destinations for ($upstream_jmid) ($jmid) disconnected, sending jm_can upstream"
			
			set msg		[m2::msg new new \
				type	jm_disconnect \
				seq		$upstream_jmid \
			]
			my _dispatch $msg

			dict unset jm			$upstream_jmid
			dict unset jm_ports	$jmid
			#if {[catch {
			#	puts stderr "m2::Port::remove_jm_dport: jm:"
			#	parray jm
			#	puts stderr "m2::Port::remove_jm_dport: jm_ports:"
			#	parray jm_ports
			#	puts stderr "m2::Port::remove_jm_dport: jm_prev:"
			#	parray jm_prev
			#}]} {
			#	puts stderr "m2::Port::remove_jm_dport: $::errorInfo"
			#}
		}
		return 1
	}

	#>>>
	method _dispatch {msg} { #<<<
		if {!$connected} {
			::puts "PANIC: not connected"
			return
		}

		try {
			# Add profiling stamp if requested <<<
			if {[$msg get oob_type] eq "profiling"} {
				$msg set oob_data [my _add_profile_stamp \
						"[$msg get type]_out" \
						[$msg get oob_data]]
			}
			# Add profiling stamp if requested >>>

			$queue enqueue [$msg serialize] [$msg get type] [$msg get seq] [$msg get prev_seq]
		} on error {errmsg options} {
			log error "Error queueing message [$msg type] for port ([self]): $errmsg\n[dict get $options -errorinfo]"
			my _die
		}
	}

	#>>>
	method _send_dport {dport msg} { #<<<
		try {
			if {![info object isa object $dport]} {
				throw {CONNECTION DPORT_COLLAPSED} ""
			}
			$dport send [self] $msg
		} trap {CONNECTION DPORT_COLLAPSED} {} {
			puts stderr "m2::Port::send_dport($dport,$msg): this: ([self]) dport collapsed before we could send it the msg (type: \"[$msg type]\", svc: \"[$msg svc]\", seq: \"[$msg seq]\", prev_seq: \"[$msg prev_seq]\"), dropping msg"
		} on error {errmsg options} {
			puts stderr "m2::Port::send_dport($dport,$msg): this: ([self]) error sending ([$msg svc]): $errmsg {[dict get $options -errorcode]}\n[dict get $options -errorinfo]"
		}
	}

	#>>>
	method _closed {} { #<<<
		my _die
	}

	#>>>
	method _t_not_connected {} { #<<<
		my _die
	}

	#>>>
	method _t_got_msg_sdata {msg_sdata} { #<<<
		set msg		[m2::msg new deserialize $msg_sdata]
		my _got_msg $msg
	}

	#>>>
	method _die {} { #<<<
		if {$dieing} return

		set connected	0
		set dieing	1
		my destroy
		return -code return
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
	method cached_station_id {} { #<<<
		my variable station_id
		if {![info exists station_id]} {
			set station_id	[my station_id]
		}
		return $station_id
	}

	#>>>
	method station_id {} { #<<<
		return "m2_node [[$queue con] human_id]"
	}

	#>>>
}



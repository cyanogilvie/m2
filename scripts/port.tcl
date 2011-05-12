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

		queue_mode
		mysvcs
		outbound
		signals
		queue
		advertise
		neighbour_info
		dieing
		connected
		svc_filter
	}

	constructor {mode parms a_queue a_params} { #<<<
		package require evlog

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
			type		node \
			debug_name	"" \
		]

		set connected		0

		#configure {*}$parms
		if {[dict exists $parms -server]} {
			set server	[dict get $parms -server]
		} else {
			error "Must set -server"
		}
		if {[dict exists $parms -queue_mode]} {
			set queue_mode	[dict get $parms -queue_mode]
		} else {
			set queue_mode	"fancy"
		}

		switch -- $mode {
			inbound				{set outbound	0; set advertise	1}
			outbound			{set outbound	1; set advertise	0}
			outbound_advertise	{set outbound	1; set advertise	1}
			default		{error "Invalid mode: ($mode)"}
		}

		if {[dict exists $parms -filter]} {
			set svc_filter	[my _compile_filter [dict get $parms -filter]]
		} else {
			set svc_filter	[my _compile_filter "allow_in(all)"]
		}
		?? {
			log debug "svc_filter:\n$svc_filter"
		}

		set queue	$a_queue

		$server register_port [self] $outbound $advertise

		if {$queue_mode eq "fancy"} {
			oo::objdefine $queue method assign {rawmsg type seq prev_seq} { #<<<
				#if {[info commands "dutils::daemon_log"] ne {}} {
				#	dutils::daemon_log LOG_DEBUG "queueing $type $seq $prev_seq"
				#} else {
				#	puts stderr "queueing $type $seq $prev_seq"
				#}
				switch -- $type {
					rsj_req - req {
						set seq
					}

					jm - jm_can {
						if {$prev_seq eq 0} {
							set seq
						} else {
							my variable _pending_jm_setup
							#puts stderr "[self] marking pending ($seq), prev_seq ($prev_seq)"
							dict set _pending_jm_setup $seq $prev_seq 1
							set prev_seq
						}
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
							log error $errmsg
						}
						# Should never happen
						break
					}
				}

				return $q
			}

			#>>>
			oo::objdefine $queue method sent {type seq prev_seq} { #<<<
				#if {[info commands "dutils::daemon_log"] ne {}} {
				#	dutils::daemon_log LOG_DEBUG "sent $type $seq $prev_seq"
				#} else {
				#	puts stderr "sent $type $seq $prev_seq"
				#}
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
								log debug "[self] Removing pending flag for ($s), $type prev_seq ($prev_seq) matches ($p)"
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
		} elseif {$queue_mode eq "fifo"} {
			oo::objdefine $queue method assign {rawmsg type seq prev_seq} { #<<<
				return "_fifo"
			}

			#>>>
			oo::objdefine $queue method pick {queues} { #<<<
				return "_fifo"
			}

			#>>>
			oo::objdefine $queue method sent {type seq prev_seq} { #<<<
			}

			#>>>
		} else {
			error "Invalid queue mode: ($queue_mode)"
		}
		oo::objdefine $queue forward receive {*}[namespace code {my _got_msg}]
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
		set msg	[m2::msg::new {
			type		nack
			svc			sys
			data		"Port collapsed"
		}]
		dict for {seq details} $req {
			lassign $details oldmsg srcport
			dict set msg seq		[$server unique_id]
			dict set msg prev_seq	[dict get $oldmsg seq]
			try {
				$srcport send [self] $msg
			} on error {errmsg options} {
				my log warning "Failed to sent swansong nack: $errmsg"
			} on ok {errmsg options} {
				my log notice "Send swansong nack"
			}
			dict unset req $seq
		}
		# nack all outstanding requests >>>

		# jm_can and dismantle all jm originating with us
		set msg		[m2::msg::new {
			type	jm_can
			svc		sys
		}]
		dict for {upid jmid} $jm {
			# Send the jm_can along to all recipients
			dict set msg seq		$jmid
			#puts stderr "jm_can: [m2::msg::display $msg]"
			foreach dport [dict get $jm_ports $jmid] {
				dict set msg prev_seq	[dict get $jm_prev $dport,$jmid]
				my _send_dport $dport $msg
			}

			# Dismantle our state for this jm channel
			dict unset jm $upid
			dict unset jm_prev $dport,$jmid
			dict unset jm_ports $jmid
		}
		
		$server unregister_port [self]
		#invoke_handlers onclose
		set handlers	[my dump_handlers]
		?? {log debug "m2::Port([self])::destructor: calling registered onclose handlers: $handlers"}
		if {[dict exists $handlers onclose]} {
			foreach cb [dict get $handlers onclose] {
				?? {log debug "m2::Port([self])::destructor: attempting to call onclose handler ($cb)"}
				try {
					uplevel #0 $cb
				} on error {errmsg options} {
					log error "m2::Port([self])::destructor: error calling onclose handler: ($cb): $errmsg\n[dict get $options -errorcode]"
				}
			}
		}
		#set end_sample	[lf sample]
		if {[self next] ne {}} {next}
	}

	#>>>

	method send {srcport msg} { #<<<
		#puts "Port::send: ($srcport) -> ([self])"
		set m_seq		[dict get $msg seq]
		set m_prev_seq	[dict get $msg prev_seq]
		switch -- [dict get $msg type] {
			req { #<<<
				set newid	[$server unique_id]

				set newmsg	[dict replace $msg \
						prev_seq	$m_seq \
						seq			$newid \
				]

				dict set req $newid		[list $msg $srcport]

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
				#puts stderr "[dict get $msg type] writing"
				my _dispatch $msg
				#>>>
			}
			
			pr_jm -
			jm { #<<<
				#puts stderr "[dict get $msg type] writing:\n[m2::msg::display $msg]"
				if {![dict exists $jm_sport $m_seq]} {
					dict set jm_sport $m_seq	$srcport
				}
				my _dispatch $msg
				#>>>
			}
			
			jm_can { #<<<
				dict unset jm_sport $m_seq
				#puts stderr "[dict get $msg type] writing"
				my _dispatch $msg
				#>>>
			}

			jm_disconnect { #<<<
				# TODO: more efficiently
				?? {log debug "m2::Port([self])::send: sending jm_disconnect($m_seq)"}
				dict for {up down} $jm {
					if {$down == $m_seq} {
						?? {log debug "Found upstream path for jm: ($up), calling _remove_jm_dport"}
						return [my _remove_jm_dport $srcport $up $m_prev_seq]
					}
				}
				#parray jm
				error "No upstream path found for jm_disconnect: [m2::msg::display $msg]"
				#>>>
			}

			rsj_req { #<<<
				# TODO: more efficiently
				dict for {up down} $jm {
					if {$down == $m_prev_seq} {
						set newmsg	[dict replace $msg \
								prev_seq	$up \
								seq			[$server unique_id] \
						]

						dict set req [dict get $newmsg seq]		[list $msg $srcport]

						my _dispatch $newmsg

						return
					}
				}
				error "No upstream path found for rsj_req: [m2::msg::display $msg]"
				#>>>
			}

			jm_req { #<<<
				set newid	[$server unique_id]

				#if {![dict exists $jm $m_prev_seq]} {
				#	log error "No jm([dict get $msg prev_seq]) mc:"
				#	parray mc
				#	log error "jm:"
				#	parray jm
				#	error "No jm"
				#}
				#set jmid	[dict get $jm $m_prev_seq]

				dict set req $newid		[list $msg $srcport]

				my _dispatch [dict replace $msg \
						prev_seq	[$srcport downstream_jmid $m_prev_seq] \
						seq			$newid \
				]
				#>>>
			}

			default { #<<<
				error "Invalid msg type: ([dict get $msg type])"
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
	method allow_svc_out {svc} { #<<<
		apply $svc_filter $svc out
	}

	#>>>
	method _got_msg {raw_msg} { #<<<
		set msg	[m2::msg::deserialize $raw_msg]
		evlog event m2.receive_msg {[list from [my cached_station_id] msg $msg]}
		?? {log trivia "-> Got msg ([my cached_station_id]) [m2::msg::display $msg]"}
		# Add profiling stamp if requested <<<
		if {[dict get $msg oob_type] eq "profiling"} {
			dict set msg oob_data [my _add_profile_stamp \
					"[dict get $msg type]_in" \
					[dict get $msg oob_data]]
		}
		# Add profiling stamp if requested >>>

		set m_seq		[dict get $msg seq]
		set m_prev_seq	[dict get $msg prev_seq]

		switch -- [dict get $msg type] {
			svc_avail { #<<<
				foreach svc [dict get $msg data] {
					if {[apply $svc_filter $svc in]} {
						dict set mysvcs $svc	1
						$server announce_svc $svc [self]
					}
				}
				#>>>
			}

			svc_revoke { #<<<
				foreach svc [dict get $msg data] {
					if {[apply $svc_filter $svc in]} {
						$server revoke_svc $svc [self]
						dict unset mysvcs $svc
					}
				}
				#>>>
			}

			neighbour_info { #<<<
				#log debug "-- [my cached_station_id] got neighbour_info: [dict get $msg data]"
				set neighbour_info	[dict merge \
						$neighbour_info[unset neighbour_info] \
						[dict get $msg data]]
				my variable station_id
				if {[info exists station_id]} {unset station_id}
				#log debug "---- [my cached_station_id], neighbour_info type: ([dict get $neighbour_info type]), keys: ([dict keys $neighbour_info])"
				#>>>
			}

			req { #<<<
				try {
					$server port_for_svc [dict get $msg svc] [self]
				} on error {errmsg options} {
					log warning "Req collided with svc_revoke for [dict get $msg svc]"
					set nack	[m2::msg::new [list \
							type	nack \
							svc		sys \
							data	"svc unavailable - crashed into svc_revoke" \
							seq		[$server unique_id] \
							prev_seq	$m_seq \
					]]
					my _dispatch $nack
				} on ok {dport} {
					my _send_dport $dport $msg
				}
				#>>>
			}

			ack { #<<<
				lassign [dict get $req $m_prev_seq] oldmsg dport
				dict set msg prev_seq	[dict get $oldmsg seq]
				dict set msg seq		[$server unique_id]

				#puts stderr "m2::Port::got_msg: passing ack along"
				my _send_dport $dport $msg
				dict unset req $m_prev_seq
				#>>>
			}

			nack { #<<<
				lassign [dict get $req $m_prev_seq] oldmsg dport
				dict set msg prev_seq	[dict get $oldmsg seq]
				dict set msg seq		[$server unique_id]

				# TODO: roll back any pr_jm setups in progress

				#puts stderr "m2::Port::got_msg: passing nack along"
				my _send_dport $dport $msg
				dict unset req $m_prev_seq
				#>>>
			}

			pr_jm -
			jm { #<<<
				#log debug "------ [dict get $msg type], pseq: ($m_prev_seq) \[[my cached_station_id]\]"
				if {[dict exists $req $m_prev_seq]} {
					dict set msg type	pr_jm
					set tmp				[dict get $req $m_prev_seq]
					set oldmsgseq		[dict get [lindex $tmp 0] seq]
					set dport			[lindex $tmp 1]

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

					dict set msg prev_seq	[list $oldmsgseq]
					dict set msg seq		$jmid

					#puts stderr "pr_jm: [m2::msg::display $msg]"

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

					dict set msg type		jm
					dict set msg seq		$jmid

					foreach dport [dict get $jm_ports $jmid] {
						dict set msg prev_seq	[dict get $jm_prev $dport,$jmid]
						#puts stderr "jm -> $dport: [m2::msg::display $msg]"
						my _send_dport $dport $msg
					}
				}
				#>>>
			}

			rsj_req { #<<<
				if {![dict exists $jm_sport $m_prev_seq]} {
					#error "No such junkmail for rsj_req: [m2::msg::display $msg]"
					log error "No such junkmail for rsj_req: [m2::msg::display $msg]"
					try {
						my _dispatch [m2::msg::new [list \
								type	nack \
								svc		sys \
								data	"No such junkmail for rsj_req" \
								seq		[$server unique_id] \
								prev_seq	$m_seq \
						]]
					} on error {errmsg options} {
						log error "Error sending nack for rsj_req: [dict get $options -errorinfo]"
					}
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

				set rand_dest	[expr {int(rand() * [llength [dict get $jm_ports $jmid]])}]
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
					log error "No such junkmail channel ([dict get $msg seq])"
					return
				}
				set jmid		[dict get $jm $m_seq]
				
				# Send the jm_can along to all recipients
				dict set msg seq		$jmid
				#puts stderr "jm_can: [m2::msg::display $msg]"
				foreach dport [dict get $jm_ports $jmid] {
					dict set msg prev_seq	[dict get $jm_prev $dport,$jmid]
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
					log error "No such junkmail for jm_disconnect: [m2::msg::display $msg]"
					#error "No such junkmail for jm_disconnect: [m2::msg::display $msg]"
				} else {
					if {[[dict get $jm_sport $m_seq] send [self] $msg]} {
						# The above returns true if we don't receive this
						# channel any more
						dict unset jm_sport $m_seq
					}
				}
				#>>>
			}

			default { #<<<
				error "Invalid msg type: ([dict get $msg type])"
				#>>>
			}
		}
	}

	#>>>
	method _send_all_svcs {} { #<<<
		set advertised_services	[list]
		foreach svc [$server all_svcs] {
			if {[my allow_svc_out $svc]} {
				lappend advertised_services	$svc
			}
		}
		my send [self] [m2::msg::new [list \
			type	svc_avail \
			seq		[$server unique_id] \
			data	$advertised_services \
		]]
	}

	#>>>
	method _remove_jm_dport {dport upstream_jmid prev_seq} { #<<<
		set jmid	[dict get $jm $upstream_jmid]
		if {$prev_seq eq "" || $prev_seq == 0} {
			?? {log warning "m2::Port::_remove_jm_dport called with prev_seq: ($prev_seq)"}
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
			?? {log debug "Still have destinations for $dport,$jmid: ([dict get $jm_prev $dport,$jmid])"}
			return 0
		}
		#?? {log debug "Deregistering ($dport) onclose handler for ([namespace code [list my _remove_jm_dport $dport $upstream_jmid \"\"]]), before:\n([join [dict get [$dport dump_handlers] onclose] \n])"}
		$dport deregister_handler onclose [namespace code [list my _remove_jm_dport $dport $upstream_jmid ""]]
		#?? {log debug "Deregistering ($dport) onclose handler for ([namespace code [list my _remove_jm_dport $dport $upstream_jmid \"\"]]), after:\n([join [dict get [$dport dump_handlers] onclose] \n])"}

		set idx		[lsearch [dict get $jm_ports $jmid] $dport]
		if {$idx == -1} {
			#?? {log debug "m2::Port::_remove_jm_dport: dport ($dport) not a destination for ($jmid)"}
			return
		}
		dict set jm_ports $jmid		[lreplace [dict get $jm_ports $jmid] $idx $idx]
		#?? {log debug "m2::Port::_remove_jm_dport: removing dport: ($dport) ($upstream_jmid) ($jmid)"}
		if {[llength [dict get $jm_ports $jmid]] == 0} {
			#?? {log debug "m2::Port::_remove_jm_dport: all destinations for ($upstream_jmid) ($jmid) disconnected, sending jm_disconnect upstream"}

			my _dispatch [m2::msg::new [list \
				type	jm_disconnect \
				seq		$upstream_jmid \
			]]

			#?? {log debug "jm(\$upstream_jmid<$upstream_jmid>): [dict get $jm $upstream_jmid]"}
			dict unset jm		$upstream_jmid
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
			if {[dict get $msg oob_type] eq "profiling"} {
				dict set msg oob_data [my _add_profile_stamp \
						"[dict get $msg type]_out" \
						[dict get $msg oob_data]]
			}
			# Add profiling stamp if requested >>>
			?? {log trivia "<- Sending msg ([my cached_station_id]) [m2::msg::display $msg]"}

			evlog event m2.queue_msg {[list to [my cached_station_id] msg $msg]}
			$queue enqueue [m2::msg::serialize $msg] [dict get $msg type] [dict get $msg seq] [dict get $msg prev_seq]
		} on error {errmsg options} {
			log error "Error queueing message [dict get $msg type] for port ([self]): $errmsg\n[dict get $options -errorinfo]"
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
			log warning "m2::Port::send_dport($dport,<msg>): this: ([self]) dport collapsed before we could send it the msg (type: \"[dict get $msg type]\", svc: \"[dict get $msg svc]\", seq: \"[dict get $msg seq]\", prev_seq: \"[dict get $msg prev_seq]\"), dropping msg"
		} on error {errmsg options} {
			log error "m2::Port::send_dport($dport,<msg>): this: ([self]) error sending ([dict get $msg svc]): $errmsg {[dict get $options -errorcode]}\n[dict get $options -errorinfo]"
		}
	}

	#>>>
	method _closed {} { #<<<
		my _die
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
	}

	#>>>
	method _compile_filter {filter_config} { #<<<
		?? {log debug "Compiling filter $filter_config"}
		set body	[list]
		lappend body {set allowed 1}
		foreach term [split $filter_config ";"] {
			switch -regexp -matchvar matches -- $term {
				{^allow\(all\)$} {
					lappend body	{set allowed 1}
				}
				{^allow\((.*?)\)$} {
					set svcs	[split [lindex $matches 1] ,]
					lappend body	[format {
						foreach p %s {
							if {[string match $p $svc]} {
								set allowed 1
								break
							}
						}
					} [list $svcs]]
				}
				{^allow_in\(all\)$} {
					lappend body	{if {$dir eq "in"} {set allowed 1}}
				}
				{^allow_out\(all\)$} {
					lappend body	{if {$dir eq "out"} {set allowed 1}}
				}
				{^allow_in\((.*?)\)$} {
					set svcs	[split [lindex $matches 1] ,]
					lappend body	[format {
						if {$dir eq "in"} {
							foreach p %s {
								if {[string match $p $svc]} {
									set allowed	1
									break
								}
							} [list $svcs]
						}
					}
				}
				{^allow_out\((.*?)\)$} {
					set svcs	[split [lindex $matches 1] ,]
					lappend body	[format {
						if {$dir eq "out"} {
							foreach p %s {
								if {[string match $p $svc]} {
									set allowed	1
									break
								}
							}
						}
					} [list $svcs]]
				}
				{^deny\(all\)$} {
					lappend body	{set allowed 0}
				}
				{^deny\((.*?)\)$} {
					set svcs	[split [lindex $matches 1] ,]
					lappend body	[format {
						foreach p %s {
							if {[string match $p $svc]} {
								set allowed 0
								break
							}
						}
					} [list $svcs]]
				}
				{^deny_in\(all\)$} {
					lappend body	{if {$dir eq "in"} {set allowed 0}}
				}
				{^deny_out\(all\)$} {
					lappend body	{if {$dir eq "out"} {set allowed 0}}
				}
				{^deny_in\((.*?)\)$} {
					set svcs	[split [lindex $matches 1] ,]
					lappend body [format {
						if {$dir eq "in"} {
							foreach p %s {
								if {[string match $p $svc]} {
									set allowed	0
									break
								}
							}
						}
					} [list $svcs]]
				}
				{^deny_out\((.*?)\)$} {
					set svcs	[split [lindex $matches 1] ,]
					lappend body [format {
						if {$dir eq "in"} {
							foreach p %s {
								if {[string match $p $svc]} {
									set allowed	0
									break
								}
							}
						}
					} [list $svcs]]
				}
				default {
					error "Syntax error in svc filter description: unknown op \"$term\""
				}
			}
		}
		lappend body {set allowed}
		list {svc dir} [join $body \n]
	}

	#>>>
	method cached_station_id {} { #<<<
		my variable station_id
		if {![info exists station_id]} {
			set station_id	[my station_id]
		} else {
			set station_id
		}
	}

	#>>>
	method station_id {} { #<<<
		return "m2_node [[$queue con] human_id] \"[dict get $neighbour_info debug_name]\""
	}

	#>>>
}



# vim: ts=4 foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create m2::node {
	constructor {args} { #<<<
		set svcs							[dict create]
		set ports							[dict create]
		set outbound_ports					[dict create]
		set advertise_ports					[dict create]
		set outbound_connection_afterids	[dict create]

		# Defaults
		set listen_on			{"tcp_coroutine://:5307"}
		set connection_retry	10
		set upstream			{}

		dict for {k v} $args {
			if {[string index $k 0] ne "-"} {
				error "Expecting parameter, got \"$k\""
			}
			set k	[string range $k 1 end]
			if {$k ni {
				listen_on connection_retry upstream
			}} {
				error "Invalid parameter: -$k"
			}
			set $k $v
		}

		# private vars
		set listens	{}
		set id		0

		my _bind

		foreach upstream $upstream {
			my _attempt_outbound_connection $upstream
		}
	}

	#>>>
	destructor { #<<<
		foreach listen $listens {
			if {[info object is object $listen]} {
				$listen destroy
			}
		}
		set listens	{}
		dict for {addr id} $outbound_connection_afterids {
			after cancel $id; dict set $outbound_connection_afterids $addr 	""
		}
		if {[self next] ne {}} {next}
	}

	#>>>

	variable {*}{
		listen_on
		connection_retry
		upstream

		listens
		svcs
		id
		ports
		outbound_ports
		advertise_ports
		outbound_connection_afterids
	}

	method announce_svc {svc port} { #<<<
		set new		[expr {![dict exists $svcs $svc]}]
		if {!$new && $port in [dict get $svcs $svc]} return
		dict lappend svcs $svc	$port
		#my _puts stderr "m2::Node::announce_svc: ($svc) ($port)"

		if {$new} {
			set msg		[m2::msg new new \
				type	svc_avail \
				seq		[my unique_id] \
				data	[list $svc] \
			]

			foreach dport [my all_ports $port] {
				# Prune out outbound connections, ala, "orange links" pan in IML
				if {[dict get $advertise_ports $dport] == 0} continue
				#puts stderr "sending msg: ($msg)"
				try {
					$dport send $port $msg
				} on error {errmsg options} {
					puts stderr "m2::Node::announce_svc: Error sending svc_avail to dport: ($dport): $errmsg\n[dict get $options -errorinfo]"
				}
			}
		}
	}

	#>>>
	method revoke_svc {svc port} { #<<<
		if {![dict exists $svcs $svc] || [set idx [lsearch [dict get $svcs $svc] $port]] == -1} return
		dict set svcs $svc	[lreplace [dict get $svcs $svc] $idx $idx]
		#my _puts stderr "m2::Node::revoke_svc: ($svc) ($port)"

		if {[llength [dict get $svcs $svc]] == 0} {
			dict unset svcs $svc

			set msg		[m2::msg new new \
				type	svc_revoke \
				seq		[my unique_id] \
				data	[list $svc] \
			]

			foreach dport [my all_ports $port] {
				# Prune out outbound connections, ala, "orange links" pan in IML
				if {[dict get $advertise_ports $dport] == 0} continue
				#my _puts stderr "sending msg: ($msg)"
				try {
					$dport send $port $msg
				} on error {errmsg options} {
					puts stderr "m2::Node::announce_svc: Error sending svc_revoke to dport: ($dport): $errmsg\n[dict get $options -errorinfo]"
				}
			}
		}
	}

	#>>>
	method port_for_svc {svc {excl {}}} { #<<<
		if {![dict exists $svcs $svc]} {
			error "Service ($svc) not available"
		}
		set tmp			[m2::intersect3 [dict get $svcs $svc] $excl]
		set remaining	[lindex $tmp 0]
		if {[llength $remaining] == 0} {
			error "Service ($svc) not available"
		}
		set idx			[expr {round(rand() * ([llength $remaining] - 1))}]
		#my _puts stderr "m2::Node::port_for_svc: ($svc) ([dict get $svcs $svc]) idx: ($idx)"
		return [lindex $remaining $idx]
	}

	#>>>
	method unique_id {} { #<<<
		incr id
	}

	#>>>
	method register_port {port outbound {advertise "default"}} { #<<<
		dict set ports $port	$outbound
		if {$outbound} {
			dict set outbound_ports $port	1
		}
		if {$advertise eq "default"} {
			dict set advertise_ports $port	[expr {
				![dict exists $outbound_ports $port]
			}]
		} else {
			dict set advertise_ports $port	$advertise
		}
	}

	#>>>
	method unregister_port {port} { #<<<
		dict unset ports 			$port
		dict unset outbound_ports	$port
		dict unset advertise_ports	$port
	}

	#>>>
	method all_ports {args} { #<<<
		set tmp	[m2::intersect3 [dict keys $ports] $args]
		return [lindex $tmp 0]
	}

	#>>>
	method all_svcs {} { #<<<
		dict keys $svcs
	}

	#>>>

	method _bind {} { #<<<
		foreach address $listen_on {
			set listen	[netdgram::listen_uri $address]

			oo::objdefine $listen forward accept \
					{*}[namespace code {my _accept_inbound}]

			lappend listens	$listen
			log notice "Ready on ($address), version [package require m2]"
		}
	}

	#>>>
	method _attempt_outbound_connection {addr} { #<<<
		set flags	"N"

		if {[string first "//" $addr] == -1} {
			set tmp		[split $addr :]
			switch -- [llength $tmp] {
				1 {
					set upip	[lindex $tmp 0]
					set upport	5307
				}

				2 {
					set upip	[lindex $tmp 0]
					set upport	[lindex $tmp 1]
				}

				3 {
					set upip	[lindex $tmp 0]
					set upport	[lindex $tmp 1]
					set flags	[lindex $tmp 2]
				}

				default {
					error "Invalid upstream address specification: ($addr)"
				}
			}

			set addr	"tcp_coroutine://$upip:$upport/?flags=$flags"
		}

		if {$flags eq "NA"} {
			set flags	"N"
		}

		set use_keepalive	0
		foreach flag [split $flags {}] {
			switch -- $flag {
				"N" {
					set contype	"outbound"
				}

				"A" {
					set contype	"outbound_advertise"
				}

				"K" {
					set use_keepalive	1
				}
				
				default {
					log warning "Node::attempt_outbound_connection: invalid flag: ($flag)"
				}
			}
		}
		if {![info exists contype]} {
			set contype	"outbound"
		}

		try {
			set con		[netdgram::connect_uri $addr]
			set queue	[netdgram::queue new]
			$queue attach $con
		} on error {errmsg options} {
			log notice "m2::Node::constructor: error connecting to upstream: ($addr): $errmsg\n[dict get $options -errorinfo]"

			dict set outbound_connection_afterids $addr	[after \
					[expr {int($connection_retry * 1000)}] \
					[namespace code [list my _attempt_outbound_connection $addr]]]
		} on ok {res options} {
			set params	{}		;# !?
			set p	[m2::port new $contype [list \
						-server [self] \
						-use_keepalive $use_keepalive \
					] \
					$queue $params]
			$p register_handler onclose \
					[namespace code [list my _attempt_outbound_connection $addr]]
			$con activate
		}
	}

	#>>>
	method _accept_inbound {con cl_ip cl_port} { #<<<
		set queue [netdgram::queue new]
		$queue attach $con
		m2::port new inbound \
				[list -server [self]] $queue [list $cl_ip $cl_port]
	}

	#>>>
	method _puts {args} { #<<<
		puts {*}$args
	}

	#>>>
}



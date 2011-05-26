# vim: ts=4 foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create m2::node {
	variable {*}{
		listen_on
		connection_retry
		upstream
		queue_mode
		io_threads

		listens
		svcs
		id
		ports
		outbound_ports
		advertise_ports
		outbound_connection_afterids
		threads
	}

	constructor {args} { #<<<
		if {[self next] ne ""} next

		set svcs							[dict create]
		set ports							[dict create]
		set outbound_ports					[dict create]
		set advertise_ports					[dict create]
		set outbound_connection_afterids	[dict create]
		set threads							[dict create]

		package require Thread 2.6.6
		package require netdgram::tcp
		oo::define netdgram::connectionmethod::tcp method default_port {} {
			return 5300
		}

		namespace path [concat [namespace path] {
			::tcl::mathop
		}]

		# Defaults
		set listen_on			{"tcp://:5300"}
		set connection_retry	10
		set upstream			{}
		set evlog				""
		set queue_mode			fancy
		set io_threads			0

		dict for {k v} $args {
			if {[string index $k 0] ne "-"} {
				error "Expecting parameter, got \"$k\""
			}
			set k	[string range $k 1 end]
			if {$k ni {
				listen_on connection_retry upstream evlog queue_mode io_threads
			}} {
				error "Invalid parameter: -$k"
			}
			set $k $v
		}

		if {$io_threads > 0} {
			for {set i 0} {$i < $io_threads} {incr i} {
				set tid	[thread::create -preserved [string map [list \
						%tm_path%	[tcl::tm::path list] \
						%auto_path%	[list $::auto_path] \
						%main_tid%	[list [thread::id]] \
						%debug%		[cfg get debug] \
				] {
					tcl::tm::path add %tm_path%
					set ::auto_path	%auto_path%
					set main_tid	%main_tid%
					package require netdgram
					package require m2

					if {%debug%} {
						proc ?? script {uplevel 1 $script}
					} else {
						proc ?? args {}
					}

					proc log args {thread::send -async %main_tid% [list log {*}$args]}

					thread::wait
				}]]
				dict set threads $tid {}
			}
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
		# TODO: destroy ports, io_threads
		if {[self next] ne ""} next
	}

	#>>>

	method announce_svc {svc port} { #<<<
		set new		[expr {![dict exists $svcs $svc]}]
		if {!$new && $port in [dict get $svcs $svc]} return
		dict lappend svcs $svc	$port
		#my _puts stderr "m2::Node::announce_svc: ($svc) ($port)"

		if {$new} {
			set msg		[m2::msg::new [list \
				type	svc_avail \
				seq		[my unique_id] \
				data	[list $svc] \
			]]

			foreach dport [my all_ports $port] {
				# Prune out outbound connections, ala, "orange links" pan in IML
				if {[dict get $advertise_ports $dport] == 0} continue
				if {![$dport allow_svc_out $svc]} continue
				#puts stderr "sending msg: ([m2::msg::display $msg])"
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

			set msg		[m2::msg::new [list \
				type	svc_revoke \
				seq		[my unique_id] \
				data	[list $svc] \
			]]

			foreach dport [my all_ports $port] {
				# Prune out outbound connections, ala, "orange links" pan in IML
				if {[dict get $advertise_ports $dport] == 0} continue
				#my _puts stderr "sending msg: ([m2::msg::display $msg])"
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
		set remaining	{}
		foreach port [dict get $svcs $svc] {
			if {$port ne $excl} {
				lappend remaining	$port
			}
		}
		if {[llength $remaining] == 0} {
			error "Service ($svc) not available"
		}
		#my _puts stderr "m2::Node::port_for_svc: ($svc) ([dict get $svcs $svc]) idx: ($idx)"
		lindex $remaining [expr {int(rand() * [llength $remaining])}]
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
		lindex [cflib::intersect3 [dict keys $ports] $args] 0
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
					{*}[namespace code {my _accept_inbound_pre}]

			lappend listens	$listen
			log notice "Ready on ($address), version [package require m2]"
		}
	}

	#>>>
	method _attempt_outbound_connection {addr} { #<<<
		set flags	"N"
		set filter	""

		if {[string first "//" $addr] == -1} {
			set tmp		[split $addr :]
			switch -- [llength $tmp] {
				1 {
					set upip	[lindex $tmp 0]
					set upport	5300
				}

				2 {lassign $tmp upip upport}
				3 {lassign $tmp upip upport flags}

				default {
					error "Invalid upstream address specification: ($addr)"
				}
			}

			set addr	"tcp://$upip:$upport/?flags=$flags"
		}

		set uri_obj	[netdgram::uri new $addr]
		try {
			set query	[dict get [$uri_obj as_dict] query]
			if {[dict exists $query flags]} {
				set flags	[dict get $query flags]
			}
			if {[dict exists $query filter]} {
				set filter	[dict get $query filter]
			}
		} finally {
			$uri_obj destroy
			unset uri_obj
			if {[info exists query]} {
				unset query
			}
		}

		set use_keepalive	0
		foreach flag [split $flags {}] {
			switch -- $flag {
				N {set contype	"outbound"}
				A {set contype	"outbound_advertise"}
				K {set use_keepalive	1}
				
				default {
					log warning "Node::attempt_outbound_connection: invalid flag: ($flag)"
				}
			}
		}
		if {![info exists contype]} {
			set contype	"outbound"
		}

		try {
			netdgram::connect_uri $addr
		} on error {errmsg options} {
			log notice "m2::Node::constructor: error connecting to upstream: ($addr): $errmsg\n[dict get $options -errorinfo]"

			dict set outbound_connection_afterids $addr	[after \
					[expr {int($connection_retry * 1000)}] \
					[namespace code [list my _attempt_outbound_connection $addr]]]
		} on ok {con} {
			try {
				if {$io_threads > 0} {
					set chosen_tid	[my _pick_thread]
					$con teleport $chosen_tid
				} else {
					set chosen_tid	[thread::id]
					set con
				}
			} trap not_teleportable {} {
				set chosen_tid	[thread::id]
				set queue	[netdgram::queue new]
				$queue attach $con
			} on ok {teleported_con} {
				set con		$teleported_con
				set queue	[thread::send $chosen_tid [format {m2::_accept %s} [list $con]]]
			}
			set params	{}		;# !?
			set p	[m2::port new $contype [list \
						-server [self] \
						-use_keepalive $use_keepalive \
						-queue_mode $queue_mode \
						-filter $filter \
					] \
					$queue $chosen_tid $params]
			$p register_handler onclose \
					[namespace code [list my _attempt_outbound_connection $addr]]
			thread::send -async $chosen_tid [list m2::_activate $con]
		}
	}

	#>>>
	method _accept_inbound_pre {con args} { #<<<
		after idle [namespace code [list my _accept_inbound $con {*}$args]]
	}

	#>>>
	method _accept_inbound {con args} { #<<<
		log debug "node::_accept_inbound: con: ($con) args: ($args)"
		try {
			if {$io_threads > 0} {
				set chosen_tid	[my _pick_thread]
				$con teleport $chosen_tid
			} else {
				set chosen_tid	[thread::id]
				set con
			}
		} on ok {teleported_con} {
			set con		$teleported_con
			set queue	[thread::send $chosen_tid [format {m2::_accept %s} [list $con]]]
		} trap not_teleportable {} {
			set chosen_tid	[thread::id]
			set queue [netdgram::queue new]
			$queue attach $con
		}
		m2::port new inbound [list -server [self]] $queue $chosen_tid $args
		thread::send $chosen_tid [list m2::_activate $con]
	}

	#>>>
	method _pick_thread {} { #<<<
		my variable thread_idx
		incr thread_idx
		set thread_idx	[expr {$thread_idx % [dict size $threads]}]
		lindex [dict keys $threads] $thread_idx
	}

	#>>>
	method _puts {args} { #<<<
		puts {*}$args
	}

	#>>>
}



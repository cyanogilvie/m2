# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create webmodule::authwebmodule {
	variable {*}{
		modulename
		auth
		title
		icon
		page
		svc
		baseurl
		required_perms
		myhost
		httpd
		docroot
		init_script
		cleanup_script
		comp
		prkey_fn
	}

	constructor {args} { #<<<
		if {[self next] ne ""} next

		package require m2

		set settings		[dict merge {
			-auth				"auth"
			-myhost				""
			-myport				""
			-required_perms		{}
			-page				"main.html"
			-docroot			"docroot"
			-init_script		"init.js"
			-cleanup_script		"cleanup.js"
		} $args]

		dict for {key val} $settings {
			set [string range $key 1 end] $val
		}

		foreach reqf {modulename title icon prkey_fn} {
			if {![info exists $reqf]} {
				error "Must specify -$reqf"
			}
		}

		if {$myhost eq ""} {
			set myhost	[info hostname]
		}
		if {$myport eq ""} {
			set myport	[my _find_port]
		}

		if {$init_script eq ""} {
			set init_script		"init.js"
		}
		if {$cleanup_script eq ""} {
			set cleanup_script	"cleanup.js"
		}

		if {![info object isa object $auth]} {
			error "Value specified for -auth is not an object"
		}

		set svc		"authwebmodule/$modulename"

		set baseurl	"http://$myhost:$myport/"

		set httpd	[my make_httpd -port $myport -docroot $docroot]

		set comp	[m2::component new \
				-svc		$svc \
				-auth		$auth \
				-prkeyfn	$prkey_fn]

		$comp register_handler user_login [namespace code {my _check_perms}]

		$comp handler module_info [namespace code {my _module_info}]
		$comp handler http_get [namespace code {my _http_get}]
		oo::objdefine [self] forward handler [namespace which -command $comp] handler
	}

	#>>>
	destructor { #<<<
		if {[info exists auth] && [info object isa object $auth]} {
			[$auth signal_ref connected] detach_output \
					[namespace code {my _connected_changed}]
		}

		if {[info exists httpd] && [info object isa object $httpd]} {
			$httpd destroy
		}
	}

	#>>>

	method comp {} { #<<<
		set comp
	}

	#>>>
	method make_httpd {args} { #<<<
		webmodule::httpd new {*}$args
	}

	#>>>
	method _http_get {auth user seq data} { #<<<
		try {
			lassign $data relfile
			log debug "Got http_get request for \"$relfile\""
			set base	[string trimright $baseurl /]
			string map [list %h $base] [$httpd get $relfile]
		} trap not_found {errmsg} {
			$auth nack $seq $errmsg
		} trap forbidden {errmsg} {
			$auth nack $seq $errmsg
		} trap nack {errmsg} {
			$auth nack $seq $errmsg
		} on error {errmsg options} {
			log error "Error handling request: [dict get $options -errorinfo]"
			$auth nack $seq "Internal error"
		} on ok {res} {
			$auth ack $seq $res
		}
	}

	#>>>
	method _module_info {auth user seq data} { #<<<
		try {
			set init_fn			[file join $docroot $init_script]
			set cleanup_fn		[file join $docroot $cleanup_script]
			if {[file exists $init_fn]} {
				set init	[cflib::readfile $init_fn]
			} else {
				set init	""
			}
			if {[file exists $cleanup_fn]} {
				set cleanup	[cflib::readfile $cleanup_fn]
			} else {
				set cleanup	""
			}
			dict create \
					title			$title \
					icon			$icon \
					baseurl			$baseurl \
					page			$page \
					init			$init \
					cleanup			$cleanup \
					required_perms	$required_perms
		} trap nack {errmsg} {
			$auth nack $seq $errmsg
		} on error {errmsg options} {
			log error "Error handling request: [dict get $options -errorinfo]"
			$auth nack $seq "Internal error"
		} on ok {res} {
			$auth ack $seq $res
		}
	}

	#>>>
	method _check_perms {user} { #<<<
		set missing	{}
		foreach perm $required_perms {
			if {![$user perm $perm]} {
				lappend missing $perm
			}
		}
		if {[llength $missing] > 0} {
			throw deny "Required permission(s) missing: [join $missing {, }]"
		}
	}

	#>>>
	method _find_port {} { #<<<
		set taken	{8080 5300 5301 5302 5307 1234 1325 1236 1237}

		try {
			exec netstat -lnt
		} on ok {raw} {
			foreach line [split $raw \n] {
				lassign $line proto rxq txq localaddr remoteattr state

				if {
					$state ne "LISTEN" ||
					$proto ne "tcp"
				} continue

				lassign [split $localaddr :] ip port

				lappend taken $port
			}
		}

		# Find a random unused port between 1025 and 32767
		set random	{
			{} {
				set upper	32767
				set lower	1025
				expr {round(rand() * ($upper - $lower + 1) + $lower)}
			}
		}

		set patience	1000
		set candidate	[apply $random]
		while {$candidate in $taken} {
			set candidate	[apply $random]
			if {[incr patience -1] <= 0} {
				error "Ran out of patience searching for unused port to listen on"
			}
		}

		return $candidate
	}

	#>>>
}



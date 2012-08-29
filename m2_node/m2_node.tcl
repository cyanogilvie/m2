#!/usr/bin/env tclsh8.6

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

if {![info exists ::tcl::basekit]} {
	package require platform

	foreach platform [platform::patterns [platform::identify]] {
		set tm_path		[file join $env(HOME) .tbuild repo tm $platform]
		set pkg_path	[file join $env(HOME) .tbuild repo pkg $platform]
		if {[file exists $tm_path]} {
			tcl::tm::path add $tm_path
		}
		if {[file exists $pkg_path]} {
			lappend auto_path $pkg_path
		}
	}
}


package require Tcl 8.6
if {0} {
	# Force load the checked out version of m2 and netdgram
	proc find_latest {match base} {
		set matches	{}
		foreach fn [glob -nocomplain -type f [file join $base $match]] {
			lappend matches [list [file mtime $fn] $fn]
		}
		lindex [lsort -index 0 -integer $matches] end 1
	}

	proc find_ver fn {
		if {[regexp {.*-(.*).tm$} [file tail $fn] - ver]} {
			set ver
		} else {
			error "Couldn't parse version from $fn"
		}
	}

	foreach {pkg basedir fakever} {
		netdgram		/home/cyan/git/tcl/netdgram/tm/tcl/	0.9.2
		netdgram::tcp	/home/cyan/git/tcl/netdgram/tm/tcl/	0.9.2
		m2				/home/cyan/git/m2/tm/tcl/			0.43.2
	} {
		set pname_match	[string map {:: /} $pkg]-*.tm
		set latest		[find_latest $pname_match $basedir]
		set ver			[find_ver $latest]
		puts "Sourcing $latest"
		source $latest
		package provide $pkg $fakever
		puts "Loaded $pkg $ver (faked as $fakever) from $latest"
	}
} else {
	package require netdgram 0.9.10
	package require m2
}
package require cflib 1.14.0
package require logging
package require evlog 0.3
package require sop 1.5.1

cflib::config create cfg $argv {
	variable listen_on		{"tcp://:5300" "jssocket://:5301" "uds:///tmp/m2/5300.socket"}
	variable upstream		{}
	variable queue_mode		fancy
	variable debug			0
	variable daemon			0		;# Obsolete
	variable loglevel		notice
	variable evlog_uri		""
	variable io_threads		1
	variable admin_console	tcp://:5350
} /etc/codeforge/m2_node.conf

evlog connect_thread "m2_node [info hostname] [pid]" [cfg get evlog_uri]

logging::logger ::log [cfg get loglevel] \
		-hook {evlog event log.%level% {$msg}}
#proc ::log::puts args {}

if {[cfg get debug]} {
	proc ?? script {uplevel 1 $script}
} else {
	proc ?? args {}
}

cflib::termtitle "m2_node"

interp bgerror {} [list apply {
	{errmsg options} {
		#log error "$errmsg"
		log error [dict get $options -errorinfo]
		#array set o	$options
		#parray o
	}
}]

set here	[file dirname [file normalize [info script]]]
source [file join $here admin_console.tcl]

proc init {} { #<<<
	try {
		#m2::evlog create evlog
		m2::node create server \
				-listen_on	[cfg get listen_on] \
				-upstream	[cfg get upstream] \
				-queue_mode	[cfg get queue_mode] \
				-io_threads	[cfg get io_threads]

		if {[cfg @admin_console] ne ""} {
			Admin_console create admin_console
		}
	} on error {errmsg options} {
		log error "Could not start m2 node: $errmsg"
		?? {log error [dict get $options -errorinfo]}
		exit 1
	}
	log notice "Ready"
}

#>>>

coroutine coro_init init
vwait forever


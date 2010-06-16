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
package require netdgram 0.6.1
package require m2
package require cflib
package require logging
package require evlog

cflib::config create cfg $argv {
	variable listen_on		{"tcp://:5300" "jssocket://:5301" "uds:///tmp/m2/5300.socket"}
	variable upstream		{}
	variable queue_mode		fancy
	variable debug			0
	variable daemon			0		;# Obsolete
	variable loglevel		notice
	variable evlog_uri		""
} /etc/codeforge/m2_node.conf

evlog connect "m2_node [info hostname] [pid]" [cfg get evlog_uri]

logging::logger ::log [cfg get loglevel]

if {[cfg get debug]} {
	proc ?? {script} {uplevel 1 $script}
} else {
	proc ?? {args} {}
}

interp bgerror {} [list apply {
	{errmsg options} {
		#log error "$errmsg"
		log error [dict get $options -errorinfo]
		#array set o	$options
		#parray o
	}
}]


proc init {} { #<<<
	try {
		#m2::evlog create evlog
		m2::node create server \
				-listen_on	[cfg get listen_on] \
				-upstream	[cfg get upstream] \
				-queue_mode	[cfg get queue_mode]
	} on error {errmsg options} {
		log error "Could not start m2 node: $errmsg"
		?? {log error [dict get options -errorinfo]}
		exit 1
	}
	log notice "Ready"
}

#>>>

coroutine coro_init init
vwait forever


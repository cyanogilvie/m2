#!/usr/bin/env kbskit8.6

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require Tcl 8.6
package require m2
package require cflib

cflib::config create cfg $argv {
	variable listen_on		{"tcp://:5300" "jssocket://:5301" "uds:///tmp/m2/5300.socket"}
	variable upstream		{}
	variable daemon			1
	variable runas_user		"daemon"
	variable runas_group	"daemon"
}

proc log {lvl msg args} { #<<<
	puts $msg
}

#>>>

interp bgerror {} [list apply {
	{errmsg options} {
		log error "$errmsg"
		#array set o	$options
		#parray o
	}
}]


proc cleanup {} { #<<<
	if {[info object isa object m2]} {
		m2 destroy
	}
}

#>>>
proc init {} { #<<<
	m2::node create server \
			-listen_on	[cfg get listen_on] \
			-upstream	[cfg get upstream]
}

#>>>

if {[cfg get daemon]} {
	dutils::daemon create daemon \
			-name			"m2_node" \
			-as_user		[cfg get runas_user] \
			-as_group		[cfg get runas_group] \
			-gen_pid_file	{return "/var/tmp/m2_node.pid"}

	proc log {lvl msg args} { #<<<
		daemon log $lvl $msg {*}$args
	}

	#>>>

	set cmd	[lindex [cfg rest] 0]
	if {$cmd eq ""} {
		set cmd		"start"
	}

	daemon apply_cmd $cmd

	daemon cleanup {
		cleanup
	}

	daemon fork {
		dutils::umask 022
		init
	}
} else {
	try {
		init
	} on error {errmsg options} {
		log error "Could not start m2 node: $errmsg"
		exit 1
	}

	coroutine main apply {
		{} {
			puts "Ready"
			vwait ::forever
		}
	}
}



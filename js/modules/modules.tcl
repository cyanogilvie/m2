# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require m2
package require cflib

cflib::config create cfg $argv {
	variable uri			"uds:///tmp/m2/5300.socket"
	variable daemon			1
	variable runas_user		"daemon"
	variable runas_group	"daemon"
}


proc log {lvl msg args} { #<<<
	puts $msg
}

#>>>

proc list_modules {} { #<<<
	set modules	[dict create]

	dict set modules "bpm2" {
		title	"BPM2"
		svc		"bpm2"
		icon	"images/BPM2.png"
	}
	dict set modules "tickertape" {
		title	"Tickertape"
		svc		"tickertape"
		icon	"images/tickertape.png"
	}
	dict set modules "dashboard" {
		title	"Dashboard"
		svc		"dashboard"
		icon	"images/dashboard.png"
	}

	return $modules
}

#>>>
proc handle_modules {seq data} { #<<<
	try {
		log debug "Got modules request: ($data)"
		set rest	[lassign $data op]

		switch -- $op {
			"list" {
				list_modules
			}

			default {
				throw nack "Invalid request \"$op\""
			}
		}
	} trap nack {errmsg} {
		api nack $seq $errmsg
	} on error {errmsg options} {
		log error [dict get $options -errorinfo]
		api nack $seq "Internal error"
	} on ok {res} {
		api ack $seq $res
	}
}

#>>>
proc init {} { #<<<
	m2::api2 create api -uri [cfg get uri]
	[api signal_ref "connected"] attach_output [list apply {
		{newstate} {
			if {$newstate} {
				api handle_svc "modules" handle_modules
			} else {
				api handle_svc "modules" ""
			}
		}
	}]
}

#>>>
proc cleanup {} { #<<<
	if {[info object isa object api]} {
		api destroy
	}
}

#>>>

if {[cfg get daemon]} {
	dutils::daemon create daemon \
			-name			"m2modules" \
			-as_user		[cfg get runas_user] \
			-as_group		[cfg get runas_group] \
			-gen_pid_file	{return "/var/tmp/m2modules.pid"}

	proc log {lvl msg args} { #<<<
		daemon log $lvl $msg {*}$args
	}

	#>>>

	set cmd	[lindex [cfg rest] 0]
	if {$cmd eq ""} {
		set cmd	"start"
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
	coroutine coro_init init
	coroutine coro_main vwait ::forever
}


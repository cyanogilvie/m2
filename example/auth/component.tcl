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

package require m2
package require cflib
package require sop
package require dsl
package require logging
package require evlog

cflib::config create cfg $argv {
	variable uri			"tcp://localhost:5300"
	variable pbkey			"/etc/codeforge/authenticator/keys/env/authenticator.pb"
	variable debug			0
	variable loglevel		notice
	variable evlog_uri		""
}

evlog connect "[file tail [info script]] [info hostname] [pid]" [cfg get evlog_uri]

logging::logger ::log [cfg get loglevel]

if {[cfg get debug]} {
	proc ?? {script} {uplevel 1 $script}
} else {
	proc ?? {args} {}
}

m2::authenticator create auth -uri [cfg get uri] -pbkey [cfg get pbkey]

set report_signal_change [list {signal newstate} {
	log debug "signal $signal change: [expr {$newstate ? "true" : "false"}]"
}]
dict for {signal sigobj} [auth signals_available] {
	[auth signal_ref $signal] attach_output [list apply $report_signal_change $signal]
}

m2::component create comp \
		-svc		examplecomponent \
		-auth		auth \
		-prkeyfn	/etc/codeforge/authenticator/keys/env/examplecomponent.pr \
		-login		1

proc pinger {} {
	set jmid	[auth unique_id]
	log notice "Starting new pinger ($jmid)"
	auth chans register_chan $jmid [list apply {
		{coro args} {$coro $args}
	} [info coroutine]]

	set ping_seq	0
	set afterid	[after 1000 [list [info coroutine] ping]]
	while {1} {
		set rest	[lassign [yield] wakeup_reason]

		switch -- $wakeup_reason {
			join {
				lassign $rest seq
				log debug "Joining $seq to ping ($jmid)"
				auth pr_jm $jmid $seq "init $ping_seq"
			}

			ping {
				log notice "Sending ping on $jmid"
				auth jm $jmid "ping [incr ping_seq]"
				set afterid	[after 1000 [list [info coroutine] ping]]
			}

			cancelled {
				after cancel $afterid; set afterid	""
				log notice "All destinations for $jmid disconnected"
				break
			}

			req {
				lassign $rest rseq rprev_seq rdata
				auth nack $rseq "Requests not supported on this channel"
			}

			default {
				log error "Unexpected wakeup_reason: ($wakeup_reason)"
			}
		}
	}

	log notice "Wrapping up pinger"
}

comp handler "hello" [list apply {
	{auth user seq rdata} {
		if {[info commands coro_pinger] ne "coro_pinger"} {
			coroutine coro_pinger pinger
		}
		coro_pinger [list join $seq]
		auth ack $seq "world, [$user name]: ($rdata)"
	}
}]

vwait forever

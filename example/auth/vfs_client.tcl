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
package require cachevfs
package require logging
package require evlog

cflib::config create cfg $argv {
	variable uri		tcp://localhost:5300
	variable pbkey		/etc/codeforge/authenticator/keys/env/authenticator.pb
	variable loglevel	notice
	variable debug		0
	variable evlog_uri	""
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


[auth signal_ref login_allowed] attach_output [list apply {
	{newstate} {
		if {$newstate} {
			set ok	[auth login "cyan@cf" "foo"]
			log notice "login ok? $ok"
			if {!($ok)} {
				log error "Login failed"
				exit
			}
		}
	}
}]


proc hello_resp {msg} {
	switch -- [dict get $msg type] {
		ack {
			log notice "got ack: \"[dict get $msg data]\""
		}

		nack {
			log notice "got nack: \"[dict get $msg data]\""
		}

		pr_jm {
			log notice "got pr_jm [dict get $msg seq]: \"[dict get $msg data]\""
		}

		jm {
			log notice "got jm [dict get $msg seq]: \"[dict get $msg data]\""
		}

		jm_can {
			log notice "got jm_disconnect [dict get $msg seq]: \"[dict get $msg data]\""
		}

		default {
			log warning "Unexpected response type to hello request: \"[dict get $msg type]\""
		}
	}
}


set connector	[auth connect_svc "examplecomponent"]
[$connector signal_ref authenticated] attach_output [list apply {
	{newstate} {
		global connector

		if {$newstate} {
			log notice "Authenticated to examplecomponent"
			$connector req_async "hello" "and things" hello_resp
		} else {
			log notice "Not authenticated to examplecomponent"
		}
	}
}]
set report_connector_signal_change [list {signal newstate} {
	log debug "connector signal $signal change: [expr {$newstate ? "true" : "false"}]"
}]
dict for {signal sigobj} [$connector signals_available] {
	[$connector signal_ref $signal] attach_output [list apply $report_connector_signal_change $signal]
}

cachevfs::mount create vfs_testpool -connector $connector -cachedir cachedir \
		-pool testpool -local virt
[vfs_testpool signal_ref mounted] attach_output [list apply {
	{newstate} {
		puts "Cachevfs mounted: $newstate"
	}
}]

vwait forever

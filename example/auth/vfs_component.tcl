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
package require cachevfs
package require datasource
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

cachevfs::backend create cachevfs -comp comp
cachevfs register_pool testpool [file join [pwd] pools testpools]

ds::dschan_backend create test_ds_backend -comp comp -tag test_ds \
		-headers {ID Foo Bar Baz}
test_ds_backend register_pool "hello" [list apply {
	{user pool extra} {
		log debug "Got check_cb for hello pool: user: ([$user name]), pool: ($pool), extra: ($extra)"
		return 1
	}
}]
test_ds_backend add_item "hello" {1 foo1 bar1 baz1}
test_ds_backend add_item "hello" {2 foo2 bar2 baz2}
test_ds_backend add_item "hello" {3 foo3 bar3 baz3}
set i	4
for {set i 4} {$i < 128 + 64 + 32 + 0*16 + 0*8 + 1*4 + 0*2 + 1*1 - 2} {incr i} {
	test_ds_backend add_item "hello" [list $i "auto item $i" "bar" "baz"]
}

set seq	$i
proc append_element {} {
	test_ds_backend add_item "hello" [list [incr ::seq] [clock format [clock seconds]] "more bar" "more baz"]
	after 10000 append_element
}

append_element

comp handler "hello" [list apply {
	{auth user seq rdata} {
		auth ack $seq "world, [$user name]: ($rdata)"
	}
}]

vwait forever

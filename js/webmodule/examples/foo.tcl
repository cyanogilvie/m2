# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require webmodule
package require m2
package require cflib

cflib::config create cfg $argv {
	variable uri		"tcp://localhost:5300"
	variable pbkey		"/etc/codeforge/authenticator/keys/authenticator.pub"
	variable daemon		"yes"
	variable runas_user		"daemon"
	variable runas_group	"daemon"
	variable httpd_port		""
	variable httpd_host		""
}

proc log {lvl msg args} { #<<<
	puts $msg
}

#>>>

proc init {} { #<<<
	m2::authenticator create auth -uri [cfg get uri] -pbkey [cfg get pbkey]

	webmodule::webmodule create webmodule \
			-auth		auth \
			-modulename	"foo" \
			-title		"Foo Example Module" \
			-icon		"images/fooicon.png" \
			-myport		[cfg get httpd_port] \
			-myhost		[cfg get httpd_host]
}

#>>>
proc cleanup {} { #<<<
	if {[info object isa object webmodule]} {
		webmodule destroy
	}

	if {[info object isa object auth]} {
		auth destroy
	}
}

#>>>

if {[cfg get daemon]} {
	package require daemon 0.6

	dutils::daemon create daemon \
			-name			"webmodule_foo" \
			-as_user		[cfg get runas_user] \
			-as_group		[cfg get runas_group] \
			-gen_pid_file	{return "/var/tmp/webmodule_foo"}

	proc log {lvl msg args} { #<<<
		uplevel [list daemon log $lvl $msg $args]
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
		init
	}
} else {
	coroutine coro_init init
	vwait ::forever
}


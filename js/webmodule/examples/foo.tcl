# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require webmodule 0.2
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

	oo::define webmodule::webmodule method make_httpd {args} {
		set obj	[webmodule::httpd new {*}$args]
		oo::objdefine $obj method got_req {req} {
			log notice "Intercepted got_req"
			set uri	[$req request_uri]
			set r	[$uri as_dict]
			set params	[$uri query_decode [dict get $r query]]
			log notice "Got request: [dict get $r path], ($params)"
			log notice "Passing through to original handler"
			try {
				next $req
			} finally {
				log notice "Finished pass-through"
			}
		}
		return $obj
	}

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


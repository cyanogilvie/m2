#!/usr/bin/env tclsh8.6

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

package require m2
package require cflib

cflib::config create cfg $argv {
	variable uri			"tcp://localhost:5300"
	variable crypto_devmode 0
	variable pbkey			"/etc/codeforge/authenticator/keys/env/authenticator.pb"
}


m2::authenticator create auth -uri [cfg get uri] -pbkey [cfg get pbkey]

[auth signal_ref login_allowed] attach_output [list apply {
	{newstate} {
		if {$newstate} {
			set ok	[auth login "cyan@cf" "foo"]
			puts "login ok? $ok"
			if {!($ok)} {
				puts stderr "Login failed"
				exit
			}
		}
	}
}]


set connector	[auth connect_svc "examplecomponent"]
[$connector signal_ref authenticated] attach_output [list apply {
	{newstate} {
		if {$newstate} {
			puts "Authenticated to examplecomponent"
			coroutine coro_[incr ::coro_seq] apply {
				{} {
					set rep	[$::connector req "hello" "and things"]
					puts "Got: ($rep)"
				}
			}
		} else {
			puts "Not authenticated to examplecomponent"
		}
	}
}]

proc getlock {} {
	global connector lockobj

	puts "getlock foo"
	set lockobj	[m2::locks::client new \
			-tag		testlocks \
			-connector	$connector \
			-id			someid]

	puts "getlock bar"
	[$lockobj signal_ref locked] attach_output [list apply {
		{newstate} {
			global lockobj
			puts "Lock state: $newstate"
			if {$newstate} {
				try {
					$lockobj lock_req testreq "hello, world"
				} on ok {result} {
					puts "Got lock_req result: ($result)"
				} on error {errmsg} {
					puts "Lock req failed: ($errmsg)"
				}
			}
		}
	}]
	puts "getlock baz"
}

coroutine coro_[incr ::coro_seq] getlock

coroutine coro_main vwait forever

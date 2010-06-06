package require m2
package require cflib
package require cachevfs

cflib::config create cfg $argv {
	variable uri			"tcp://localhost:5300"
	variable crypto_devmode 0
	variable pbkey			"/etc/codeforge/authenticator/keys/env/authenticator.pb"
}


m2::authenticator create auth -uri [cfg get uri] -pbkey [cfg get pbkey]

set report_signal_change [list {signal newstate} {
	puts "signal $signal change: [expr {$newstate ? "true" : "false"}]"
}]
dict for {signal sigobj} [auth signals_available] {
	[auth signal_ref $signal] attach_output [list apply $report_signal_change $signal]
}


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
set report_connector_signal_change [list {signal newstate} {
	puts "connector signal $signal change: [expr {$newstate ? "true" : "false"}]"
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

coroutine coro_main vwait forever

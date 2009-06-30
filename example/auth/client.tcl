package require m2
package require cflib

cflib::config create cfg $argv {
	variable uri			"tcp://localhost:5300"
	variable crypto_devmode 0
	variable pbkey			"/etc/codeforge/authenticator/authenticator.pub"
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
		}
	}
}]


coroutine coro_main vwait forever

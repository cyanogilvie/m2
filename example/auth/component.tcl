package require m2
package require cflib
package require sop
package require dsl
package require cachevfs

cflib::config create cfg $argv {
	variable uri			"tcp://localhost:5300"
	variable pbkey			"/etc/codeforge/authenticator/keys/authenticator.pb"
}


m2::authenticator create auth -uri [cfg get uri] -pbkey [cfg get pbkey]

set report_signal_change [list {signal newstate} {
	puts "signal $signal change: [expr {$newstate ? "true" : "false"}]"
}]
dict for {signal sigobj} [auth signals_available] {
	[auth signal_ref $signal] attach_output [list apply $report_signal_change $signal]
}

m2::component create comp \
		-svc		"examplecomponent" \
		-auth		auth \
		-prkeyfn	"/etc/codeforge/authenticator/keys/examplecomponent.pr"  \
		-login		0

cachevfs::backend create cachevfs -comp comp
cachevfs register_pool testpool [file join [pwd] pools testpools]

comp handler "hello" [list apply {
	{auth user seq rdata} {
		auth ack $seq "world, [$user name]: ($rdata)"
	}
}]

coroutine coro_main vwait forever

package require m2
package require cflib
package require sop
package require dsl

cflib::config create cfg $argv {
	variable uri		"tcp://localhost:5300"
	variable pbkey		"authenticator.pub"
}

m2::authenticator create auth -uri [cfg get uri] -pbkey [cfg get pbkey]

set report_signal_change [list {signal newstate} {
	puts "signal $signal change: [expr {$newstate ? "true" : "false"}]"
}]
dict for {signal sigobj} [auth signals_available] {
	[auth signal_ref $signal] attach_output [list apply $report_signal_change $signal]
}

component create comp \
		-sv			"examplecomponent" \
		-auth		auth \
		-prkeyfn	"examplecomponent.priv" \
		-login		0

comp handler "hello" {auth user seq rdata} {
	auth ack $seq "world"
}

coroutine main apply {
	{} {
		vwait ::forever
	}
}

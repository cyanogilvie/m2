proc log {lvl msg args} {puts $msg}
proc ?? args {}

package require m2

m2::authenticator create auth -uri tcp:// \
		-pbkey /etc/codeforge/authenticator/keys/env/authenticator.pb

proc resp msg {
	switch -- [dict get $msg type] {
		ack {
			puts "Got response: [dict get $msg data]"
		}

		nack {
			puts stderr "Request problem: [dict get $msg data]"
			exit 1
		}

		default {
			puts stderr "Unexpected response type to hello request: [dict get $msg type]"
			exit 1
		}
	}
}

set connector [auth connect_svc hello]
[$connector signal_ref authenticated] attach_output [list apply {
	newstate {
		puts "connector authenticated state: $newstate"
		global connector
		if {$newstate} {
			$connector req_async hello "hello, world" resp
		}
	}
}]

[auth signal_ref login_allowed] attach_output [list apply {
	newstate {
		puts "login_allowed state: $newstate"
		if {$newstate} {
			auth login test@cf test
		}
	}
}]

vwait forever

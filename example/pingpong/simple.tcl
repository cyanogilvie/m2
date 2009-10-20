package require m2
package require cflib

cflib::config create cfg $argv {
	variable uri		"tcp://localhost:5300"
}

m2::api2 create m2 -uri [cfg get uri]

proc ping_resp {msg_data} {
	switch -- [dict get $msg_data type] {
		ack {
			puts "Request succeeded: [dict get $msg_data data]"
			exit 0
		}

		nack {
			puts "Request failed: [dict get $msg_data data]"
			exit 2
		}

		pr_jm - jm - jm_can {
			puts "Not expecting response type: \"[dict get $msg_data type]\""
		}

		default {
			puts "Invalid response type: \"[dict get $msg_data type]\""
		}
	}
}


proc call_ping {} {
	m2 req "ping" "This is the payload" ping_resp
}


[m2 svc_signal "ping"] attach_output [list apply {
	{newstate} {
		if {$newstate} {
			puts "connected"
			call_ping
		} else {
			puts "not connected"
		}
	}
}]

vwait ::forever

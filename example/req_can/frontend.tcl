# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require m2
package require cflib
package require Tk
package require sop

cflib::config create cfg $argv {
	#variable uri	"uds:///tmp/m2/5300.socket"
	variable uri	"tcp://:5300"
}

wm title . "Req_can Test Frontend"

ttk::setTheme clam

puts "Trying to connect to [cfg get uri]"
m2::api2 create m2  -uri [cfg get uri]

sop::signal new in_flight
sop::gate new can_req -mode and
$can_req attach_input [m2 svc_signal req_can_test]
$can_req attach_input $in_flight inverted

ttk::button .req -text "Request" -command [list apply {
	{} {
		$::in_flight set_state 1
		m2 req "req_can_test" "" [list apply {
			{msg} {
				switch -- [dict get $msg type] {
					ack {
						puts "got ack: ([dict get $msg data])"
						$::in_flight set_state 0
					}

					nack {
						puts "got nack: ([dict get $msg data])"
						$::in_flight set_state 0
					}

					default {
						puts stderr "Unexpected response type: ([dict get $msg type])"
					}
				}
			}
		}]
	}
}]
pack .req

[m2 signal_ref connected] attach_output [list apply {
	{newstate} {
		puts "Connected: $newstate"
	}
}]
[m2 svc_signal req_can_test] attach_output [list apply {
	{newstate} {
		puts "svc available: $newstate"
	}
}]

$can_req attach_output [list apply {
	{newstate} {
		if {$newstate} {
			.req state {!disabled}
		} else {
			.req state {disabled}
		}
	}
}]

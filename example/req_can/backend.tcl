# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require m2
package require cflib
package require Tk

cflib::config create cfg $argv {
	variable uri	"tcp://:5300"
}

wm title . "Req_can Test Backend"

ttk::setTheme clam

puts "Trying to connect to [cfg get uri]"
m2::api2 create m2 -uri [cfg get uri]

[m2 signal_ref connected] attach_output [list apply {
	{newstate} {
		puts "Connected: $newstate"
		if {$newstate} {
			m2 handle_svc "req_can_test" [list apply {
				{seq data} {
					ttk::frame .f${seq}
					ttk::button .f${seq}.ack -text "Ack $seq" -command [list apply {
						{seq} {
							m2 ack $seq ""
							destroy .f${seq}
						}
					} $seq]
					ttk::button .f${seq}.nack -text "Nack $seq" -command [list apply {
						{seq} {
							m2 nack $seq ""
							destroy .f${seq}
						}
					} $seq]
					pack .f${seq}.ack .f${seq}.nack -fill both -expand true -side left
					pack .f${seq} -side top
				}
			}]
		} else {
			m2 handle_svc "req_can_test" ""
		}
	}
}]


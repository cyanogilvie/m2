package require m2

m2::api2 create m2 -uri tcp://

proc handle_helloworld {seq data} {
	m2 ack $seq "echo: ($data)"
}

[m2 signal_ref connected] attach_output [list apply {
	{newstate} {
		if {$newstate} {
			m2 handle_svc helloworld handle_helloworld
		} else {
			m2 handle_svc helloworld ""
		}
	}
}]

vwait forever

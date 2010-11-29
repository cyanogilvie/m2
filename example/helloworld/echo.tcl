package require m2

m2::api2 create m2 -uri tcp://

proc handle_echo {seq data} {
	m2 ack $seq $data
}

[m2 signal_ref connected] attach_output [list apply {
	{newstate} {
		if {$newstate} {
			m2 handle_svc echo handle_echo
		} else {
			m2 handle_svc echo ""
		}
	}
}]

vwait forever

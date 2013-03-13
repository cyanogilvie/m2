package require m2

m2::api2 create m2 -uri tcp://

proc resp msg {
	if {[dict get $msg type] ne "ack"} {
		puts stderr "Request failed: [dict get $msg data]"
		exit 1
	}
	puts [dict get $msg data]
	exit 0
}

m2 waitfor connected
m2 req helloworld "hello, world" resp

vwait forever

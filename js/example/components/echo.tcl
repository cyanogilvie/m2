# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require m2
package require cflib

cflib::config create cfg $argv {
	variable uri		"tcp://localhost:5300"
	variable svc		"echo"
}

proc handle_svc {seq data} { #<<<
	puts "Got request for [cfg get svc], [string length $data] bytes, hex: [binary encode base64 $data]"
	puts "data: ($data)"
	cflib::writefile /tmp/raw.png $data binary
	m2 ack $seq $data
	#m2 ack $seq [cflib::readfile /home/cyan/git/fnb/dashboard/images-src/indicator_red.png binary]
}

#>>>

m2::api2 create m2 -uri [cfg get uri]

[m2 signal_ref connected] attach_output [list apply {
	{newstate} {
		puts "M2 connected: $newstate"
		if {$newstate} {
			m2 handle_svc [cfg get svc] handle_svc
			puts "Advertised service [cfg get svc]"
		} else {
			m2 handle_svc [cfg get svc] ""
			puts "Revoked service [cfg get svc]"
		}
	}
}]

vwait ::forever


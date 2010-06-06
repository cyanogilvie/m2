# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require platform
foreach platform [platform::patterns [platform::identify]] {
	set tm_path		[file join $env(HOME) .tbuild repo tm $platform]
	set pkg_path	[file join $env(HOME) .tbuild repo pkg $platform]

	if {[file exists $tm_path]} {
		tcl::tm::path add $tm_path
	}
	if {[file exists $pkg_path]} {
		lappend auto_path $pkg_path
	}
}

package require m2
package require cflib

cflib::config create cfg $argv {
	variable uri			"tcp://localhost"
	variable svc			"newimgview"
}

m2::api2 create m2 -uri [cfg get uri]

# next_image generator <<<
coroutine next_image apply {
	{} {
		set here	[file dirname [file normalize [info script]]]
		set imgdir	[file normalize [file join $here .. imgview images]]
		set files	{}
		yield
		while {1} {
			if {[llength $files] == 0} {
				set files	[glob -nocomplain -type f [file join $imgdir *]]
				if {[llength $files] == 0} {
					puts stderr "No files"
					exit 2
				}
			}
			set files	[lassign $files next]
			yield $next
		}
	}
}

#>>>

proc handle_svc {seq data} { #<<<
	lassign $data op
	puts "Got $op request"
	try {
		switch -- $op {
			"next_image" {
				m2 ack $seq [cflib::readfile [next_image] binary]
			}

			default {
				throw nack "Invalid operation ($op)"
			}
		}
	} trap nack {errmsg} {
		m2 nack $seq $errmsg
	} on error {errmsg options} {
		puts "Unhandled error in handle_svc: [dict get $options -errorinfo]"
		m2 nack $seq "Internal error"
	}
}

#>>>

[m2 signal_ref connected] attach_output [list apply {
	{newstate} {
		puts "M2 connected: $newstate"
		if {$newstate} {
			m2 handle_svc [cfg get svc] handle_svc
		} else {
			m2 handle_svc [cfg get svc] ""
		}
	}
}]

vwait forever

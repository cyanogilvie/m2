# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require platform
foreach platform [platform::patterns [platform::identify]] {
	set tm_path		[file join $env(HOME) .tbuild repo tm $platform]
	set pkg_path	[file join $env(HOME) .tbuild repo pkg $platform]
	if {[file exists $tm_path]} {tcl::tm::path add $tm_path}
	if {[file exists $pkg_path]} {lappend auto_path $pkg_path}
}

package require m2
package require cflib
package require Pixel
package require Pixel_devil

cflib::config create cfg $argv {
	variable uri			"tcp://localhost"
	variable slideshow_time	3.0
}

m2::api2 create m2 -uri [cfg get uri]

proc cleanup {} { #<<<
	proc cleanup {} {}
}

#>>>

proc display_image {imgdata} { #<<<
	global picture

	puts "Loading new image: [string length $imgdata] bytes"
	try {
		pixel::devil::load_image_from_var $imgdata
	} on error {errmsg options} {
		puts stderr "Error loading image: $errmsg"
		return
	} on ok {pmap} {}

	lassign [pixel::pmap_info $pmap] w h

	puts "   new image dimentions: $w x $h"

	#dict set picture aspect [expr {double($w) / $h}]
}

#>>>
proc load_next_image {} { #<<<
	if {![[m2 svc_signal "newimgview"] state]} {
		puts stderr "Can't request next_image: newimgview service is not available"
		return
	}
	puts "Requesting next_image"
	m2 req newimgview [list "next_image"] [list apply {
		{msg} {
			puts "Got [dict get $msg type] response"

			switch -- [dict get $msg type] {
				ack {
					puts "Got data: [string length [dict get $msg data]]"
					display_image [dict get $msg data]
				}

				nack {
					puts stderr "newimgview next_image nack: [dict get $msg data]"
				}

				default {
					puts stderr "Unexpected response type to newimgview next_image request: ([dict get $msg type])"
				}
			}
		}
	}]
}

#>>>

# Slideshow <<<
coroutine slideshow apply {
	{} {
		set afterid	""
		while {1} {
			load_next_image
			set afterid	[after [expr {
				round([cfg get slideshow_time] * 1000.0)
			}] [list [info coroutine]]]

			yield
			after cancel $afterid
		}
	}
}
# Slideshow >>>

vwait forever

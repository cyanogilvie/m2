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
package require Pixel
package require Pixel_sdl
package require Pixel_fonts
#lappend auto_path [file join $env(HOME) .tbuild repo pkg linux-glibc2.10-x86_64]
package require Pixel_gl 0.3.0
package require Pixel_ttf 3.2.0
package require Pixel_svg_cairo
package require Pixel_devil
namespace eval pixel::gl {
	namespace export *
}
namespace import pixel::gl::*
namespace import tcl::mathop::*

#namespace path [list {*}[namespace path] ::pixel::gl ::tcl::mathop]

cflib::config create cfg $argv {
	variable uri			"tcp://localhost"
	variable width			1024
	variable height			768
	variable slideshow_time	3.0
}

m2::api2 create m2 -uri [cfg get uri]

set scr		[pixel::sdl::setup_screen [cfg get width] [cfg get height] 32 {SDL_ANYFORMAT SDL_OPENGL}]

glewInit
if {![glewIsSupported "GL_VERSION_2_0"]} {
	puts stderr "GL version 2.0 not supported"
	exit 2
}

glEnable GL_BLEND
glMatrixMode GL_MODELVIEW
glLoadIdentity
glClearColor 0.0 0.0 0.0 0.0

proc shader_program {vert_fn frag_fn} { #<<<
	#namespace path [list {*}[namespace path] ::pixel::gl ::tcl::mathop]

	set p	[glCreateProgram]
	set v	[glCreateShader GL_VERTEX_SHADER]
	glShaderSource $v [cflib::readfile $vert_fn]
	try {
		glCompileShader $v
	} trap {GL COMPILE} {errmsg options} {
		puts stderr "Could not complile vertex shader \"$vert_fn\":\n$errmsg"
		exit 1
	}
	glAttachShader $p $v

	set f	[glCreateShader GL_FRAGMENT_SHADER]
	glShaderSource $f [cflib::readfile $frag_fn]
	try {
		glCompileShader $f
	} trap {GL COMPILE} {errmsg options} {
		puts stderr "Could not compile fragment shader \"$frag_fn\":\n$errmsg"
		exit 1
	}
	glAttachShader $p $f

	glLinkProgram $p
	if {![glValidateProgram $p]} {
		puts stderr "Could not link shader program:\n[glGetProgramInfoLog $p]"
		exit 1
	}

	list $p $v $f
}

#>>>

lassign [shader_program "imgview2.vert" "imgview2.frag"] p v f
puts "Program validation:\n[glGetProgramInfoLog $p]"
glUseProgram $p

set uniform	[dict create]
dict set uniform Tex0	[glGetUniformLocation $p Tex0]

# Setup picture stuff <<<
lassign [glGenTextures 1] imgtex
glActiveTexture GL_TEXTURE0
glBindTexture GL_TEXTURE_2D $imgtex
glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_S GL_CLAMP
glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_T GL_CLAMP
glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_LINEAR
glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_LINEAR

proc make_picture_quad {aspect} { #<<<
	#namespace path [list {*}[namespace path] ::pixel::gl ::tcl::mathop]
	global width height imgtex

	set area_top	[cfg get height]
	set area_bot	0
	set area_left	0
	set area_right	[cfg get width]

	set area_width	[- $area_right $area_left]
	set area_height	[- $area_top $area_bot]

	set area_aspect	[expr {double($area_width) / $area_height}]
	if {$aspect > $area_aspect} {
		# Width limited
		set quad_width	[cfg get width]
		set quad_height	[expr {$quad_width / double($aspect)}]
	} else {
		# Height limited
		set quad_height	[cfg get height]
		set quad_width	[expr {$quad_height * $aspect}]
	}

	set vpad	[expr {($area_height - $quad_height) / 2.0}]
	set hpad	[expr {($area_width - $quad_width) / 2.0}]

	set top		[- $area_top $vpad]
	set bottom	[+ $area_bot $vpad]
	set left	[+ $area_left $hpad]
	set right	[- $area_right $hpad]

	set quad	[glGenList]
	glNewList $quad
	glBegin GL_QUADS
	glActiveTexture GL_TEXTURE0
	glBindTexture GL_TEXTURE_2D $imgtex

	# Top left
	glMultiTexCoord2f GL_TEXTURE0 0.0 0.0
	glVertex3f $left $top 0.0

	# Top right
	glMultiTexCoord2f GL_TEXTURE0 1.0 0.0
	glVertex3f $right $top 0.0

	# Bottom right
	glMultiTexCoord2f GL_TEXTURE0 1.0 1.0
	glVertex3f $right $bottom 0.0

	# Bottom left
	glMultiTexCoord2f GL_TEXTURE0 0.0 1.0
	glVertex3f $left $bottom 0.0

	glEnd
	glEndList

	return $quad
}

#>>>

coroutine get_aspect_quad apply {
	{} {
		set quads	[dict create]
		lassign [yield] aspect
		while {1} {
			if {![dict exists $quads $aspect]} {
				dict set quads $aspect [make_picture_quad $aspect]
			}
			lassign [yield [dict get $quads $aspect]] aspect
		}
	}
}

# Setup picture stuff >>>

proc cleanup {} { #<<<
	#namespace path [list {*}[namespace path] ::pixel::gl ::tcl::mathop]

	glDeleteShader $::v
	glDeleteShader $::f
	glDeleteShader $::p
	unset ::scr
	proc cleanup {} {}
}

#>>>

# Bind SDL events <<<
pixel::sdl::bind_events key [list apply {
	{name ev} {
		puts "Event: key _____________"
		array set e $ev
		parray e
		unset e
		puts "------------------------"

		dict with ev {}
		if {$state eq "SDL_PRESSED"} {
			if {$ascii eq "q" || $sym eq 27} {
				try {
					cleanup
				} on error {errmsg options} {
					puts stderr "Error cleaning up: [dict get $options -errorinfo]"
				}
				exit
			} else {
				switch -- $keyname {
					"right" {
						slideshow
					}
				}
			}
		}
	}
}]

pixel::sdl::bind_events expose [list apply {
	{name ev} {
		pixel::sdl::do_frame $::scr
	}
}]

pixel::sdl::bind_events quit [list apply {
	{name ev} {
		cleanup
		exit 0
	}
}]

# Bind SDL events >>>

proc display_image {imgdata} { #<<<
	global picture imgtex
	#namespace path [list {*}[namespace path] ::pixel::gl ::tcl::mathop]

	puts "Loading new image: [string length $imgdata] bytes"
	try {
		pixel::devil::load_image_from_var $imgdata
	} on error {errmsg options} {
		puts stderr "Error loading image: $errmsg"
		return
	} on ok {pmap} {}

	lassign [pixel::pmap_info $pmap] w h

	puts "   new image dimentions: $w x $h"

	dict set picture aspect [expr {double($w) / $h}]

	glBindTexture GL_TEXTURE_2D $imgtex
	glTexImage2D GL_TEXTURE_2D 0 0 $pmap
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
proc draw_screen {} { #<<<
	global width height uniform picture
	#namespace path [list {*}[namespace path] ::pixel::gl ::tcl::mathop]

	glClear GL_COLOR_BUFFER_BIT GL_DEPTH_BUFFER_BIT
	glMatrixMode GL_PROJECTION
	glLoadIdentity
	gluOrtho2D 0 [cfg get width] 0 [cfg get height]

	if {[info exists picture]} {
		glBlendFunc GL_ONE GL_ZERO
		glUniform1i [dict get $uniform Tex0] 0
		glCallList [get_aspect_quad [dict get $picture aspect]]
	}

	glFlush
	glFinish
	pixel::sdl::gl_swapbuffers
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

coroutine mainloop apply {
	{} {
		try {
			while {1} {
				set framestart	[clock microseconds]
				pixel::sdl::dispatch_events
				update
				draw_screen
				set frameend	[clock microseconds]
				set target		[expr {1 / 30.0}]
				set elapsed		[expr {($frameend - $framestart) / 1000000.0}]
				set remaining	[expr {max($target - $elapsed, 0.001)}]
				#puts "remaining: ($remaining)"
				after [expr {round($remaining * 1000)}] [list [info coroutine]]
				yield
			}
		} on error {errmsg options} {
			puts "Uncaught error: [dict get $options -errorinfo]"
			exit 1
		}
	}
}

vwait forever

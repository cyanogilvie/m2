#!/usr/bin/env tclsh8.6
# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

if {[file system [info script]] eq "native"} {
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
}

package require tclreadline
package require cflib
package require logging 0.3
package require netdgram

cflib::config create cfg $argv {
	variable debug		0
	variable loglevel	notice
	variable uri		tcp://localhost:5350
} /etc/codeforge/m2_admin_console.conf

if {[cfg @debug]} {
	proc ?? script {uplevel 1 $script}
} else {
	proc ?? args {}
}

proc c {args} { #<<<
	set build	""
	set map {
		black		30
		red			31
		green		32
		yellow		33
		blue		34
		purple		35
		cyan		36
		white		37
		bg_black	40
		bg_red		41
		bg_green	42
		bg_yellow	43
		bg_blue		44
		bg_purple	45
		bg_cyan		46
		bg_white	47
		inverse		7
		bold		5
		underline	4
		bright		1
		norm		0
	}
	foreach t $args {
		if {[dict exists $map $t]} {
			append build "\[[dict get $map $t]m"
		}
	}
	set build
}

#>>>
proc aside txt { #<<<
	TclReadLine::clearline
	TclReadLine::print $txt
	namespace eval ::TclReadLine {prompt $CMDLINE}
}

#>>>
proc aside_log {level msg} { #<<<
	regsub -all {[[0-9]+m|[^[:print:]]+} $msg {} rawmsg
	switch -- $level {
		LOG_DEBUG -
		trivia -
		debug	{
			set cols	{bright black}
		}

		notify -
		notice {
			set cols	{bright white}
		}

		LOG_INFO -
		warn -
		warning {
			set cols	{bright purple}
		}

		error -
		LOG_ERR {
			set cols	{bright red}
		}

		fatal -
		LOG_CRIT -
		LOG_ALERT -
		LOG_EMERG {
			set cols	{bright white bg_red}
		}

		default {
			set cols	{white}
		}
	}
	aside "## [c {*}$cols]$rawmsg[c norm]\n"
}

#>>>

logging::logger ::log [cfg @loglevel] -cmd [list aside_log %level%]
#logging::logger ::log [cfg @loglevel]

set TclReadLine::PROMPT {[cfg @uri] > }

proc connect {{uri ""}} { #<<<
	global con

	if {$uri eq ""} {
		set uri	[cfg @uri]
	}

	if {[info exists con] && [info object isa object $con]} {
		$con destroy
	}
	set con	[netdgram::connect_uri $uri]
	oo::objdefine $con method closed {} {
		log notice "Server closed connection"
	}
	oo::objdefine $con method received msg {
		global waiting

		set rest	[lassign $msg type]
		switch -- $type {
			version {
				log notice "Admin console server: $rest"
			}

			resp {
				lassign $rest id options res
				switch -- [dict get $options -code] {
					0 - 2 {
					}

					default {
						log error $res
						?? {
							log error [dict get $options -errorinfo]
						}
					}
				}
				if {[info exists waiting($id)]} {
					set cb	$waiting($id)
					array unset waiting $id
					$cb [list $options $res]
				}
			}

			default {
				log error "Unexpected message type \"$type\" received from node"
			}
		}
	}
	$con activate
}

#>>>

set cmdseq	0
proc _sendcmd args { #<<<
	global con cmdseq waiting
	if {![info exists con] || ![info object isa object $con]} {
		log error "Not connected"
	}
	set myseq	[incr cmdseq]
	$con send [list cmd $myseq {*}$args]
	set waiting($myseq) [info coroutine]
	lassign [yield] options res
	return -options $options $res
}

#>>>

namespace eval cmds {
	namespace export *
	namespace ensemble create

	proc ports args {
		foreach port [_sendcmd ports {*}$args] {
			aside $port
		}
	}

	proc connect {{uri ""}} {
		::connect $uri
	}
}

connect [cfg @uri]

TclReadLine::interact ::cmds
#chan configure stdin -blocking 0 -buffering line
#chan event stdin readable [list apply {
#	{} {
#		set line	[chan gets stdin]
#		if {[chan eof stdin]} {
#			chan close stdin
#			set ::exit 0
#			return
#		}
#		try {
#			cmds {*}$line
#		} on error {errmsg options} {
#			log error $errmsg
#		}
#	}
#}]
#
#if {![info exists exit]} {
#	vwait exit
#}
#exit $exit

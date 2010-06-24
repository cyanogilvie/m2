# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require cflib

cflib::config create cfg $argv {
	variable debug		0
	variable mode		"auto"
}

set action	[lindex [cfg rest] 0]

proc log {lvl msg args} {puts $msg}

if {[cfg get debug]} {
	proc ?? {script} {uplevel 1 $script}
} else {
	proc ?? {args} {}
}

proc pick_mode {} { #<<<
	if {[file exists /etc/inittab]} {
		return "inittab"
	} elseif {[file isdirectory /etc/init]} {
		return "upstart"
	} else {
		log error "No supported installation options found"
		exit 2
	}
}

#>>>

if {[cfg get mode] eq "auto"} {
	set mode	[pick_mode]
} else {
	set mode	[cfg get mode]
}

proc inittab {action} { #<<<
	set id			m2n
	set runlevels	2345
	set cmd			"/usr/bin/m2_node -daemon 0"

	switch -- $action {
		install {
			set newfile	[list]
			foreach line [split [cflib::readfile /etc/inittab] \n] {
				set trimline	[string trim $line]
				if {
					[string index $trimline 0] eq "#" ||
					$trimline eq "" ||
					[lindex [split $trimline :] 0] ne $id
				} {
					lappend newfile $line
				}
			}
			lappend newfile [join [list $id $runlevels respawn $cmd] :]

			cflib::writefile /etc/inittab [join $newfile \n]

			try {
				exec kill -HUP 1
			} on error {errmsg options} {
				log error "Could not restart init: $errmsg"
			} on ok {} {
				?? {log debug "Restarted init"}
			}
		}

		remove {
			set newfile	[list]
			foreach line [split [cflib::readfile /etc/inittab] \n] {
				set trimline	[string trim $line]
				if {
					[string index $trimline 0] eq "#" ||
					$trimline eq "" ||
					[lindex [split $trimline :] 0] ne $id
				} {
					lappend newfile $line
				}

			}
			cflib::writefile /etc/inittab [join $newfile \n]

			try {
				exec kill -HUP 1
			} on error {errmsg options} {
				log error "Could not restart init: $errmsg"
			} on ok {} {
				?? {log debug "Restarted init"}
			}
		}

		default {
			log error "Invalid action: \"$action\""
			exit 1
		}
	}
}

#>>>
proc upstart {action} { #<<<
	switch -- $action {
		install {
			if {[file exists /etc/init/m2_node.conf]} {
				try {
					exec status m2_node
				} on ok {output} {
					?? {log debug "job status: \"$output\""}
					set running	[expr {[lindex $output 1] eq "start/running"}]
				} on error {errmsg options} {
					log error "Error stopping querying job status: $errmsg"
					exit 1
				}
			} else {
				set running	0
			}

			if {$running} {
				try {
					exec stop m2_node
				} on error {errmsg options} {
					log error "Could not stop job: $errmsg"
				} on ok {} {
					?? {log debug "Stopped job"}
				}
			}

			set cmd			"/usr/bin/m2_node -daemon 0"
			set job	[format {
description "M2 Node"

start on stopped networking and stopped mountall
stop on runlevel [!2345]

respawn
exec %s
} $cmd]

			cflib::writefile /etc/init/m2_node.conf $job

			try {
				exec start m2_node
			} on error {errmsg options} {
				log error "Could not start job: $errmsg"
			} on ok {} {
				?? {log debug "Started job"}
			}
		}

		remove {
			try {
				exec status m2_node
			} on ok {output} {
				?? {log debug "job status: \"$output\""}
				set running	[expr {[lindex $output 1] eq "start/running"}]
			} on error {errmsg options} {
				log error "Error stopping querying job status: $errmsg"
			}

			if {$running} {
				try {
					exec stop m2_node
				} on error {errmsg options} {
					log error "Could not stop job: $errmsg"
				} on ok {} {
					?? {log debug "Stopped job"}
				}
			}

			file delete -- /etc/init/m2_node.conf
		}

		default {
			log error "Invalid action: \"$action\""
			exit 1
		}
	}
}

#>>>

switch -- $mode {
	inittab {inittab $action}
	upstart {upstart $action}
}

exit 0

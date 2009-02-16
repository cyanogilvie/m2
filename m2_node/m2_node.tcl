#!/usr/bin/env kbskit8.6

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require Tcl 8.6
package require m2

# Config options handling <<<
set cfg	[dict create {*}{
	listen_on		{"tcp://:5300"}
	upstream		{}
	daemon			1
	runas_user		"daemon"
	runas_group		"daemon"
}]

set cmd_args	[dict create]
set rest		{}
for {set i 0} {$i < [llength $argv]} {incr i} {
	set arg	[lindex $argv $i]
	if {[string index $arg 0] ne "-"} {
		lappend rest	$arg
		continue
	}

	set k	$arg
	incr i
	if {$i >= [llength $argv]} {
		puts stderr "Missing argument for \"%k\""
		exit 1
	}
	set k	[string range $k 1 end]
	set v	[lindex $argv $i]

	if {![dict exists $cfg $k]} {
		puts stderr "Invalid arg: \"$k\", should be one of \"[join [dict keys $cfg] "\", \""]\""
		exit 1
	}
	dict set cmd_args $k $v
}
set cfg	[dict merge $cfg $cmd_args]

proc cfg {op args} {
	global cfg

	switch -- $op {
		"get" {
			set rest	[lassign $args key]
			if {[llength $rest] > 1} {
				error "Too many arguments"
			}
			if {[dict exists $cfg $key]} {
				return [dict get $cfg $key]
			} else {
				if {[llength $args] > 0} {
					return [lindex $args 0]
				} else {
					error "No such config item: \"$key\""
				}
			}
		}

		default {
			error "Invalid config operation: \"$op\""
		}
	}
}
# Config options handling >>>

proc log {lvl msg} {
	puts $msg
}

interp bgerror {} [list apply {
	{errmsg options} {
		log error "$errmsg"
		#array set o	$options
		#parray o
	}
}]

if {[dict get $cfg daemon]} {
	if {[::tcl::pkgconfig get threaded]} {
		puts stderr "Cannot daemonize in a threaded interpreter"
		exit 1
	}
	package require daemon 0.3
	namespace eval dutils {
		namespace export daemon*
	}
	namespace import dutils::*

	# Drop root priviledges <<<
	proc _readfile {fn} { #<<<
		set fp	[open $fn r]
		set dat	[read $fp]
		close $fp
		return $dat
	}

	#>>>
	proc lookup_uid {user} { #<<<
		foreach line [split [_readfile /etc/passwd] \n] {
			lassign [split $line :] username pw uid pgid gecos home shell

			if {$user eq $username} {
				return $uid
			}
		}

		error "User $user not found" "" [list no_such_user $user]
	}

	#>>>
	proc lookup_gid {name} { #<<<
		foreach line [split [_readfile /etc/group] \n] {
			lassign [split $line :] group pw gid userlist
			set userlist	[split $userlist ,]

			if {$name eq $group} {
				return $gid
			}
		}

		error "Group $group not found" "" [list no_such_group $name]
	}

	#>>>

	if {
		[dutils::getgid] == 0 ||
		[dutils::getegid] == 0
	} {
		set gid		[lookup_gid [cfg get runas_group]]
		dutils::setregid $gid $gid
	}

	if {
		[dutils::getuid] == 0 ||
		[dutils::geteuid] == 0
	} {
		set uid		[lookup_uid [cfg get runas_user]]
		dutils::setreuid $uid $uid
	}
	# Drop root priviledges >>>

	daemon_name "m2_node"
	daemon_pid_file_proc [list apply {
		{} {
			file join / var tmp m2_node.pid
		}
	}]

	proc log {lvl msg} { #<<<
		set dlog_prio	"LOG_DEBUG"
		switch -- $lvl {
			trivia	{return}
			debug	{set dlog_prio	"LOG_DEBUG"}
			notice	{set dlog_prio	"LOG_INFO"}
			warn -
			warning	{set dlog_prio	"LOG_WARNING"}
			error	{set dlog_prio	"LOG_ERR"}
			fatal	{set dlog_prio	"LOG_CRIT"}
			default {
				if {$lvl in {
					LOG_EMERG
					LOG_ALERT
					LOG_CRIT
					LOG_ERR
					LOG_WARNING
					LOG_NOTICE
					LOG_INFO
					LOG_DEBUG
				}} {
					set dlog_prio	$lvl
				} else {
					set dlog_prio	"LOG_DEBUG"
				}
			}
		}
		daemon_log $dlog_prio $msg
	}

	#>>>

	set cmd	[lindex $rest 0]
	if {$cmd eq ""} {
		set cmd		"start"
	}

	if {$cmd ni {
		start
		stop
		restart
		status
		pidfile
	}} {
		puts stderr "Invalid command \"$cmd\", should be one of \"start\", \"stop\", \"restart\", \"status\" or \"pidfile\""
		exit 1
	}

	set existingpid		[daemon_pid_file_is_running]
	switch -- $cmd {
		stop - restart { #<<<
			if {[daemon_pid_file_is_running] < 0} {
				daemon_log LOG_WARNING "Can't stop - not running"
				exit 1
			}

			try {
				daemon_pid_file_kill_wait SIGINT 5
			} on error {errmsg options} {
				daemon_log LOG_WARNING "Failed to kill daemon: $errmsg"
				exit 1
			} on ok {} {
				set existingpid	-1
			}

			if {$cmd eq "stop"} {
				exit 0
			}
			#>>>
		}

		status { #<<<
			if {$existingpid >= 0} {
				puts "running"
				exit 0
			} else {
				puts "not running"
				exit 0
			}
			#>>>
		}

		pidfile { #<<<
			puts [daemon_pid_file]
			exit 0
			#>>>
		}
	}

	if {$existingpid >= 0} {
		daemon_log LOG_ERR "already running, PID: ($existingpid)"
		exit 1
	}

	set pid	[daemon_fork]
	daemon_log LOG_INFO "running, pid: ([pid])"
}

try {
	m2::node create server \
			-listen_on	[dict get $cfg listen_on] \
			-upstream	[dict get $cfg upstream]
} on error {errmsg options} {
	daemon_log LOG_ERR "Could not start m2 node: $errmsg"
	deamon_retval_send 1
	exit 1
}

if {[dict get $cfg daemon]} {
	daemon_sighandler [list apply {
		{signame} {
			switch -- $signame {
				"SIGINT" -
				"SIGQUIT" -
				"SIGTERM" {
					daemon_log LOG_INFO "Got $signame, shutting down cleanly"
					try {
						server destroy
					} on error {errmsg options} {
						daemon_log LOG_WARNING "Problem cleanly shutting down node: $errmsg"
					}
					daemon_exit
				}

				"SIGHUP" {
					daemon_log LOG_INFO "Got HUP"
					# TODO: what?
				}

				default {
					daemon_log LOG_WARNING "Got unexpected signal: \"$signame\", ignoring"
				}
			}
		}
	}]

	daemon_retval_send 0
	daemon_log LOG_INFO "Successfully started"
}

vwait ::forever


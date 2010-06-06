#!/usr/bin/env kbskit8.6

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require netdgram::tcp
package require m2
package require cflib

cd [file dirname [info script]]

if {[::tcl::pkgconfig get threaded]} {
	puts stderr "Cannot daemonize in a threaded interpreter"
	exit 1
}
package require daemon 0.3
namespace eval dutils {
	namespace export daemon*
}
namespace import dutils::*

daemon_name "chatprov"
daemon_pid_file_proc [list apply {
	{} {
		file join / var tmp chatprov.pid
	}
}]

set cmd	[lindex $argv 0]
if {$cmd eq ""} {
	set cmd	"start"
}

set valid_commands {
	start
	stop
	restart
	status
	pidfile
}
if {$cmd ni $valid_commands} {
	puts stderr "Invalid command \"$cmd\", should be one of \"[join $valid_commands "\", \""]\""
	exit 1
}
set existingpid	[daemon_pid_file_is_running]
switch -- $cmd {
	stop - restart { #<<<
		if {[daemon_pid_file_is_running] < 0} {
			if {$cmd eq "restart"} {
				daemon_log LOG_WARNING "Not running"
			} else {
				daemon_log LOG_WARNING "Can't stop - not running"
				exit 1
			}
		} else {
			try {
				daemon_pid_file_kill_wait SIGINT 5
			} on error {errmsg options} {
				daemon_log LOG_WARNING "Failed to kill daemon: $errmsg"
				exit 1
			} on ok {} {
				set existingpid	-1
			}
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

try {
	daemon_sighandler [list apply {
		{signame} {
			switch -- $signame {
				"SIGINT" -
				"SIGQUIT" -
				"SIGTERM" {
					daemon_log LOG_INFO "Got $signame, shutting down cleanly"
					try {
						if {[info object isa object chat]} {
							chatserver destroy
						}
						if {[info object isa object m2]} {
							m2 destroy
						}
					} on error {errmsg options} {
						daemon_log LOG_WARNING "Problem cleanly shutting down: $errmsg"
					}
					daemon_exit
				}

				"SIGHUP" {
					daemon_log LOG_INFO "Got HUP"
				}

				default {
					daemon_log LOG_WARNING "Got unexpected signal: \"$signame\""
				}
			}
		}
	}]

	m2::api2 create m2 -uri "tcp://localhost:5300"

	source "chat.tcl"

	chat create chatserver
} on error {errmsg options} {
	daemon_log LOG_ERR "Initialization failed: $errmsg"
	daemon_retval_send 1
	daemon_exit
}

daemon_retval_send 0
daemon_log LOG_INFO "Started"

vwait ::forever

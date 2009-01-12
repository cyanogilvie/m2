# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

namespace eval netdgram {
	package require netdgram

	class create connectionmethod::tcp_coroutine { #<<<
		superclass netdgram::connectionmethod
		mixin netdgram::debug

		constructor {} { #<<<
			if {[self next] ne {}} {next}
			if {![package vsatisfies [info patchlevel] 8.6-]} {
				error "Coroutines require Tcl 8.6"
			}
		}

		#>>>

		method listen {uri_obj} { # <<<
			set parts	[$uri_obj as_dict]
			set params	[split [dict get $parts authority] :]
			if {[llength $params] != 2} {
				error "Invalid connection parameters, expecting [self class]://ip:port specify ip as \"*\" to bind to all interfaces"
			}
			lassign $params host port
			set flags	[dict get $parts query]
			set listen [netdgram::listener::tcp_coroutine new $host $port $flags]
			oo::objdefine $listen forward human_id apply {
				{human_id} {
					set human_id
				}
			} "uri([$uri_obj encoded]) pid([pid])"
			return $listen
		}

		#>>>
		method connect {uri_obj} {	;# <<<
			try {
				set parts	[$uri_obj as_dict]
				set params	[split [dict get $parts authority] :]
				if {[llength $params] != 2} {
					error "Invalid connection parameters, expecting [self class]://ip:port"
				}
				lassign $params host port
				set flags	[dict get $parts query]
				set socket	[socket $host $port]

				set con	[netdgram::connection::tcp_coroutine new $socket $host $port $flags]
				oo::objdefine $con forward human_id apply {
					{human_id} {
						set human_id
					}
				} "uri([$uri_obj encoded]) pid([pid]) con($con)"
				return $con
			} on error {errmsg options} {
				if {[info exists con] && [info object isa object $con]} {
					$con destroy
					unset con
				}
				if {[info exists socket] && $socket in [chan names]} {
					close $socket
					unset socket
				}
			}
		}

		#>>>
	}


	#>>>
	class create listener::tcp_coroutine { #<<<
		superclass netdgram::listener
		mixin netdgram::debug

		variable {*}{
			flags
			listen
		}

		constructor {host port a_flags} { #<<<
			if {[self next] ne {}} {next}

			set flags $a_flags
			if {$host in {* 0.0.0.0 ""}} {
				set listen	[socket -server [namespace code {my _accept}] $port]
			} else {
				set listen	[socket -server [namespace code {my _accept}] -myaddr $host $port]
			}
		}

		#>>>
		destructor { #<<<
			if {[info exists listen]} {
				close $listen
				unset listen
			}

			if {[self next] ne {}} {next}
		}

		#>>>

		method _accept {socket cl_ip cl_port} { #<<<
			try {
				set con		[netdgram::connection::tcp_coroutine new \
						$socket $cl_ip $cl_port $flags]

				oo::objdefine $con forward human_id apply {
					{human_id} {
						set human_id
					}
				} "con($con) fromaddr($cl_ip:$cl_port) on [my human_id]"

				my accept $con $cl_ip $cl_port
			} on error {errmsg options} {
				puts "Error in accept: $errmsg\n[dict get $options -errorinfo]"
				if {[info exists con] && [info object is object $con]} {
					$con destroy
					unset con
				}
				return
			}

			if {![info exists con] || ![info object is object $con]} {
				# $con died, most likely killed by the accept handler
				return
			}
			try {
				$con activate
			} on error {errmsg options} {
				puts stderr "Unexpected error activating $con: $errmsg\n[dict get $options -errorinfo]"
				if {[info object is object $con]} {
					$con destroy
					unset con
				}
			}
		}

		#>>>
	}


	#>>>
	class create connection::tcp_coroutine { #<<<
		superclass netdgram::connection
		mixin netdgram::debug

		variable {*}{
			socket
			cl_ip
			cl_port
			data_waiting
		}

		constructor {a_socket a_cl_ip a_cl_port a_flags} { #<<<
			if {[self next] ne {}} {next}

			set socket	$a_socket
			set cl_ip	$a_cl_ip
			set cl_port	$a_cl_port
			set data_waiting	0
			#try {
			#	chan configure $socket -nodelay 1
			#} on error {errmsg options} {
			#	puts stderr "Couldn't set TCP_NODELAY on socket: $errmsg"
			#} on ok {} {
			#	puts stderr "Enabled TCP_NODELAY on socket"
			#}
			puts "[self] initialized socket to: ($socket)"
		}

		#>>>
		destructor { #<<<
			if {[info exists socket] && $socket in [chan names]} {
				close $socket
				unset socket
			}

			my closed
			if {[self next] ne {}} {next}
		}

		#>>>

		method activate {} { #<<<
			if {![info exists socket] || $socket ni [chan names]} {
				throw {socket_collapsed} "Socket collapsed"
			}
			set coro	"::consumer_[string map {:: _} [self]]"
			coroutine $coro my _consumer
			chan event $socket readable [list $coro]
		}

		#>>>
		method send {msg} { #<<<
			set data_len	[string length $msg]
			try {
				chan configure $socket \
						-buffering full
				chan puts $socket $data_len
				chan puts -nonewline $socket $msg
				#puts "writing msg: ($msg) to $socket"
				chan flush $socket
			} on error {errmsg options} {
				puts stderr "Error writing message to socket: $errmsg\n[dict get $options -errorinfo]"
				my destroy
				return
			}
		}

		#>>>
		method data_waiting {newstate} { #<<<
			if {$newstate == $data_waiting} return
			set data_waiting	$newstate

			if {$data_waiting} {
				#my variable writable_kickoff
				#set writable_kickoff	[clock microseconds]
				chan event $socket writable [namespace code {my _notify_writable}]
			} else {
				chan event $socket writable {}
			}
		}

		#>>>

		method _consumer {} { #<<<
			try {
				while {1} {
					chan configure $socket \
							-blocking 0 \
							-buffering line \
							-translation binary

					while {1} {
						set line	[gets $socket]
						if {[chan eof $socket]} {throw {close} ""}
						if {![chan blocked $socket]} break
						#puts stderr "yielding waiting for the control line"
						yield
					}

					lassign $line payload_bytecount
					set remaining	$payload_bytecount

					if {![string is integer -strict $payload_bytecount]} {
						throw {close} ""
					}

					chan configure $socket \
							-blocking 0 \
							-buffering none \
							-translation binary
					set payload	""
					while {$remaining > 0} {
						set chunk	[chan read $socket $remaining]
						if {[chan eof $socket]} {throw {close} ""}
						set chunklen	[string length $chunk]
						if {$chunklen == 0} {
							#puts "yielding waiting for the rest of the data packet (got [string length $payload] bytes, waiting for $remaining bytes"
							yield
							continue
						}
						append payload	$chunk
						unset chunk
						incr remaining -$chunklen
					}

					my received $payload
				}
			} trap {close} {res options} {
				# Nothing to do.  destructor takes care of it
			} on error {errmsg options} {
				puts stderr "Unhandled error in consumer: $errmsg"
				array set e $options
				parray e
				puts stderr "[dict get $options -errorinfo]"
			} finally {
				my destroy
			}
		}

		#>>>
		method _notify_writable {} { #<<<
			# Also called for eof
			if {[chan eof $socket]} {
				my destroy
				return
			}

			#my variable writable_kickoff
			#if {[info exists writable_kickoff]} {
			#	set writable_delay	[expr {[clock microseconds] - $writable_kickoff}]
			#	unset writable_kickoff
			#	puts stderr "delay in getting writable after asking for it: $writable_delay usec"
			#}
			try {
				my writable
			} on error {errmsg options} {
				puts stderr "Error in writable handler: $errmsg\n[dict get $options -errorinfo]"
			}
		}

		#>>>
	}


	#>>>
}

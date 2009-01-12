# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

namespace eval netdgram {
	package require netdgram

	class create connectionmethod::uds { #<<<
		superclass netdgram::connectionmethod
		mixin netdgram::debug

		constructor {} { #<<<
			if {[self next] ne {}} {next}

			package require unix_sockets
		}

		#>>>

		method listen {uri_obj} { # <<<
			set parts	[$uri_obj as_dict]
			if {[dict get $parts authority] ne ""} {
				error "Unix domain sockets can only be local"
			}
			set path	[dict get $parts path]
			set flags	[dict get $parts query]
			return [netdgram::listener::uds new $path $flags]
		}

		#>>>
		method connect {uri_obj} {	;# <<<
			try {
				set parts	[$uri_obj as_dict]
				if {[dict get $parts authority] ne ""} {
					error "Unix domain sockets can only be local"
				}
				set path	[dict get $parts path]
				set flags	[dict get $parts query]
				set socket	[unix_sockets::connect $path]
				return [netdgram::connection::uds new $socket $flags]
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
	class create listener::uds { #<<<
		superclass netdgram::listener
		mixin netdgram::debug

		variable {*}{
			flags
			listen
		}

		constructor {path a_flags} { #<<<
			if {[self next] ne {}} {next}

			set flags $a_flags
			set listen	[unix_sockets::listen $path [namespace code {my _accept}]]
		}

		#>>>
		destructor { #<<<
			if {[info exists listen]} {
				if {$listen in [chan names]} {
					close $listen
				}
				unset listen
			}
			if {[self next] ne {}} {next}
		}

		#>>>

		method _accept {socket} { #<<<
			try {
				set con		[netdgram::connection::uds new \
						$socket $flags]

				my accept $con
			} on error {errmsg options} {
				puts "Error in accept: $errmsg\n[dict get $options -errorinfo]"
				if {[info exists con] && [info object is object $con]} {
					$con destroy
					unset con
				}
			} on ok {res options} {
				$con activate
			}
		}

		#>>>
	}


	#>>>
	class create connection::uds { #<<<
		superclass netdgram::connection
		mixin netdgram::debug

		variable {*}{
			socket
			data_waiting
		}

		constructor {a_socket a_flags} { #<<<
			if {[self next] ne {}} {next}

			set socket	$a_socket
			set data_waiting	0
			puts "[self] initialized socket to: ($socket)"
		}

		#>>>
		destructor { #<<<
			if {[info exists socket]} {
				if {$socket in [chan names]} {
					close $socket
				}
				unset socket
			}

			my closed
			if {[self next] ne {}} {next}
		}

		#>>>

		method activate {} { #<<<
			set coro	"::consumer_[string map {:: _} [self]]"
			coroutine $coro my _consumer
			chan event $socket readable [list $coro]
		}

		#>>>
		method send {msg} { #<<<
			set data_len	[string length $msg]
			chan puts $socket $data_len
			chan puts -nonewline $socket $msg
			puts "writing msg: ($msg) to $socket"
			chan flush $socket
		}

		#>>>
		method data_waiting {newstate} { #<<<
			if {$newstate == $data_waiting} return
			set data_waiting	$newstate

			if {$data_waiting} {
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
					puts "FOO"
						set line	[gets $socket]
					puts "BAR"
						if {[chan eof $socket]} {throw {close} ""}
						if {![chan blocked $socket]} break
						yield
					}
					puts "BAZ"

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
				puts stderr "Unhandled error in consumer: $errmsg\n[dict get $options -errorinfo]"
			} finally {
				my destroy
			}
		}

		#>>>
		method _notify_writable {} { #<<<
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


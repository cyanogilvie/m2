# vim: foldmarker=<<<,>>> ft=tcl foldmethod=marker shiftwidth=4 ts=4

oo::class create m2::threaded_api {
	superclass m2::api

	variable {*}{
		tid
		queue
		uri
	}

	method _init {} { #<<<
		my _create_thread
		tailcall next
	}

	#>>>
	method _destroy {} { #<<<
		log notice "Called [self] threaded_api::_destroy"
		if {[thread::exists $tid]} {
			thread::send $tid {
				if {[info exists $queue]} {
					m2::_destroy_queue $queue
					unset queue
				}
			}
			thread::release $tid
		}
		tailcall next
	}

	#>>>
	method send msg { #<<<
		evlog event m2.queue_msg {[list to $uri msg $msg]}
		#thread::send -async $tid [list m2::_enqueue $queue $msg]
		thread::send -async $tid [list $queue enqueue [m2::msg::serialize $msg] \
			[dict get $msg type] \
			[dict get $msg seq] \
			[dict get $msg prev_seq]]
	}

	#>>>
	method _create_con a_uri { #<<<
		lassign [thread::send $tid [string map [list \
				%uri%					$a_uri \
				%connection_lost_cb%	[list [namespace code {my _connection_lost}]] \
				%got_msg_cb%			[namespace code {my _got_msg_raw}] \
				%main_tid%				[list [thread::id]] \
		] {
			try {
				set con		[netdgram::connect_uri %uri%]
				set queue	[netdgram::queue new]
				$queue attach $con

				oo::objdefine $queue forward closed thread::send %main_tid% \
						%connection_lost_cb%
				oo::objdefine $queue method receive raw_msg {
					thread::send -async %main_tid% [list %got_msg_cb% $raw_msg]
					#thread::send -async %main_tid% [list %got_msg_cb% \
					#		[m2::msg::deserialize $raw_msg]]
				}
				oo::objdefine $queue method assign {rawmsg type seq prev_seq} { #<<<
					switch -- $type {
						rsj_req - req {
							set seq
						}

						jm - jm_can {
							if {$prev_seq eq 0} {
								set seq
							} else {
								my variable _pending_jm_setup
								#puts stderr "[self] marking pending ($seq), prev_seq ($prev_seq)"
								dict set _pending_jm_setup $seq $prev_seq 1
								set prev_seq
							}
						}

						default {
							set prev_seq
						}
					}
				}

				#>>>
				oo::objdefine $queue method pick {queues} { #<<<
					my variable _pending_jm_setup
					if {![info exists _pending_jm_setup]} {
						set _pending_jm_setup	[dict create]
					}

					set q		[next $queues]
					set first	$q

					# Skip queues for jms that were setup in requests for which
					# we still haven't sent the ack or nack
					while {[dict exists $_pending_jm_setup $q]} {
						set q		[next $queues]
						if {$q eq $first} {
							set errmsg	"[self] Eeek - all queues have the pending flag set, should never happen.  Queues:"
							foreach p $queues {
								if {[dict exists $_pending_jm_setup $p]} {
									append errmsg "\n\t($p): ([dict get $_pending_jm_setup $p])"
								} else {
									append errmsg "\n\t($p): --"
								}
							}
							if {[info commands "dutils::daemon_log"] ne {}} {
								dutils::daemon_log LOG_ERR $errmsg
							} else {
								puts stderr $errmsg
							}
							# Should never happen
							break
						}
					}

					return $q
				}

				#>>>
				oo::objdefine $queue method sent {type seq prev_seq} { #<<<
					if {$type in {
						ack
						nack
					}} {
						my variable _pending_jm_setup
						if {![info exists _pending_jm_setup]} {
							set _pending_jm_setup	[dict create]
						}

						dict for {s ps} $_pending_jm_setup {
							foreach p [dict keys $ps] {
								if {$p eq $prev_seq} {
									dict unset _pending_jm_setup $s $p
									if {[dict size [dict get $_pending_jm_setup $s]] == 0} {
										dict unset _pending_jm_setup $s
									}
								}
							}
						}
					}
				}

				#>>>

				$con activate
			} on ok {res options} {
				list $res $options $queue
			} on error {errmsg options} {
				if {[info exists queue] && [info object is object $queue]} {
					$queue destroy
					unset queue
				}
				if {[info exists con] && [info object is object $con]} {
					$con destroy
					# $con unset by close_con
				}

				list $errmsg $options ""
			}
		}]] res options queue
		return -options $options $res
	}

	#>>>
	method station_id {} { #<<<
		thread::send $tid {[$queue con] human_id}
	}

	#>>>
	method _create_thread {} { #<<<
		package require Thread 2.6.6

		set debug	0
		?? {set debug	1}

		set tid	[thread::create -preserved [string map [list \
				%tm_path%		[tcl::tm::path list] \
				%auto_path%		[list $::auto_path] \
				%debug%			$debug \
				%main_tid%		[list [thread::id]] \
		] {
			tcl::tm::path add %tm_path%
			set auto_path		%auto_path%

			proc log args {thread::send -async %main_tid% [list log {*}$args]}

			package require netdgram
			package require m2

			package require netdgram::tcp
			oo::define netdgram::connectionmethod::tcp method default_port {} {
				return 5300
			}

			if {%debug%} {
				proc ?? script {uplevel 1 $script}
			} else {
				proc ?? args {}
			}

			?? {log debug "Created threaded_api, tid: [thread::id]"}

			thread::wait
		}]]
	}

	#>>>
}

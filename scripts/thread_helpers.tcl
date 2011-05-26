# vim: ts=4 foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

proc m2::_accept {con} {
	set queue [netdgram::queue new]
	$queue attach $con
	set queue
}

proc m2::_enqueue {queue msg} {
	$queue enqueue [m2::msg::serialize $msg] \
			[dict get $msg type] \
			[dict get $msg seq] \
			[dict get $msg prev_seq]
}

proc m2::_destroy_queue {queue} {
	if {[info exists queue] && [info object is object $queue]} {
		set con	[$queue con]
		# $queue dies when $con does, close_con unsets $con
		if {[info object isa object $con]} {
			$con destroy
		} else {
			log warning "con $con died mysteriously under queue $queue"
			$queue destroy
		}
	}
}

proc m2::_activate {con} {
	try {
		$con activate
	} on error {errmsg options} {
		log error "Unexpected error activating $con: [dict get $options -errorinfo]"
		if {[info object isa object $con]} {
			$con destroy
			unset con
		}
	}
}


# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create m2::handlers {
	constructor {} {
		set allow_unregistered	1
		set handlers			[dict create]
		set afterids			[dict create]
		set processing_handlers	0
		set processing_stack	{}
	}

	destructor {
		try {
			if {[info exists afterids]} {
				dict for {key val} $afterids {
					after cancel $val
					dict unset afterids $key
				}
			}
		} on error {errmsg options} {
			puts "Error destroying [self]: $errmsg\n[dict get $options -errorinfo]"
		}
	}

	variable {*}{
		allow_unregistered
		handlers
		afterids
		processing_handlers
		processing_stack
	}

	method register_handler {type handler} { #<<<
		if {
			![dict exists $handlers $type]] 
			|| $handler ni [dict get $handlers $type]
		} {
			my _handlers_debug trivia "Registering handler ($type) ($handler)"
			dict lappend handlers $type	$handler
		}
	}

	#>>>
	method deregister_handler {type handler} { #<<<
		if {![dict exists $handlers $type]} return
		set idx	[lsearch [dict get $handlers $type] $handler]
		#log trivia "[self] Deregistering handler ($type) ($handler)"
		dict set handlers $type	[lreplace [dict get $handlers $type] $idx $idx]
	}

	#>>>
	method handlers_available {type} { #<<<
		return [expr {
			[dict exists $handlers $type]] &&
			[llength [dict get $handlers $type]] >= 1}]
	}

	#>>>
	method dump_handlers {} { #<<<
		return $handlers
	}

	#>>>

	method invoke_handlers {type args} { #<<<
		if {![dict exists $handlers $type]]} {
			if {$allow_unregistered} {
				return
			} else {
				error "[self]: No handlers found for type: ($type)"
			}
		}

		set results	{}
		if {$processing_handlers} {
			my _handlers_debug debug "detected reentrant handling for ($type) stack: ($processing_stack)"
		}
		incr processing_handlers	1
		lappend processing_stack	$type
		set last_handler	""
		try {
			my _handlers_debug debug "entering processing of $type"
			foreach handler [dict get $handlers $type] {
				# Check if a previous handler removed this one <<<
				if {
					![dict exists $handlers $type]] ||
					$handler ni [dict get $handlers $type]
				} {
					my _handlers_debug debug "Skipping handler ($handler) which has just been removed (presumably by a previous handler in the list"
					continue
				}
				# Check if a previous handler removed this one >>>
				set pending_afterid	\
						[after 3000 [namespace code [list my _throw_hissy_handler $handler $args]]]
				set last_handler	$handler
				dict set afterids invoke_handler_$handlerx)	$pending_afterid
				my _handlers_debug debug "Invoking callback for ($type): ($handler)"
				lappend results	[uplevel #0 $handler $args]
				after cancel $pending_afterid
				dict unset afterids	invoke_handler_$handler
			}
		} on ok {
			incr processing_handlers	-1
			set processing_stack		[lrange $processing_stack 0 end-1]
			my _handlers_debug debug "leaving processing of $type"
			return $results
		} on error {errmsg options} {
			incr processing_handlers	-1
			set processing_stack		[lrange $processing_stack 0 end-1]
			my _handlers_debug error "\nError processing handlers for ($type), in handler ($last_handler): $errmsg\n[dict get $options -errorinfo]"
			dict incr options -level
			return -options $options $errmsg
		}
	}

	#>>>
	method _debug {msg} { #<<<
		my _handlers_debug debug $msg
	}

	#>>>
	method _handlers_debug {lvl msg} { #<<<
		# Override in derived class
		switch -- $lvl {
			warning -
			error {
				puts stderr "m2::handlers::handlers_debug([self]): $lvl $msg"
			}
		}
	}

	#>>>

	method _throw_hissy_handler {handler arglist} { #<<<
		puts stderr "\n\nHandlers::throw_hissy: obj: ([self]) taking way too long to complete invoke_handlers for handler: ($handler)\n\targs: ($arglist)\n\n"
	}

	#>>>
}



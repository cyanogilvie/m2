# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

m2::pclass create m2::signal {
	superclass m2::handlers m2::baselog

	property name		""	_name_changed
	property debugmode	0
	property output_handler_warntime	3000

	variable {*}{
		outputs
		cleanups
		o_state
		afterids
		changewait
		seq
	}

	method _name_changed {} { #<<<
		set baselog_instancename	$name
	}

	#>>>

	constructor {accessvar args} { #<<<
		my variable outputs o_state
		set outputs		{}
		set o_state		0
		set seq			0

		set cleanups	[dict create]
		set afterids	[dict create]
		array set changewait	{}

		my configure {*}$args

		upvar $accessvar scopevar
		set scopevar	[self]
		trace variable scopevar u [namespace code {my _scopevar_unset}]
	}

	#>>>
	destructor { #<<<
		my _debug debug "tlc::Signal::destructor: [self] $name dieing"
		#trace vdelete scopevar u [namespace code {my _scopevar_unset}]
		if {$debugmode} {
			dict for {tag afterid} $afterids {
				after cancel $afterid
				dict unset afterids $tag
			}
		}
		foreach output $outputs {
			my _debug debug "tlc::Signal::destructor: ------ twitch: ($output)"
			my detach_output $output
		}

		foreach key [array names $changewait] {
			my _debug debug "notifying waiting changewait($key) of our death"
			set changewait($key)	"source_died"
		}
		if {[self next] ne {}} {next}
		my _debug debug "tlc::Signal::destructor: [self] truely dead"
	}

	#>>>

	method state {} { #<<<
		my variable o_state
		return $o_state
	}

	#>>>
	method set_state {newstate} { #<<<
		my variable o_state
		if {![string is boolean -strict $newstate]} {
			throw [list not_a_boolean $newstate] \
					"newstate must be a valid boolean"
		}
		if {$newstate} {
			set normstate	1
		} else {
			set normstate	0
		}
		my _on_set_state $normstate
		if {$o_state == $normstate} return
		set o_state	$normstate
		my _update_outputs
	}

	#>>>
	method toggle_state {} { #<<<
		my variable o_state
		my set_state [expr {!$o_state}]
	}

	#>>>

	method attach_output {handler {cleanup {}}} { #<<<
		my variable outputs
		if {$handler in $outputs} {
			return 0
		}

		lappend outputs $handler
		
		if {$cleanup ne {}} {
			dict set cleanups $handler	$cleanup
		}
		my _update_output $handler
		
		return 1
	}

	#>>>
	method detach_output {handler} { #<<<
		my _debug debug "tlc::Signal::detach_output: ($handler)"
		if {$handler in $outputs} {
			set idx			[lsearch $outputs $handler]
			set outputs		[lreplace $outputs $idx $idx]

			if {[dict exists $cleanups $handler]} {
				my _debug debug "tlc::Signal::detach_output: cleaning up ($handler)"
				my _debug debug "tlc::Signal::detach_output: foo"
				uplevel #0 [dict get $cleanups $handler]
				my _debug debug "tlc::Signal::detach_output: bar"
				dict unset cleanups $handler
			}
			
			return 1
		} else {
			my _debug debug "tlc::Signal:detach_output: output not found!!\n($handler)\n[join $outputs \n]]\n============================="
			return 0
		}
	}

	#>>>

	method name {} { #<<<
		return $name
	}

	#>>>
	method explain_txt {{depth 0}} { #<<<
		return "[string repeat {  } $depth][self] \"[[self] name]\": [[self] state]\n"
	}

	#>>>

	method waitfor {sense {timeout 0}} { #<<<
		if {$sense} {
			if {[my state]} return
			set normsense	1
		} else {
			if {![my state]} return
			set normsense	0
		}

		set signame	[my name]
		set myseq	[incr seq]

		if {$timeout != 0} {
			set afterid \
					[after $timeout [namespace code [list my _changewait_timeout $myseq]]]
			dict set afterids waitfor_$myseq	$afterid
		}

		my _debug debug "tlc::Signal::waitfor: Waiting for [namespace which -variable changewait]($myseq)"
		set resolved	0
		while {!($resolved)} {
			set changewait($myseq)	"waiting"
			vwait [namespace which -variable changewait]($myseq)
			set res	$changewait($myseq)
			if {[string is boolean $res] && [state] != $normsense} {
				log warning "Woken up by transient spike while waiting for state $sense, waiting for more permanent change"
				set resolved	0
			} else {
				set resolved	1
			}
		}

		if {[info exists afterid]} {
			after cancel $afterid
			unset afterid
		}

		if {$res ne "source_died"} {
			# in the case where we have died, these data members have
			# disappeared, and to try to access them (like unsetting them)
			# causes a segfault

			dict unset afterids waitfor_$myseq
			array unset changewait $myseq
		}

		switch -- $res {
			1 -
			0 {
				return
			}

			"timeout" {
				throw [list timeout $signame] \
						"Timeout waiting for signal \"$signame\""
			}

			"source_died" {
				throw [list source_died $signame] \
						"Source died while waiting for signal \"$signame\""
			}

			default {
				error "Unexpected result waiting for signal \"$signame\": ($res)"
			}
		}
	}

	#>>>

	method _update_output {handler} { #<<<
		my variable o_state
		#puts stderr "Signal::_update_output($o_state): $name ([self]) update output ($handler)"
		if {$debugmode} {
			set pending_afterid	[after $output_handler_warntime \
					[namespace code [list my _throw_hissy $handler]]]
			dict set afterids update_output_$handler	$pending_afterid
		}
		try {
			uplevel #0 $handler [list $o_state]
		} on error {errmsg options} {
			my log error "\n\"$name\" error updating output ($o_state) handler: ($handler) $name ([self]): $errmsg\n[dict get $options -errorinfo]"
		}
		if {$debugmode} {
			after cancel $pending_afterid
			dict unset afterids	update_output_$handler
		}
		#puts stderr "Signal::_update_output: $name ([self]) done"
	}

	#>>>
	method _update_outputs {} { #<<<
		my variable outputs
		foreach output $outputs {
			my _update_output $output
		}
		my _debug debug "tlc::Signal::_update_outputs: Flagging changewaits: ([array names changewait])"
		foreach key [array names changewait] {
			my _debug debug "tlc::Signal::_update_outputs: flagging state change for waiting vwait: changewait($key) to ($o_state)"
			set changewait($key)	$o_state
		}
	}

	#>>>
	method _debug {level msg} { #<<<
		my invoke_handlers _debug $level $msg
	}

	#>>>
	method _on_set_state {pending} { #<<<
	}

	#>>>
	method _throw_hissy {handler} { #<<<
		log warning "name: ($name) obj: ([self]) taking way too long to update output for handler: ($handler)"
	}

	#>>>
	method _scopevar_unset {args} { #<<<
		#puts stderr "Signal::_scopevar_unset: $name ([self]) scopevar unset"
		if {$debugmode} {
			my _debug debug "tlc::Signal::_scopevar_unset"
		}
		my destroy
	}

	#>>>
	method _changewait_timeout {myseq} { #<<<
		set changewait($myseq)	"timeout"
	}

	#>>>
}



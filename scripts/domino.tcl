# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

m2::pclass create m2::domino {
	superclass m2::baselog

	property name	""		_name_changed
	property delay	"idle"

	protected_property after_id	""
	protected_property outputs	{}
	protected_property inputs	[dict create]
	protected_property lock		0

	method _name_changed {} { #<<<
		set baselog_instancename	$name
	}

	#>>>

	constructor {accessvar args} { #<<<
		my configure {*}$args

		if {$name eq ""} {
			my configure -name $accessvar
		}

		upvar $accessvar scopevar
		set scopevar [self]
		trace variable scopevar u [my code _scopevar_unset]
	}

	#>>>
	destructor { #<<<
		after cancel $after_id
		foreach dom_obj [dict keys $inputs] {
			my detach_input $dom_obj
		}
	}

	#>>>

	method tip {args} { #<<<
		if {$lock > 0} return

		if {$after_id ne ""} return
		my _debug debug "tlc::Domino::tip: ([self]) ($name)"
		set after_id	[after $delay [my code _tip_outputs]]
	}

	#>>>
	method tip_now {args} { #<<<
		my _tip_outputs
	}

	#>>>
	method attach_output {handler} { #<<<
		if {$handler ni $outputs} {
			lappend outputs $handler
			return 1
		} else {
			return 0
		}
	}

	#>>>
	method detach_output {handler} { #<<<
		set idx		[lsearch $outputs $handler]
		set outputs	[lreplace $outputs $idx $idx]
	}

	#>>>
	method attach_input {dom_obj} { #<<<
		if {![info object isa typeof $dom_obj m2::domino]} {
			error "$dom_obj isn't a m2::domino"
		}

		dict set inputs $dom_obj	1

		return [$dom_obj attach_output [my code tip]]
	}

	#>>>
	method detach_input {dom_obj} { #<<<
		if {![info object isa typeof $dom_obj m2::domino]} {
			error "$dom_obj isn't a Domino"
		}

		dict unset inputs $dom_obj

		return [$dom_obj detach_output [my code tip]]
	}

	#>>>
	method pending {} { #<<<
		expr {$after_id ne ""}
	}

	#>>>
	method force_if_pending {} { #<<<
		if {$after_id ne ""} {my tip_now}
	}

	#>>>
	method lock {} { #<<<
		incr lock
	}

	#>>>
	method unlock {} { #<<<
		incr lock -1
		if {$lock < 0} {
			puts stderr "[self] lock went below zero!: $lock"
		}
	}

	#>>>

	method _debug {level msg} { #<<<
#		invoke_handlers debug $level $msg
	}

	#>>>
	method _tip_outputs {} { #<<<
		after cancel $after_id
		set after_id	""
		foreach output $outputs {
			try {
				uplevel #0 $output
			} on error {errmsg options} {
				my log error "\nerror updating output ($output):\n\t$errmsg\n[dict get $options -errorinfo]"
			}
		}
	}

	#>>>
	method _scopevar_unset {args} { #<<<
		my log debug
		delete object [self]
	}

	#>>>
}



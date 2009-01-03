# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create m2::refcounted {
	constructor {} {
		set refcount	1
	}

	destructor {
		my _clear_registry
	}

	variable {*}{
		refcount
		registry_var
	}

	method object_registry {varname} { #<<<
		my _clear_registry

		set registry_var	$varname
		upvar $registry_var var_ref

		set var_ref		[self]
	}

	#>>>
	method incref {args} { #<<<
		set old		$refcount
		incr refcount
		my log_cmd debug "[self]: refcount $old -> $refcount ($args)"
	}

	#>>>
	method decref {args} { #<<<
		set old		$refcount
		incr refcount -1
		my log_cmd debug "[self]: refcount $old -> $refcount ($args)"
		if {$refcount <= 0} {
			my log_cmd debug "[self]: our time has come"
			my destroy
			return
		}
	}

	#>>>
	method refcount {} { #<<<
		return $refcount
	}

	#>>>

	method log_cmd {lvl msg args} {}
	method autoscoperef {} { #<<<
		my log_cmd debug "[self class]::[self method] callstack: (callstack dump broken)"
		upvar 2 _m2_refcounted_scoperef_[string map {:: //} [self]] scopevar
		set scopevar	[self]
		trace variable scopevar u [namespace code {my decref "scopevar unset"}]
	}

	#>>>
	method _clear_registry {} { #<<<
		if {[info exists registry_var]} {
			upvar $registry_var old_registry
			if {[info exists old_registry]} {
				unset old_registry
			}
		}
	}

	#>>>
}



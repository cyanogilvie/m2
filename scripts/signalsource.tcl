# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

m2::pclass create m2::signalsource {
	constructor {} { #<<<
		if {[self next] ne {}} {next}
		array set signals	{}
	}

	#>>>
	destructor { #<<<
		array unset signals
		if {[self next] ne {}} {next}
	}

	#>>>

	protected_property signals

	method signal_ref {signal} { #<<<
		if {![info exists signals($signal)]} {
			error "Invalid signal ($signal)" "" [list invalid_signal $signal]
		}
		return $signals($signal)
	}

	#>>>
	method signal_state {signal} { #<<<
		if {![info exists signals($signal)]} {
			error "Invalid signal ($signal)" "" [list invalid_signal $signal]
		}
		return [$signals($signal) state]
	}

	#>>>
	method waitfor {signal {timeout 0}} { #<<<
		if {![info exists signals($signame)]} {
			throw [list invalid_signal $signame] "Invalid signal ($signame)"
		}
		$signals($signame) waitfor true $timeout
	}

	#>>>
	method signals_available {} { #<<<
		set build	{}
		foreach signame [lsort -dictionary [array names signals]] {
			lappend build	$signame $signals($signame)
		}
		return $build
	}

	#>>>
}



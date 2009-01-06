# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

m2::pclass create m2::gate {
	superclass m2::signal

	pclass_config {
		constructor_auto_next	0
	}

	property mode		"or"	_mode_changed
	property default	0		_default_changed

	method _mode_changed {} { #<<<
		set valid_modes	{and nand nor or}
		if {$mode ni $valid_modes} {
			throw {PROPERTY INVALID} "-mode must be one of ([join $valid_modes {, }])"
		}
		my _calc_o_state
	}

	#>>>
	method _default_changed {} { #<<<
		my _calc_o_state
	}

	#>>>

	variable {*}{
		inputs
		sense
		isvar
		var_inputs
	}

	constructor {accessvar args} { #<<<
		upvar $accessvar scopevar
		next $accessvar

		set inputs		[dict create]
		set sense		[dict create]
		set isvar		[dict create]
		set var_inputs	{}

		my configure {*}$args
	}

	#>>>
	destructor { #<<<
		foreach var_input $var_inputs {
			my detach_var_input $var_input
		}
		foreach input [dict keys $inputs] {
			try {
				if {[my _isa_signal $input]} {
					$input detach_output [my code _input_update $input]
				}
			} on error {errmsg options} {
				puts stderr "Error detatching input ($input) during game destructor: $errmsg\n[dict get $options -errorinfo]"
			}
		}
	}

	#>>>
	
	method attach_input {gate_obj {a_sense normal}} { #<<<
		if {![my _isa_signal $gate_obj]} {
			error "$gate_obj isn't a m2::signal"
		}

		#$gate_obj register_handler debug [my code _debug]
		dict set sense $gate_obj	[expr {$a_sense ne "normal"}]

		return [$gate_obj attach_output [my code _input_update $gate_obj] \
				[my code _cleanup $gate_obj]]
	}

	#>>>
	method detach_input {gate_obj} { #<<<
		if {![my _isa_signal $gate_obj]} {
			error "$gate_obj isn't a m2::signal"
		}

		my _debug debug "tlc::Gate::detach_input ([self]): ($gate_obj)"

		set ok	[catch {unset inputs($gate_obj)} msg]
		dict unset inputs $gate_obj
		
		$gate_obj detach_output [my code _input_update $gate_obj]

		my _calc_o_state
	}

	#>>>
	method detach_all_inputs {} { #<<<
		foreach vinput $var_inputs {
			my detach_var_input $vinput
		}
		foreach gate_obj [dict keys $inputs] {
			detach_input $gate_obj
		}
	}

	#>>>
	method attach_var_input {varname {a_sense normal}} { #<<<
		if {$varname ni $var_inputs} {
			lappend var_inputs	$varname
		}
		dict set isvar [self]::$varname	$varname
		dict set sense [self]::$varname	[expr {$a_sense eq "inverted"}]
		trace add variable $varname {write unset} \
				[my code _var_input_update $varname]

		my _var_input_update $varname $varname "" write	
	}

	#>>>
	method detach_var_input {varname} { #<<<
		set idx			[lsearch $var_inputs $varname]
		set var_inputs	[lreplace $var_inputs $idx $idx]
		trace remove variable $varname {write unset} \
				[my code _var_input_update $varname]

		dict unset inputs [self]::$varname
		dict unset sense [self]::$varname
		dict unset isvar [self]::$varname

		my _calc_o_state
	}

	#>>>

	method explain_state {} { #<<<
		return $inputs
	}

	#>>>
	method explain_txt {{depth 0}} { #<<<
		set txt	""
		set firstdepth	[expr {($depth > 0) ? $depth-1 : 0}]
		append txt "[self] \"[[self] name]\": [[self] state]\[$default\] [string toupper [[self] cget -mode]] (\n"
		foreach key [dict keys $inputs] {
	#		append txt "[string repeat {  } $firstdepth]"
			append txt "[string repeat {  } $depth]"
			append txt [dict get $inputs $key]
			append txt [expr {[dict get $sense $key] ? "i" : " "}]
			if {[dict exists $isvar $key]} {
				append txt "[self] var_input: [dict get $isvar $key] ([dict get $inputs $key])\n"
			} else {
				append txt [$key explain_txt [expr {$depth + 1}]]
			}
		}
		append txt "[string repeat {  } $depth])\n"

		return $txt
	}

	#>>>

	method _calc_o_state {} { #<<<
		if {[dict size $inputs] == 0} {
			set new_o_state		$default
		} else {
			switch [string tolower $mode] {
				"and" - "nor"	{set assume	1}
				"nand" - "or"	{set assume	0}
			}

			dict for {input state} $inputs {
				switch [string tolower $mode] {
					"and" - "nand"	{
						if {!($state)} {
							set assume	[expr {!($assume)}]
							break
						}
					}

					"or" - "nor"	{
						if {$state} {
							set assume	[expr {!($assume)}]
							break
						}
					}
				}
			}

			set new_o_state		$assume
		}

		my set_state $new_o_state
	}

	#>>>
	method _input_update {gate_obj state} { #<<<
		if {[dict get $sense $gate_obj]} {
			set state	[expr {!$state}]
		}
		my _debug debug "tlc::Gate::input_update ([self]) ($name): ($gate_obj) ($state)"
		dict set inputs $gate_obj	$state

		my _calc_o_state
	}

	#>>>
	method _var_input_update {varname n1 n2 op} { #<<<
		upvar $varname value
		switch $op {
			write {
				if {![info exists value]} {
					error "var doesn't exist!  ($varname)"
				}
				set state	[expr {
					[string is boolean $value] && $value
				}]
				if {[dict get $sense [self]::$varname]} {
					set state	[expr {!($state)}]
				}
				dict set inputs [self]::$varname $state

				my _calc_o_state
			}

			unset {
				my detach_var_input $varname
			}
		}
	}

	#>>>
	method _cleanup {gate_obj} { #<<<
		my detach_input $gate_obj
	}

	#>>>
	method _isa_signal {obj} { #<<<
		expr {
			[info object isa typeof $obj m2::signal] ||
			([itcl::is object $obj] && [$obj isa tlc::Signal])
		}
	}

	#>>>
}



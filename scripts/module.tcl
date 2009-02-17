# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

cflib::pclass create m2::module {
	superclass cflib::baselog sop::signalsource

	property auth			""
	property svc			""
	property local			"modules"
	property cachebase		"cache"
	property pool			"client"
	property onmounted		{}
	property onunmounted	{}

	variable {*}{
		modulebase
		module_ns
		connector
		vfs
		on_unmount
		loaded_files
		moduledata
		signals
	}

	constructor {args} { #<<<
		my log debug [self]

		set on_unmount		{}

		sop::gate new signals(mounted) -name "[self] mounted" -mode and
		sop::signal new signals(ready) -name "[self] ready"

		package require cachevfs

		array set loaded_files	{}
		array set moduledata	{}

		my configure {*}$args

		foreach reqf {auth svc} {
			if {![set $reqf] eq ""} {
				throw [list missing_field $reqf] "Must set -$reqf"
			}
		}

		set modulebase	[file join $local $svc $pool]
		set module_ns	"[namespace current]::svc,${svc}::$pool"

		set connector	[$auth connect_svc $svc]
		[$connector signal_ref authenticated] attach_output \
				[my code _authenticated_changed]

		set signals(authenticated)	[$connector signal_ref authenticated]
	}

	#>>>
	destructor { #<<<
		my log debug [self]
		if {[info exists connector] && [info object isa object $connector]} {
			$connector detach_output [my code _authenticated_changed]
		}
		if {[info exists vfs] && [info object isa object $vfs]} {
			$vfs destroy
			unset vfs
		}

		if {$on_unmount ne {}} {
			namespace eval [namespace current]::svc,$svc $on_unmount
		}
	}

	#>>>

	method moduledata {key args} { #<<<
		switch -- [llength $args] {
			0 {
				if {[info exists moduledata($key)]} {
					return $moduledata($key)
				} else {
					throw [list invalid_moduledata_key $key] \
							"No moduledata for key: \"$key\""
				}
			}

			1 {
				set value				[lindex $args 0]
				set moduledata($key)	$value

				return $value
			}

			default {
				error "Invalid syntax"
			}
		}
	}

	#>>>
	method require {fn args} { #<<<
		switch -- [llength $args] {
			0 {set ns	$module_ns}
			1 {set ns	"${module_ns}::[lindex $args 0]"}
			default {
				throw {syntax_error} \
						"Too many arguments, must be require <file> ?ns?"
			}
		}
		if {![info exists loaded_files($fn)]} {
			namespace eval $ns [list source [file join $modulebase $fn]]
			set loaded_files($fn)	1
		}
	}

	#>>>
	method register_view {name command {icon ""}} { #<<<
	}

	#>>>
	method modulebase {} { #<<<
		return $modulebase
	}

	#>>>
	method ns {} { #<<<
		return $module_ns
	}

	#>>>

	method _authenticated_changed {newstate} { #<<<
		if {$newstate} {
			set vfs	[cachevfs::mount new -connector $connector \
					-cachedir [file join $cachebase $svc $pool] -pool $pool \
					-local $modulebase]

			$signals(mounted) attach_input [$vfs signal_ref mounted]

			my log debug "Initiated mount of pool $pool in \"$modulebase\" pwd: \"[pwd]\""

			[$vfs signal_ref mounted] attach_output [my code _on_mounted]
		} else {
			try {
				if {[info exists vfs] && [info object isa object $vfs]} {
					$vfs destroy
					unset vfs
				}

				if {$on_unmount ne {}} {
					namespace eval $module_ns $on_unmount
				}
			} on error {errmsg options} {
				my log error "Unhandled error: $errmsg\n[dict get $options -errorinfo]"
			}
		}
	}

	#>>>
	method _on_mounted {newstate} { #<<<
		if {$newstate} {
			if {$onmounted ne {}} {
				apply $onmounted $modulebase
			} else {
				set on_unmount_fn	[file join $modulebase on_unmount.tcl]
				set on_login_fn		[file join $modulebase onlogin.tcl]

				if {[file exists $on_unmount_fn]} {
					set on_unmount	[cflib::readfile $on_unmount_fn]
				} else {
					set on_unmount	""
				}

				if {[file exists $on_login_fn]} {
					namespace eval $module_ns {}
					interp alias {} [list ${module_ns}::module] {} [list [self]]
					set dat	[cflib::readfile $on_login_fn]
					namespace eval \
							$module_ns [list source $on_login_fn]
				} else {
					my log error "Missing bootstrap file: \"$on_unmount_fn\" for svc \"$svc\""
				}
			}
			$signals(ready) set_state 1
		} else {
			$signals(ready) set_state 0
			if {$onunmounted ne {}} {
				apply $onunmounted $modulebase
			} else {
				if {[info exists on_unmount] && $on_unmount ne ""} {
					namespace eval \
							$module_ns $on_unmount
				}
			}
		}
	}

	#>>>
}



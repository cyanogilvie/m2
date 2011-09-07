# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create Admin_console {
	variable {*}{
		listener
	}

	constructor {} { #<<<
		if {[self next] ne ""} next

		if {"::oo::Helpers::cflib" ni [namespace path]} {
			namespace path [concat [namespace path] {
				::oo::Helpers::cflib
			}]
		}

		my _load_cmds [cflib::readfile [file join $::here admin_cmds.tcl]]

		package require netdgram

		set listener	[netdgram::listen_uri [cfg @admin_console]]
		oo::objdefine $listener forward accept {*}[code _accept]
		log notice "Admin console listening on ([cfg @admin_console])"
	}

	#>>>
	destructor { #<<<
		if {[info exists listener] && $listener in [chan names]} {
			chan close $listener
			unset listener
		}
		if {[self next] ne ""} next
	}

	#>>>

	method _accept {con args} { #<<<
		oo::objdefine $con forward received {*}[code _received $con]
		oo::objdefine $con forward closed {*}[code _closed $con]
		log notice "Admin console connection from \"[$con human_id]\""
		$con activate
		$con send [list version [package require m2] capabilities [my _caps]]
	}

	#>>>
	method _received {con msg} { #<<<
		log debug "Received from [$con human_id]: \"$msg\""
		try {
			set rest	[lassign $msg type id]
			switch -- $type {
				cmd {
					{*}cmds {*}$rest
				}

				default {
					throw invalid_type "Type invalid: \"$type\""
				}
			}
		} on ok {res options} {
			$con send [list resp $id $options $res]
		} on error {errmsg options} {
			$con send [list resp $id $options $errmsg]
		}
	}

	#>>>
	method _closed con { #<<<
		log notice "Admin console connection from \"[$con human_id]\" disconnected"
	}

	#>>>
	method _caps {} { #<<<
		lsort -unique [concat [cmds capabilities] {basic_cmds}]
	}

	#>>>
	method _load_cmds script { #<<<
		if {[namespace exists cmds]} {
			namespace delete cmds
		}
		namespace eval cmds {
			namespace export *
			namespace ensemble create

			proc capabilities {} {list}
		}
		namespace eval cmds $script
	}

	#>>>
}

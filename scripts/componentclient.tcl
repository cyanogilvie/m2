# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

cflib::pclass create m2::componentclient {
	superclass cflib::baselog

	property status_feedback	0
	property auth				""	_auth_changed

	variable {*}{
		component_svr
		svc
		auth_set
	}

	constructor {a_svc} { #<<<
		set auth_set	0
		set svc			$a_svc
		my log debug "svc: $svc"
	}

	#>>>
	destructor { #<<<
		my log debug "svc: [expr {[info exists svc] ? $svc : {not set}}]"
		if {[info exists component_svr]} {
			catch {$component_svr destroy}
			unset component_svr
		}
	}

	#>>>

	method connector {} { #<<<
		return $component_svr
	}

	#>>>

	# Protected
	method authenticated_changed {newstate} { #<<<
		my log warning "called virtual method of baseclass!"
		# Override in derived class
	}

	#>>>

	method _auth_changed {} { #<<<
		if {$auth_set} {
			error "Cannot reconfigure -auth"
		}
		set auth_set	1

		set component_svr	[$auth connect_svc $svc]
		[$component_svr signal_ref authenticated] attach_output \
				[my code authenticated_changed]
		if {
			$status_feedback &&
			![$component_svr signal_state authenticated]
		} {
			# Blegh
			Waitforgui .#auto -title "Waiting to be connected to $svc server" \
					-signalsource $component_svr -signal authenticated
		}
	}

	#>>>
}



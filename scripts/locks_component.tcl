# vim: foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4 ft=tcl

# Signals fired:
#	aquire_lock(user, id)			- Fired when a lock is requested,
#									throw an error to reject the request
#	lock_aquired(user, id)			- Fired when a lock is aquired
#	lock_released(id)				- Fired when a lock is released
#	lock_released_user(user, id)	- Fired when a lock is released
#	lock_req_<op>(id, auth, user, seq, reqdata)
#									- Fired when a lock request of type
#									<op> arrives on a lock channel

cflib::pclass create m2::locks::component {
	superclass cflib::handlers cflib::baselog

	property comp			""
	property tag			""
	property heartbeat		"180"

	variable {*}{
		locks
	}

	constructor {args} { #<<<
		set locks	[dict create]

		my configure {*}$args

		foreach reqf {comp tag} {
			if {[set $reqf] eq ""} {
				error "Must set -$reqf"
			}
		}

		$comp handler $tag [my code _getlock]
	}

	#>>>
	destructor { #<<<
		set auth	[$comp cget -auth]
		dict for {key val} $locks {
			after cancel [dict get $val heartbeat]
			dict set locks $key heartbeat ""
			$auth jm_can [dict get $val jmid] ""
			dict unset locks $key
		}
	}

	#>>>

	method breaklock {id} { #<<<
		if {![dict exists $locks $id]} {
			throw [list no_lock $id] "No lock info for $id"
		}
		set jmid	[dict get $locks $id jmid]
		set holder	[dict get $locks $id userobj]

		[$comp cget -auth] jm_can $jmid ""
		after cancel [dict get $locks $id heartbeat]
		dict unset locks $id

		try {
			my invoke_handlers lock_released $id
			my invoke_handlers lock_released_user $holder $id
		} on error {errmsg options} {
			my log error "\nerror in lock_released handlers for id ($id): $errmsg\n[dict get $options -errorinfo]"
		}
	}

	#>>>
	method locked {id} { #<<<
		dict exists $locks $id
	}

	#>>>
	method who_holds {id} { #<<<
		if {![dict exists $locks $id]} {
			throw [list no_lock $id] "No lock info for $id"
		}
		dict get $locks $id userobj
	}

	#>>>
	method held_by {username} { #<<<
		set ids	{}
		dict for {id info} $locks {
			if {[dict get $info username] eq $username} {
				lappend ids	$id
			}
		}

		return $ids
	}

	#>>>

	method _getlock {auth user seq rest} { #<<<
		set id		$rest
		
		if {[dict exists $locks $id]} {
			set userobj		[dict get $locks $id userobj]
			set username	[dict get $locks $id username]
			my log notice "request to lock ($id) by ([$user name]) rejected - lock already held by ($username)"
			$auth nack $seq "Already locked by $username"
			return
		}

		try {
			my invoke_handlers aquire_lock $user $id
		} trap {response error} {errmsg options} {
			my log notice "request to lock ($id) by ([$user name]) rejected - aquire_lock threw error: $errmsg\n[dict get $options -errorinfo]"
			$auth nack $seq $errmsg
			return
		} on error {errmsg options} {
			my log notice "request to lock ($id) by ([$user name]) rejected - aquire_lock threw error: $errmsg\n[dict get $options -errorinfo]"
			$auth nack $seq "Lock denied"
			return
		}

		set new_jmid	[$auth unique_id]

		$auth pr_jm $new_jmid $seq ""
		$auth chans register_chan $new_jmid \
				[my code _lock_cb $user [$user name] $id]

		dict set locks $id jmid			$new_jmid
		dict set locks $id userobj		$user
		dict set locks $id username		[$user name]
		if {$heartbeat ne ""} {
			dict set locks $id heartbeat \
					[after [expr {round($heartbeat * 1000)}] \
					[my code breaklock $id]]
		} else {
			dict set locks $id heartbeat	""
		}

		$auth ack $seq [dict create heartbeat $heartbeat]
		my invoke_handlers lock_aquired $user $id
	}

	#>>>
	method _lock_cb {user un id type rest} { #<<<
		switch -- $type {
			cancelled { #<<<
				if {![dict exists $locks $id]} {
					# We were already unlocked, perhaps by a component breaklock
					return
				}

				set holder	[dict get $locks $id userobj]

				my log debug "lock on ($id) held by user ($un) cancelled"
				after cancel [dict get $locks $id heartbeat]
				dict unset locks $id

				try {
					my invoke_handlers lock_released $id
					my invoke_handlers lock_released_user $holder $id
				} on error {errmsg options} {
					my log error "\nerror in lock_released handlers for id ($id): $errmsg\n[dict get $options -errorinfo]"
				}
				#>>>
			}
			req { #<<<
				lassign $rest seq prev_seq msg auth
				lassign $msg op reqdata

				my _reset_heartbeat $id
				if {$op eq "_heartbeat"} {
					$auth ack $seq ""
					return
				}

				if {![dict exists $locks $id]} {
					my log error "Got req on a lock_cb that had already been unlocked!"
					$auth nack $seq "Lock not held anymore"
					return
				}

				if {![my handlers_available lock_req_$op]} {
					my log error "no handlers registered for req type ($op)"
					$auth nack $seq "Invalid op: ($op)"
					return
				}

				try {
					my invoke_handlers lock_req_$op $id $auth $user $seq $reqdata
				} on error {errmsg options} {
					default {
						my log error "\nerror invoking handlers for lock_req_$op: $errmsg\n[dict get $options -errorinfo]"
						$auth nack $seq "Internal error"
					}
				}
				#>>>
			}
			default { #<<<
				error "Invalid type: ($type)"
				#>>>
			}
		}
	}

	#>>>
	method _reset_heartbeat {id} { #<<<
		if {![dict exists $locks $id]} return

		after cancel [dict get $locks $id heartbeat]
		dict set locks $id heartbeat	[after [expr {$heartbeat * 1000}] \
				[my code breaklock $id]]
	}

	#>>>
}



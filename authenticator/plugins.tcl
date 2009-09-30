# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

# Manage the set of auth delegation plugins

oo::class create Plugins {
	superclass cflib::baselog

	variable {*}{
		plugins
	}

	constructor {} { #<<<
		if {[self next] ne {}} next

		set plugins	{}
	}

	#>>>
	destructor { #<<<
		my _unload_plugins

		if {[self next] ne {}} next
	}

	#>>>

	method plugin_command {plugin_name params command args} { #<<<
		set pinf	[my _require_plugin $plugin_name $params]

		set slave	[dict get $pinf slave]

		$slave eval [list plugin $command {*}$args]
	}

	#>>>

	method _require_plugin {plugin_name params} { #<<<
		set fn		[my _name2file $plugin_name] 

		set last_changed	[file mtime $fn]
		if {[dict exists $plugins $plugin_name $params]} {
			set pinf	[dict get $plugins $plugin_name $params]
			if {$last_changed eq [dict get $pinf last_changed]} {
				return $pinf
			} else {
				my _unload_plugin $plugin_name $params
			}
		}

		set ok	0
		try {
			set slave	[interp create]

			my _init_slave $slave

			try {
				$slave eval [list source $fn]
				$slave eval [list Plugin create plugin {*}$params]
			} on error {errmsg options} {
				error $errmsg $::errorInfo {load_problem}
			}

			if {
				![$slave eval {expr {
					[info commands plugin] eq "plugin" &&
					[info object isa object plugin] &&
					[info object isa typeof plugin pluginbase]
				}}]
			} {
				throw {bad_interface} ""
			}

			dict set plugins $plugin_name $params [dict create \
					slave			$slave \
					last_changed	$last_changed \
			]
		} trap {load_problem} {errmsg options} {
			my log error "Plugin $plugin_name cannot be loaded: $errmsg\n[dict get $options -errorinfo]"
		} trap {bad_interface} {errmsg options} {
			my log error "Plugin $plugin_name does not implement a pluginbase called plugin"
		} on error {errmsg options} {
			my log error "Error initializing plugin $plugin_name: $errmsg\n[dict get $options -errorinfo]"
		} on ok {} {
			set ok	1
			dict get $plugins $plugin_name $params
		} finally {
			if {!($ok)} {
				if {[info exists slave] && [interp exists $slave]} {
					try {
						interp delete $slave
					} on error {errmsg options} {
						my log error "Error destroying plugin:\n[dict get $options -errorinfo]"
					}
				}
			}
		}
	}

	#>>>
	method _unload_plugin {plugin_name params} { #<<<
		if {![dict exists $plugins $plugin_name $params]} {
			my log warning "No plugin loaded for \"$plugin_name\" \"$params\""
			return
		}
		set slave	[dict get $plugins $plugin_name $params slave]
		try {
			$slave eval {plugin destroy}
		} on error {errmsg options} {
			my log error "Error unloading plugin \"$plugin_name\": $errmsg\n[dict get $options -errorinfo]"
		}
		interp delete $slave
		dict unset plugins $plugin_name $params
	}

	#>>>
	method _unload_plugins {} { #<<<
		dict for {plugin_name params} $plugins {
			my _unload_plugin $plugin_name $params
		}
	}

	#>>>
	method _init_slave {slave} { #<<<
		$slave eval {
			oo::class create pluginbase {
				method check_auth {username subdomain credentials} { #<<<
					# Override this in the plugin implementation
					# return boolean, true = credentials ok
					throw {not_supported} "Not supported"
				}

				#>>>
				method get_info {username subdomain} { #<<<
					# Override this in the plugin implementation return a dict,
					# with keys for attribs, perms and prefs formatted as a
					# mergearray, mergelist and mergearray respectively
					# Optionally also return profilenames in the dict, which
					# must be a mergearray
					throw {not_supported} "Not supported"
				}

				#>>>
				method set_pref {username subdomain pref newvalue} { #<<<
					# Override this in the plugin implementation
					# Set the pref to the indicated value or throw an error
					throw {not_supported} "Not supported"
				}

				#>>>
				method change_credentials {username subdomain old_credentials new_credentials} { #<<<
					# Override this in the plugin implementation
					# It is up to the implementation to verify that the old
					# credentials are valid.
					# Set the credentials to the indicated value or throw an
					# error
					# throw errorcode "denied" to have the $errmsg used as the
					# message to the user
					throw {not_supported} "Not supported"
				}

				#>>>
				method normalize_username {username} { #<<<
					# Optionally override this in the plugin implementation to
					# provide a normalized version of the username (like
					# forced-lower-case, etc)
					return $username
				}

				#>>>

				method log {lvl msg args} { #<<<
					puts stderr $msg
				}

				unexport log
				#>>>
			}
		}
	}

	#>>>
	method _name2file {plugin_name} { #<<<
		set basic	[file tail $plugin_name]
		set fq		[file join [cfg get plugin_dir] $plugin_name]

		if {[file extension $fq] eq ""} {
			if {![file exists $fq]} {
				# If the name doesn't exist and doesn't have an extension,
				# try .tcl
				append fq	".tcl"
			}
		}

		if {![file exists $fq]} {
			throw [list invalid_plugin $plugin_name] \
					"No plugin registered for \"$plugin_name\""
		}

		return $fq
	}

	#>>>
}



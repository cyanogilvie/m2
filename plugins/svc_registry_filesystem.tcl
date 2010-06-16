namespace eval dsl {}

proc dsl::decomment {in} { #<<<
	set out	""

	foreach line [split $in \n] {
		if {[string index [string trim $line] 0] eq "#"} continue
		append out	$line "\n"
	}

	return $out
}

#>>>
proc dsl::dsl_eval {interp dsl_commands dsl_script args} { #<<<
	set aliases_old	{}
	foreach {cmdname cmdargs cmdbody} [dsl::decomment $dsl_commands] {
		dict set aliases_old $cmdname [$interp alias $cmdname]

		$interp alias $cmdname apply [list $cmdargs $cmdbody [uplevel {namespace current}]] {*}$args
	}

	try {
		$interp eval $dsl_script
	} finally {
		dict for {cmdname oldalias} $aliases_old {
			$interp alias $cmdname $oldalias
		}
	}
}

#>>>

oo::class create cflib::config { #<<<
	variable {*}{
		definitions
		cfg
		rest
	}

	constructor {argv config} { #<<<
		set cfg	[dict create]

		set slave	[interp create -safe]
		try {
			dsl::dsl_eval $slave {
				variable {definitionsvar varname default} { #<<<
					dict set $definitionsvar $varname default $default
				}

				#>>>
			} $config [namespace which -variable definitions]
		} finally {
			if {[interp exists $slave]} {
				interp delete $slave
			}
		}

		set mode	"key"
		set rest	{}
		foreach arg $argv {
			switch -- $mode {
				key {
					if {[string index $arg 0] eq "-"} {
						set key	[string range $arg 1 end]
						if {![dict exists $definitions $key]} {
							throw [list bad_config_setting $key] \
									"Invalid config setting: \"$key\""
						}
						set mode	"val"
					} else {
						lappend rest	$arg
					}
				}

				val {
					dict set cfg $key $arg
					set mode	"key"
				}
			}
		}

		dict for {k v} $definitions {
			if {![dict exists $cfg $k]} {
				dict set cfg $k [dict get $definitions $k default]
			}
		}
	}

	#>>>
	method get {key args} { #<<<
		switch -- [llength $args] {
			0 {
				if {![dict exists $cfg $key]} {
					throw [list bad_config_setting $key] \
							"Invalid config setting: \"$key\""
				}
				return [dict get $cfg $key]
			}

			1 {
				if {[dict exists $cfg $key]} {
					return [dict get $cfg $key]
				} else {
					return [lindex $args 0]
				}
			}

			default {
				error "Too many arguments: expecting key ?default?"
			}
		}
	}

	#>>>
	method rest {} { #<<<
		return $rest
	}

	#>>>
}

#>>>

oo::class create Plugin {
	superclass pluginbase

	variable {*}{
		svc_dir
		cfg
	}

	constructor {args} { #<<<
		if {[self next] ne ""} next

		set cfg	[cflib::config new $args {
			variable svc_dir		"/etc/codeforge/svcs"
		}]

		if {
			![file readable [$cfg get svc_dir]]
		} {
			error "Svc registry path \"[$cfg get svc_dir]\" isn't readable"
		}
	}

	#>>>
	method check_auth {username subdomain credentials} { #<<<
		log debug "Got request to check username: ($username), subdomain: ($subdomain), credentials: ($credentials)"
		return 0
	}

	#>>>
	method get_info {username subdomain} { #<<<
		log debug "Got request to provide info for username: ($username), subdomain: ($subdomain)"
		dict create \
				attribs	{} \
				perms	{} \
				prefs	{}
	}

	#>>>
}


# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

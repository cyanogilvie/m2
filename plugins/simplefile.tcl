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
		cfg
		default_details
	}

	constructor {args} { #<<<
		if {[self next] ne ""} next

		set default_details	[dict create \
				attribs	{} \
				perms	{} \
				prefs	{} \
		]

		cflib::config create cfg $args {
			variable fn			"/etc/codeforge/users"
			variable detailsfn	"/etc/codeforge/userdetails"
			variable ignorecase	{}	;# list of "username", "password"
			variable hashed		0
		}

		if {![file readable [cfg get fn]]} {
			error "User file \"[cfg get fn]\" isn't readable"
		}
	}

	#>>>
	method check_auth {username subdomain credentials} { #<<<
		set fp	[open [cfg get fn] r]
		try {
			foreach line [split [chan read $fp] \n] {
				set line	[string trim $line]
				if {[string index $line 0] eq "#"} continue
				if {$line eq ""} continue
				lassign [split $line :] un pw
				if {"username" in [cfg get ignorecase]} {
					if {[string tolower $username] eq [string tolower $un]} {
						return [my _check_pw $credentials $pw]
					}
				} else {
					if {$username eq $un} {
						return [my _check_pw $credentials $pw]
					}
				}
			}

			return 0
		} finally {
			chan close $fp
		}
	}

	#>>>
	method _check_pw {pw1 pw2} { #<<<
		if {[cfg get hashed]} {
			set pw1	[binary encode base64 [hash::md5 $pw1]]
		}
		expr {
			$pw1 eq $pw2
		}
	}

	#>>>
	method get_info {username subdomain} { #<<<
		log debug "get_info for \"$username\" subdomain: \"$subdomain\" ------------"
		if {![file readable [cfg get detailsfn]]} {
			log warning "details file \"[cfg get detailsfn]\" doesn't exist"
			return $default_details
		}

		set dat	[dsl::decomment [my _readfile [cfg get detailsfn]]]

		if {[dict exists $dat $username]} {
			log debug "Returning attribs for \"$username\": [dict get $dat $username]"
			dict get $dat $username
		} else {
			set default_details
		}
	}

	#>>>
	method _readfile {fn} { #<<<
		set h	[open $fn r]
		try {
			chan read $h
		} finally {
			chan close $h
		}
	}

	#>>>
}

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

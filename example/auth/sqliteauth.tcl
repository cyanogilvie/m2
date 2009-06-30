# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require cflib

oo::class create Plugin {
	superclass oo::pluginbase

	variable {*}{
		db
		cfg
	}

	constructor {args} { #<<<
		if {[self next] ne ""} next

		set cfg	[cflib::config new $args {
			variable dbfile		""
			variable ignorecase	{}	;# list of "username", "password"
		}]

		if {[$cfg get dbfile] eq ""} {
			error "Must supply -dbfile"
		}

		set db	[string map {:: _} [self]_db
		sqlite3 $db [$cfg get dbfile]
	}

	#>>>
	destructor { #<<<
		if {[info exists db] && [info commands $db] eq $db} {
			$db close
			unset db
		}
	}

	#>>>

	method check_auth {username subdomain credentials} { #<<<
		set found	0
		db eval {
			select
				
		}
	}

	#>>>
}



# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require crypto
package require cflib

cflib::config create cfg $argv {
	variable debug		0
}

set cmd	[file tail $argv0]
namespace eval $cmd {
	namespace export *
	namespace ensemble create

	proc generate {{keysize 1024} {e 0x10001}} { #<<<
		set K	[crypto::rsa::RSAKG $keysize [expr {$e+0}]]
		puts $K
	}

	#>>>
	proc extract_public_key {{filename -}} { #<<<
		if {$filename eq "-"} {
			set h	stdin
		} else {
			set h	[open $filename r]
		}
		set K	[string trim [chan read $h]]
		if {$filename ne "-"} {
			chan close $h
		}
		try {
			dict keys $K
		} on ok {keys} {
		} on error {} {
			throw fail "Invalid key format: $K"
		}
		if {[lsort $keys] ne [lsort [list n e d p q dP dQ qInv]]} {
			throw fail "Invalid key format: $keys"
		}

		puts [dict filter $K script {k v} {expr {$k in {n e}}}]
	}

	#>>>
}

try {
	$cmd {*}[cfg rest]
} on ok {} {
	exit 0
} trap {TCL WRONGARGS} {errmsg} \
- trap {TCL LOOKUP SUBCOMMAND} {errmsg} {
	puts stderr $errmsg
	exit 2
} trap {fail} {errmsg} {
	puts stderr $errmsg
	exit 2
} on error {errmsg options} {
	if {[cfg get debug]} {
		puts stderr [dict get $options -errorcode]
		puts stderr [dict get $options -errorinfo]
	} else {
		puts stderr "Unexpected error: $errmsg"
	}
	exit 3
}

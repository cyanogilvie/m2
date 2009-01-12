package require starkit
if {[starkit::startup] == "sourced"} return

set here	[file dirname [info script]]
::tcl::tm::path add [file join $here tm]
lappend auto_path [file join $here lib]

source [file join $here "m2_node"]

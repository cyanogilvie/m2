package require Tcl 8.6
package require cflib
package require sop
package require netdgram

namespace eval m2 {}

if {[info commands ??] ne {??}} {
	proc ?? {args} {}
}

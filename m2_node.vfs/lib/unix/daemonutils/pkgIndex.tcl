
# @@ Meta Begin
# Package daemon 0.4
# Meta description 
# Meta platform    linux-glibc2.3-ix86
# @@ Meta End


if {![package vsatisfies [package provide Tcl] 8.4]} return

package ifneeded daemon 0.4 [string map [list @ $dir] {
            load [file join {@} libdaemon0.4.so] daemon

        # ACTIVESTATE TEAPOT-PKG BEGIN DECLARE

        package provide daemon 0.4

        # ACTIVESTATE TEAPOT-PKG END DECLARE
    }]

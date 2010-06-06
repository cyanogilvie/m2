#!/usr/bin/env kbskit8.6-gui

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require Tk
wm withdraw .

package require sop
package require netdgram::tcp
package require m2
package require cflib

m2::api2 create m2 -uri "tcp://localhost:5300"

cd [file dirname [info script]]

source "gui.tcl"

gui create main -title "Test chat client"
main show

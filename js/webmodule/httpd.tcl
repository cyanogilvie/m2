# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require cflib
package require oodaemons 0.3
package require oodaemons::httpd 0.3

if {[info commands ::??] ne "::??"} {
	proc ?? {args} {}
}

cflib::pclass create webmodule::httpd {
	superclass oodaemons::httpd

	property docroot "docroot"

	method get {relfile} { #<<<
		set fqfn	[my _resolve_path $relfile]
		if {![file exists $fqfn]} {
			throw not_found "File not found"
		}
		if {![file readable $fqfn]} {
			throw forbidden "Permission denied to read file"
		}
		lassign [my _mime_info $fqfn] \
				mode \
				mimetype

		if {$mode eq "text" || $mimetype in {
			application/javascript
			application/xhtml+xml
		}} {
			set data	[cflib::readfile $fqfn text]
			set encoding	utf-8
		} else {
			set data	[cflib::readfile $fqfn binary]
			set encoding	binary
		}

		?? {log debug "httpd::get \"$relfile\" returning [string length $data] bytes, encoding: ($encoding), mimetype: ($mimetype)"}
		list $data $encoding $mimetype
	}

	#>>>
	method got_req {req} { #<<<
		set uri	[$req request_uri]

		?? {log debug "Got request for path: \"[$uri path]\""}

		try {
			my _resolve_path [string trimleft [$uri path] /]
		} trap not_found {errmsg} {
			$req send_response [dict create \
					code			404 \
					response-data	"Requested file not found" \
			]
			return
		} on ok {fqfn} {}

		lassign [my _mime_info $fqfn] mode mimetype

		if {$mode eq "text" || $mimetype in {
			application/javascript
			application/xhtml+xml
		}} {
			# TODO: check if Accept-Charset header allows utf-8
			$req send_response [dict create \
					mimetype			$mimetype \
					content-encoding	"utf-8" \
					response-data		[cflib::readfile $fqfn text] \
			]
		} else {
			$req send_response [dict create \
					mimetype			$mimetype \
					content-encoding	binary \
					response-data		[cflib::readfile $fqfn binary] \
			]
		}
	}

	#>>>
	method _resolve_path {relpath} { #<<<
		set fqbase	[file normalize $docroot]
		set fqfn	[file join $fqbase $relpath]

		if {![file exists $fqfn]} {
			throw not_found "Not found"
		}

		return $fqfn
	}

	#>>>
	method _mime_info {fqpath} { #<<<
		set mimetypes	[oodaemons::mimetypes new]	;# oodaemons::mimetypes is a singleton
		set mimetype	[$mimetypes for_path $fqpath "text/plain"]

		lassign [split $mimetype /] type
		if {$type eq "text"} {
			return [list text $mimetype]
		} else {
			return [list binary $mimetype]
		}
	}

	#>>>
}


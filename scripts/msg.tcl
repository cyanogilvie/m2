# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create m2::msg {
	superclass m2::refcounted

	constructor {mode args} { #<<<
		next

		set dat	{
			svc			"sys"
			type		"req"
			seq			""
			prev_seq	0
			sell_by		""
			part		1
			of			1
			data		""
		}

		# Bind an automatic scopvar in our caller's stack frame to decref us
		# when it goes out of scope
		my autoscoperef

		switch -- $mode {
			new {
				set dat [dict merge $dat $args]
			}
			
			deserialize {
				my _deserialize [lindex $args 0]
			}
			
			clone {
				set dat	[[lindex $args 0] get_data]
			}

			raw {}

			default {
				error "Invalid mode: ($mode)"
			}
		}
	}

	#>>>

	variable {*}{
		dat
	}

	method serialize {} { #<<<
		set hdr			[list \
				[dict get $dat svc] \
				[dict get $dat type] \
				[dict get $dat seq] \
				[dict get $dat prev_seq] \
				[dict get $dat sell_by] \
				[dict get $dat part] \
				[dict get $dat of]]
		set sdata		[list 1 [string length $hdr] [string length [dict get $dat data]]]
		append sdata	"\n"
		append sdata	$hdr
		append sdata	[dict get $dat data]

		return $sdata
	}

	#>>>
	method shift_seqs {newseq} { #<<<
		dict set dat prev_seq	[dict get $dat seq]
		dict set dat seq		$newseq
	}

	#>>>
	method display {} { #<<<
		set display	""
		append display "Msg ([self]):\n"
		foreach attr {svc type seq prev_seq sell_by part of data} {
			if {$attr eq "data"} {
				append display "  $attr: \[[string length [dict get $dat $attr]]\]\n"
			} else {
				append display "  $attr: ([dict get $dat $attr])\n"
			}
		}

		return $display
	}

	#>>>
	method get_data {} { #<<<
		return $dat
	}

	#>>>
	method get {attr} { #<<<
		return [dict get $dat $attr]
	}

	#>>>
	method set {attr newval} { #<<<
		return [dict set dat $attr $newval]
	}

	#>>>
	method _accessor {attr args} { #<<<
		if {[llength $args] == 0} {
			return [my get $attr]
		} else {
			return [my set $attr {*}$args]
		}
	}

	#>>>

	method _deserialize {sdata} { #<<<
		set idx		[string first "\n" $sdata]
		if {$idx == -1} {
			error "Invalid serialized msg format"
		}
		set preend		[expr {$idx - 1}]
		set hdrstart	[expr {$idx + 1}]
		set pre			[string range $sdata 0 $preend]
		set fmt			[lindex $pre 0]
		switch -- $fmt {
			1 {
				set hdr_len		[lindex $pre 1]
				set data_len	[lindex $pre 2]
				set hdrend		[expr {$hdrstart + $hdr_len - 1}]
				set datastart	[expr {$hdrend + 1}]
				set dataend		[expr {$datastart + $data_len - 1}]
				set hdr			[string range $sdata $hdrstart $hdrend]
				dict set dat data	[string range $sdata $datastart $dataend]
				foreach h {svc type seq prev_seq sell_by part of} v $hdr {
					dict set dat $h	$v
				}
			}

			default {
				error "Don't know what to do with format: ($fmt)"
			}
		}
	}

	#>>>
}


oo::define m2::msg method svc {args}		{my _accessor [self method] {*}$args}
oo::define m2::msg method type {args}		{my _accessor [self method] {*}$args}
oo::define m2::msg method seq {args}		{my _accessor [self method] {*}$args}
oo::define m2::msg method prev_seq {args}	{my _accessor [self method] {*}$args}
oo::define m2::msg method sell_by {args}	{my _accessor [self method] {*}$args}
oo::define m2::msg method part {args}		{my _accessor [self method] {*}$args}
oo::define m2::msg method of {args}			{my _accessor [self method] {*}$args}
oo::define m2::msg method data {args}		{my _accessor [self method] {*}$args}


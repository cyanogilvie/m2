# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> foldmarker=<<<,>>>

namespace eval m2::msg {
	namespace path [concat [namespace path] {
		::tcl::mathop
	}]

	proc new {{initial {}}} { #<<<
		dict merge {
			svc			"sys"
			type		"req"
			seq			""
			prev_seq	0
			meta		""
			oob_type	1
			oob_data	1
			data		""
		} $initial
	}

	#>>>
	proc display {dat} { #<<<
		set display	""
		append display "Msg:\n"
		foreach attr {svc type seq prev_seq meta oob_type oob_data data} {
			if {$attr eq "data"} {
				package require hash
				append display "  $attr: [binary encode base64 [hash::md5 [dict get $dat $attr]]] \[[string length [dict get $dat $attr]]\]\n"
			} else {
				append display "  $attr: ([dict get $dat $attr])\n"
			}
		}

		set display
	}

	#>>>
	proc deserialize {sdata} { #<<<
		scan $sdata "%\[^\n\]%n" pre idx
		lassign $pre fmt hdr_len data_len
		if {$fmt ne "1"} {error "Don't know how to parse format ($fmt)"}
		set hdrend		[+ $idx $hdr_len]

		lassign [string range $sdata [+ $idx 1] $hdrend] \
			svc type seq prev_seq meta oob_type oob_data

		dict create \
				svc			$svc \
				type		$type \
				seq			$seq \
				prev_seq	$prev_seq \
				data		[string range $sdata [+ $hdrend 1] [+ $hdrend $data_len]] \
				meta		$meta \
				oob_type	$oob_type \
				oob_data	$oob_data
	}

	#>>>
	proc serialize {dat} { #<<<
		set data		[dict get $dat data]
		set hdr			[list \
				[dict get $dat svc] \
				[dict get $dat type] \
				[dict get $dat seq] \
				[dict get $dat prev_seq] \
				[dict get $dat meta] \
				[dict get $dat oob_type] \
				[dict get $dat oob_data]]
		return [list 1 [string length $hdr] [string length $data]]\n$hdr$data
	}

	#>>>
	proc shift_seqs {dat newseq} { #<<<
		dict set dat prev_seq [dict get $dat seq]
		dict set dat seq $newseq
	}

	#>>>
}

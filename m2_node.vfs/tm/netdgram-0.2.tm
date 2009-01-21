# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

# Connection method plugins must implement this API

package require TclOO 0.6

namespace eval netdgram {
	namespace path ::oo

	variable managers	[dict create]

	proc connect_uri {uri} { #<<<
		try {
			set uri_obj		[netdgram::uri new $uri]
			set uri_parts	[$uri_obj as_dict]

			set manager	[netdgram::_get_manager [dict get $uri_parts scheme]]

			return [$manager connect $uri_obj]
		} finally {
			if {[info exists uri_obj] && [info object is object $uri_obj]} {
				$uri_obj destroy
				unset uri_obj
			}
		}
	}

	#>>>
	proc listen_uri {uri} { #<<<
		try {
			set uri_obj		[netdgram::uri new $uri]
			set uri_parts	[$uri_obj as_dict]

			set manager	[netdgram::_get_manager [dict get $uri_parts scheme]]

			return [$manager listen $uri_obj]
		} finally {
			if {[info exists uri_obj] && [info object is object $uri_obj]} {
				$uri_obj destroy
				unset uri_obj
			}
		}
	}

	#>>>

	proc _get_manager {scheme} { #<<<
		variable managers

		if {![dict exists $managers $scheme]} {
			package require netdgram::$scheme
			dict set managers $scheme \
					[netdgram::connectionmethod::${scheme} new]
		}
		set manager	[dict get $managers $scheme]
	}

	#>>>

	class create debug { #<<<
		#filter _foolog
		method _foolog {args} { #<<<
			puts "Calling: [self] [join [self target] ->] $args"
			next {*}$args
		}

		#>>>
	}

	#>>>

	class create connectionmethod { #<<<
		mixin netdgram::debug

		method listen {uri_obj} {}		;# Returns netdgram::Listener instance
		method connect {uri_obj} {}		;# Returns netdgram::Connection instance
	}

	#>>>
	class create connection { #<<<
		mixin netdgram::debug

		# Forward / override these to add high level behaviour
		method human_id {} {return "not set: [self]"}
		method received {msg} {}
		method closed {} {}
		method writable {} {}

		method send {msg} {}
		method activate {} {}	;# Called when accept checks are passed
		method data_waiting {newstate} {}
	}

	#>>>
	class create listener { #<<<
		mixin netdgram::debug

		# Forward / override these to add high level behaviour
		method accept {con args} {}
		method human_id {} {return "not set: [self]"}
	}

	#>>>
}

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

namespace eval netdgram {
	namespace path ::oo

	class create queue {
		mixin netdgram::debug

		variable {*}{
			queues
			rawcon
			msgid_seq
			defrag_buf
			target_payload_size
			roundrobin
		}

		constructor {} { #<<<
			if {[self next] ne {}} {next}
			set queues		[dict create]
			set defrag_buf	[dict create]
			set msgid_seq	0
			set target_payload_size		10000
			set roundrobin				{}
			#set target_payload_size	1400
			#set target_payload_size	8
		}

		#>>>
		destructor { #<<<
			my closed

			if {[self next] ne {}} {next}
		}

		#>>>

		method attach {con} { #<<<
			set rawcon	$con

			oo::objdefine $rawcon forward writable \
					{*}[namespace code {my _rawcon_writable}]
			oo::objdefine $rawcon forward received \
					{*}[namespace code {my _receive_raw}]
			oo::objdefine $rawcon forward closed \
					{*}[namespace code {my _rawcon_closed}]
		}

		#>>>
		method con {} { #<<<
			if {![info exists rawcon]} {
				throw {not_attached} "Not attached to a con"
			}

			return $rawcon
		}

		#>>>

		method assign {msg args} { # returns queue name to enqueue $msg to <<<
			return "_fifo"
		}

		#>>>
		method enqueue {msg args} { #<<<
			set target	[my assign $msg {*}$args]

			set msgid		[incr msgid_seq]
			#dict lappend queues $target [list $msgid [zlib deflate [encoding convertto utf-8 $msg] 3]]
			dict lappend queues $target [list $msgid [encoding convertto utf-8 $msg]]
			$rawcon data_waiting 1
		}

		#>>>
		method pick {queues} { # returns the queue to dequeue a msg from <<<
			# Default behaviour: roundrobin of queues
			set new_roundrobin	{}

			# Trim queues that have gone away
			foreach queue $roundrobin {
				if {$queue ni $queues} continue
				lappend new_roundrobin $queue
			}

			# Append any new queues to the end of the roundrobin
			foreach queue $queues {
				if {$queue in $new_roundrobin} continue
				lappend new_roundrobin $queue
			}

			# Pull the next queue off head and add it to the tail
			set roundrobin	[lassign $new_roundrobin next]
			lappend roundrobin	$next

			return $next
		}

		#>>>
		method dequeue {max_payload} { # returns a {msgid is_tail fragment} <<<
			if {[dict size $queues] == 0} {
				throw {queue_empty} ""
			}

			set source	[my pick [dict keys $queues]]

			set new	[lassign [dict get $queues $source] next]

			lassign $next msgid msg
			if {$max_payload < [string length $msg]} {
				set is_tail	0

				set fragment		[string range $msg 0 $max_payload-1]
				set remaining_msg	[string range $msg $max_payload end]
				set new	[linsert $new 0 [list $msgid $remaining_msg]]
			} else {
				set is_tail	1

				set fragment		$msg
			}

			if {[llength $new] > 0} {
				dict set queues $source $new
			} else {
				dict unset queues $source
			}
			if {[dict size $queues] == 0} {
				$rawcon data_waiting 0
			}
			return [list $msgid $is_tail $fragment]
		}

		#>>>
		method receive {msg} { #<<<
		}

		#>>>
		method closed {} { #<<<
		}

		#>>>
		method _receive_fragment {msgid is_tail fragment} { #<<<
			dict append defrag_buf $msgid $fragment
			if {$is_tail == 1} {
				set complete	[dict get $defrag_buf $msgid]
				dict unset defrag_buf $msgid
				#my receive [encoding convertfrom utf-8 [zlib inflate $complete]]
				my receive [encoding convertfrom utf-8 $complete]
			}
		}

		#>>>
		method _receive_raw {msg} { #<<<
			set p	0
			while {$p <= [string length $msg]} {
				set idx	[string first "\n" $msg $p]
				set head	[string range $msg $p $idx-1]
				lassign $head msgid is_tail fragment_len
				set end_idx	[expr {$idx + $fragment_len + 1}]
				set frag	[string range $msg $idx+1 $end_idx]
				set p		[expr {$end_idx + 1}]
				my _receive_fragment $msgid $is_tail $frag
			}
		}

		#>>>
		method _rawcon_closed {} { #<<<
			my destroy
		}

		#>>>
		method _rawcon_writable {} { #<<<
			set remaining_target	$target_payload_size

			try {
				lassign [my dequeue $remaining_target] \
						msgid is_tail fragment

				set fragment_len	[string length $fragment]
				set payload_portion	"$msgid $is_tail $fragment_len\n$fragment"
				incr remaining_target -$fragment_len
				append payload	$payload_portion

				$rawcon send $payload
			} trap {queue_empty} {} {
				return
			}
		}

		#>>>
		method intersect3 {list1 list2} { #<<<
			set firstonly		{}
			set intersection	{}
			set secondonly		{}

			set list1	[lsort -unique $list1]
			set list2	[lsort -unique $list2]

			foreach item $list1 {
				if {[lsearch -sorted $list2 $item] == -1} {
					lappend firstonly $item
				} else {
					lappend intersection $item
				}
			}

			foreach item $list2 {
				if {[lsearch -sorted $intersection $item] == -1} {
					lappend secondonly $item
				}
			}

			return [list $firstonly $intersection $secondonly]
		}

		#>>>
	}
}
# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

# Aims to be RFC2396 compliant

namespace eval netdgram {
	namespace path ::oo

	# The reason that this is here is so that the sets, lists and charmaps
	# are generated only once, making the instantiation of uri objects much
	# lighter
	variable uri_common	[dict create \
		reserved {
			; / ? : @ & = + $ ,
		} \
		lowalpha {
			a b c d e f g h i j k l m n o p q r s t u v w x y z
		} \
		upalpha {
			A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
		} \
		digit {
			0 1 2 3 4 5 6 7 8 9
		} \
		mark {
			- _ . ! ~ * ' ( )
		} \
		alpha		{} \
		alphanum	{} \
		unreserved	{} \
		charmap		{} \
	]

	dict with uri_common {
		set alpha		[concat $lowalpha $upalpha]
		set alphanum	[concat $alpha $digit]
		set unreserved	[concat $alphanum $mark]
	}
}

oo::class create netdgram::uri {
	mixin netdgram::debug

	variable {*}{
		charmap
		parts
		cached_encoding
	}

	constructor {uri_encoded {encoding "utf-8"}} { #<<<
		if {[self next] ne {}} {next}

		if {[llength [dict get $::netdgram::uri_common charmap]] == 0} {
			my _generate_charmap
		}
		set charmap	[dict get $::netdgram::uri_common charmap]
		my _parseuri $uri_encoded $encoding
	}

	#>>>

	method type {} { #<<<
		if {[dict exists $parts scheme]} {
			return "absolute"
		} else {
			return "relative"
		}
	}

	#>>>
	method as_dict {} { #<<<
		return $parts
	}

	#>>>
	method set_part {part newvalue} { #<<<
		if {$part ni {
			scheme
			authority
			path
			query
			fragment
		}} {
			error "Invalid URI part \"$part\""
		}

		if {$newvalue ne [dict get $parts $part]} {
			if {[info exists cached_encoding]} {unset cached_encoding}
			dict set parts $part $newvalue
		}
	}

	#>>>
	method encoded {{encoding "utf-8"}} { #<<<
		if {![info exists cached_encoding]} {
			if {[dict get $parts scheme] ne ""} {
				# is absolute
				set scheme	[my _hexhex_encode [encoding convertto $encoding [string tolower [dict get $parts scheme]]]]
				set authority	[my _hexhex_encode [encoding convertto $encoding [string tolower [dict get $parts authority]]] ":"]
			}
			if {[dict get $parts path] eq ""} {
				set path	"/"
			} else {
				set path	[dict get $parts path]
			}
			set path	[my _hexhex_encode [encoding convertto $encoding $path] "/"]
			if {[dict size [dict get $parts query]] == 0} {
				set query	""
			} else {
				set query	"?[my query_encode [dict get $parts query]]"
			}

			if {[dict get $parts fragment] eq ""} {
				set fragment	""
			} else {
				set fragment	"#[my _hexhex_encode [encoding convertto $encoding [dict get $parts fragment]]]"
			}

			if {[dict get $parts scheme] eq ""} {
				# is relative
				set cached_encoding "${path}${query}${fragment}"
			} else {
				# is absolute
				set cached_encoding	"${scheme}://${authority}${path}${query}${fragment}"
			}
		}

		return $cached_encoding
	}

	#>>>
	method query_decode {query {encoding "utf-8"}} { #<<<
		set build	[dict create]
		foreach term [split $query &] {
			# Warning: doesn't check for less or more than 1 "="
			lassign [split $term =] key val
			dict set build [my _urldecode $key $encoding] [my _urldecode $val $encoding]
		}
		return $build
	}

	#>>>
	method query_encode {query {encoding "utf-8"}} { #<<<
		set terms	{}
		dict for {key value} $query {
			set ekey	[my _hexhex_encode [encoding convertto $encoding $key]]
			set evalue	[my _hexhex_encode [encoding convertto $encoding $value]]
			lappend terms	"${ekey}=${evalue}"
		}
		return [join $terms &]
	}

	#>>>

	method _parseuri {uri {encoding "utf-8"}} { #<<<
		if {[info exists cached_encoding]} {unset cached_encoding}
		# Regex from RFC2396
		if {![regexp {^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?} $uri x x1 scheme x2 authority path x3 query x4 fragment]} {
			throw [list invalid_uri $uri] "Invalid URI"
		}

		set parts	[dict create \
				scheme		[my _urldecode [string tolower $scheme] $encoding] \
				authority	[my _urldecode [string tolower $authority] $encoding] \
				path		[my _urldecode $path $encoding] \
				query		[my query_decode $query $encoding] \
				fragment	[my _urldecode $fragment $encoding] \
		]

		return $parts
	}

	#>>>
	method _urldecode {data {encoding "utf-8"}} { #<<<
		regsub -all {([][$\\])} $data {\\\1} data
		regsub -all {%([0-9a-fA-F][0-9a-fA-F])} $data  {[binary format H2 \1]} data
		return [encoding convertfrom $encoding [subst $data]]
	}

	#>>>
	method _generate_charmap {} { #<<<
		set charmap	{}
		dict with ::netdgram::uri_common {
			for {set i 0} {$i < 256} {incr i} {
				set c	[binary format c $i]
				if {$c in $unreserved} {
					lappend charmap	$c
				} else {
					lappend charmap	[format "%%%02X" $i]
				}
			}
		}

		dict set ::netdgram::uri_common charmap $charmap
	}

	#>>>
	method _hexhex_encode {data {exceptions ""}} { #<<<
		binary scan $exceptions c* elist
		binary scan $data c* byteslist
		set out	""
		foreach byte $byteslist {
			set byte	[expr {$byte & 0xff}]	;# convert to unsigned
			if {$byte in $elist} {
				append out	[format "%c" $byte] 
			} else {
				append out	[lindex $charmap $byte]
			}
		}
		return $out
	}

	#>>>
}

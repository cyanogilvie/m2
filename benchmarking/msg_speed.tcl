#!/usr/bin/tclsh8.6
# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> foldmarker=<<<,>>>

if {![info exists ::tcl::basekit]} {
	package require platform

	foreach platform [platform::patterns [platform::identify]] {
		set tm_path		[file join $env(HOME) .tbuild repo tm $platform]
		set pkg_path	[file join $env(HOME) .tbuild repo pkg $platform]
		if {[file exists $tm_path]} {
			tcl::tm::path add $tm_path
		}
		if {[file exists $pkg_path]} {
			lappend auto_path $pkg_path
		}
	}
}

package require cflib

source msg.tcl
source old/msg.tcl

apply {
	{} {
		m2::msg::new
		set msg_new	[time {
			m2::msg::new {
				type	req
				svc		authenticator
				seq		1
				data	"hello, world"
			}
		} 100000]
		puts "msg_new: $msg_new"

		[m2::msg new new] destroy
		set obj_msg_new	[time {
			[m2::msg new new \
				type	req \
				svc		authenticator \
				seq		1 \
				data	"hello, world" \
			] destroy
		} 10000]
		puts "obj msg new: $obj_msg_new"

		set dm	[m2::msg::new {
			type	req
			svc		authenticator
			seq		1
			data	"hello, world"
		}]
		set dm_serialized	[m2::msg::serialize $dm]
		set dm_serialize [time {
			m2::msg::serialize $dm
		} 10000]
		puts "dm serialize: $dm_serialize"

		set om [m2::msg new new \
				type	req \
				svc		authenticator \
				seq		1 \
				data	"hello, world"]

		set om_field_get1	[time {
			$om get type
		} 100000]
		puts "om_field_get1: $om_field_get1"
		set om_field_get2	[time {
			$om type
		} 100000]
		puts "om_field_get2: $om_field_get2"

		set dm_field_get	[time {
			dict get $dm type
		} 100000]
		puts "dm_field_get: $dm_field_get"

		set om_serialized	[$om serialize]
		set om_serialize [time {
			$om serialize
		} 10000]
		puts "om serialize: $om_serialize"

		set dm_deserialize [time {
			m2::msg::deserialize $dm_serialized
		} 10000]
		puts "dm deserialize: $dm_deserialize"

		set om_deserialize [time {
			[m2::msg new deserialize $om_serialized] destroy
		} 10000]
		puts "om deserialize: $om_deserialize"


		set dm	[m2::msg::shift_seqs $dm[unset dm] 2]
		set dm_shift_seqs0	[time {
			set newmsg	$dm
			dict set newmsg prev_seq	[dict get $dm seq]
			dict set newmsg seq			3
		} 10000]
		puts "dm_shift_seqs0: $dm_shift_seqs0"
		set dm_shift_seqs01	[time {
			set newmsg	[dict replace $dm prev_seq [dict get $dm seq] seq 3]
		} 10000]
		puts "dm_shift_seqs01: $dm_shift_seqs01"
		set dm	[m2::msg::shift_seqs $dm[unset dm] 2]
		set dm_shift_seqs1	[time {
			set dm	[m2::msg::shift_seqs $dm 3]
		} 10000]
		puts "dm_shift_seqs1: $dm_shift_seqs1"
		set dm_shift_seqs2	[time {
			set dm	[m2::msg::shift_seqs $dm[unset dm] 3]
		} 10000]
		puts "dm_shift_seqs2: $dm_shift_seqs2"
		set dm_shift_seqs3	[time {
			set dm	[m2::msg::shift_seqs $dm[set dm ""] 3]
		} 10000]
		puts "dm_shift_seqs3: $dm_shift_seqs3"
		set dm_shift_seqs4	[time {
			set dm	[dict replace $dm prev_seq [dict get $dm[unset dm] seq] seq 3]
		} 10000]
		puts "dm_shift_seqs4: $dm_shift_seqs4"
		set dm_shift_seqs5	[time {
			dict set dm prev_seq [dict get $dm seq]
			dict set dm seq 3
		} 10000]
		puts "dm_shift_seqs5: $dm_shift_seqs5"
		set dm_shift_seqs6	[time {
			dict update dm seq seq prev_seq prev_seq {
				set prev_seq	$seq
				set seq			3
			}
		} 10000]
		puts "dm_shift_seqs6: $dm_shift_seqs6"

		$om shift_seqs 2
		set om_shift_seqs	[time {
			$om shift_seqs 3
		} 10000]
		puts "om_shift_seqs: $om_shift_seqs"
	}
}

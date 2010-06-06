#!/usr/bin/env tclsh8.6

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

package require m2
package require cflib
package require sop
package require dsl

cflib::config create cfg $argv {
	variable uri			"tcp://localhost:5300"
	variable pbkey			"/etc/codeforge/authenticator/keys/env/authenticator.pb"
}


m2::authenticator create auth -uri [cfg get uri] -pbkey [cfg get pbkey]

m2::component create comp \
		-svc		"examplecomponent" \
		-auth		auth \
		-prkeyfn	"/etc/codeforge/authenticator/keys/env/examplecomponent.pr"  \
		-login		0

comp handler "hello" [list apply {
	{auth user seq rdata} {
		auth ack $seq "world, [$user name]: ($rdata)"
	}
}]

m2::locks::component create locksmgr \
		-comp	comp \
		-tag	testlocks

locksmgr register_handler aquire_lock [list apply {
	{user id} {
		if {$id ne "someid"} {
			throw {response error} "Invalid id: ($id)"
		}
	}
}]

locksmgr register_handler lock_req_testreq [list apply {
	{id auth user seq data} {
		puts "Got request on lock channel for id ($id): ($data)"
		$auth ack $seq "hello $data"
	}
}]

coroutine coro_main vwait forever

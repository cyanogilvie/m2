# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

set orig_dir	[pwd]

package require cflib

set rest		[lassign $argv cmd]

cflib::config create cfg $rest {
	variable makeuser			0
	variable keysize			2048
	variable crypto_devmode		0
	variable svc				""
	variable svc_keys_registry	"/etc/codeforge/authenticator/svc_keys"
	variable keystore			"/etc/codeforge/authenticator/keys"
	variable debug				0
	variable as_user			"codeforge"
	variable as_group			"codeforge"
}


if {[cfg get crypto_devmode]} {
	namespace eval crypto {
		variable devmode	1
	}
}

# Drop root <<<
package require daemon 0.5

proc lookup_uid {name} {
	foreach line [split [cflib::readfile /etc/passwd] \n] {
		lassign [split $line :] \
				username pw uid pgid gecos home shell

		if {$name eq $username} {
			return $uid
		}
	}

	throw [list no_such_user $name] "User \"$user\" not found"
}

proc lookup_gid {name} {
	foreach line [split [cflib::readfile /etc/group] \n] {
		lassign [split $line :] \
				group pw gid userlist
		set userlist	[split $userlist ]

		if {$name eq $group} {
			return $gid
		}
	}

	throw [list no_such_group $name] "Group \"$group\" not found"
}

if {
	[dutils::getgid] == 0 ||
	[dutils::getegid] == 0
} {
	set gid	[lookup_gid [cfg get as_group]]
	dutils::setregid $gid $gid
}
if {
	[dutils::getuid] == 0 ||
	[dutils::geteuid] == 0
} {
	set uid	[lookup_uid [cfg get as_user]]
	dutils::setreuid $uid $uid
}
#>>>


proc create {} { #<<<
	package require Crypto 0.9.1

	# Generate the keypair <<<
	puts "Generating key: [cfg get keysize] bits"
	set handle		[crypto::rsa_generate_key [cfg get keysize] 17]
	set fqkeystore	[cfg get keystore]
	set pr_fn	[file join $fqkeystore "[cfg get svc].priv"]
	set pb_fn	[file join $fqkeystore "[cfg get svc].pub"]
	crypto::rsa_write_private_key $handle $pr_fn
	file attributes $pr_fn -permissions 0600
	puts "Wrote private key: \"$pr_fn\""
	crypto::rsa_write_public_key $handle $pb_fn
	puts "Wrote public key: \"$pb_fn\""
	# Generate the keypair >>>

	# Create svc_keys link <<<
	puts "Creating svc_keys link"
	set fqsvc_keys_registry	[cfg get svc_keys_registry]
	set registry			$fqsvc_keys_registry
	set link				[file normalize [file join $registry [cfg get svc]]]
	file link -symbolic $link $pb_fn
	# Create svc_keys link >>>

	# Create component prkey link <<<
	puts "Creating private key link"
	set link	[file normalize [file join $::orig_dir "[cfg get svc].priv"]]
	file link -symbolic $link $pr_fn
	# Create component prkey link >>>

	# (Optionally) create svc user <<<
	if {[cfg get makeuser]} {
		puts stderr "-makeuser not supported yet"
	}
	# (Optionally) create svc user >>>
}

#>>>

set cmd_args	[cfg rest]
switch -- $cmd {
	create	{set handler	create}

	default {
		puts stderr "Invalid cmd: $cmd"
		exit -1
	}
}

try {
	$handler {*}$cmd_args
} on error {errmsg options} {
	if {[cfg get debug]} {
		puts stderr [dict get $options -errorinfo]
	} else {
		puts stderr $errmsg
	}
}

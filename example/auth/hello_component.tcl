proc ?? args {}
proc log {lvl msg args} {puts $msg}

package require m2

m2::authenticator create auth -uri tcp:// \
		-pbkey /etc/codeforge/authenticator/keys/env/authenticator.pb

m2::component create comp \
		-svc		hello \
		-auth		auth \
		-prkeyfn	/etc/codeforge/authenticator/keys/env/hello.pr \
		-login		yes

comp handler hello [list apply {
	{auth user seq rest} {
		puts "Got request"
		$auth ack $seq "hello [$user name]: $rest"
	}
}]

vwait forever

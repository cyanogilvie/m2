# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> foldmarker=<<<,>>>

oo::class create m2::baselog {
	method log {lvl msg args} {
		uplevel [string map [list %lvl% $lvl %msg% $msg %args% $args] {
			puts "[self] [self class]::[self method] %lvl% %msg%"
		}
	}
}



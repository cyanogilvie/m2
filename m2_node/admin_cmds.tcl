
namespace eval ports { #<<<
	namespace export *
	namespace ensemble create

	proc show {} { #<<<
		set ports {}
		foreach obj [info class instances ::m2::port] {
			lappend ports [$obj cached_station_id]
		}
		set ports
	}

	#>>>
}

#>>>

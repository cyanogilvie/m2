proc m2::intersect3 {list1 list2} {
	set firstonly       {}
	set intersection    {}
	set secondonly      {}

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



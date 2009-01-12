// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

function is_space(char) { //<<<
	// Not perfect
	if (
		char == ' ' ||
		char == '\t' ||
		char == '\n' ||
		char == '\r' ||
		char == '\v'
	) {
		return true;
	} else {
		return false;
	}
}

//>>>
function unicode_char(value) { //<<<
	var hexstr;
	var rhexmap = [
		'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
	];
	hexstr = '\\u';
	hexstr += rhexmap[(value / (1<<12)) & 0xF];
	hexstr += rhexmap[(value / (1<<8)) & 0xF];
	hexstr += rhexmap[(value / (1<<4)) & 0xF];
	hexstr += rhexmap[value & 0xF];
	return eval('"'+hexstr+'"');
}

//>>>
function char_is_hex(char) { //<<<
	switch (char) {
		case '0':
		case '1':
		case '2':
		case '3':
		case '4':
		case '5':
		case '6':
		case '7':
		case '8':
		case '9':
		case 'a':
		case 'b':
		case 'c':
		case 'd':
		case 'e':
		case 'f':
		case 'A':
		case 'B':
		case 'C':
		case 'D':
		case 'E':
		case 'F':
			return true;

		default:
			return false;
	}
}

//>>>
function parse_tcl_list(str) { //<<<
	var ofs = -1;
	var parts = new Array();
	var elem = '';
	var in_elem = false;
	var braced = false;
	var quoted = false;
	var bracedepth = 0;
	var braceescape = false;
	var elemstart = false;
	var escaped = false;
	var escape_seq = '';
	var escape_mode = '';
	var needspace = false;
	var braceofs = 0;
	var quoteofs = 0;
	var c;
	var finished = false;
	var cont = false;
	var acc;
	var pow;

	var hexmap = {
		'a': 10,
		'b': 11,
		'c': 12,
		'd': 13,
		'e': 14,
		'f': 15,
		'A': 10,
		'B': 11,
		'C': 12,
		'D': 13,
		'E': 14,
		'F': 15
	};

	for (var i=0; i<str.length; i++) {
		ofs++;

		c = str.charAt(i);

		if (needspace) { // continues <<<
			if (is_space(c)) {
				needspace = 0;
				continue;
			}
			throw 'Garbage after list element at offset '+ofs+': "'+c+'"';
		}
		//>>>
		if (!in_elem) { // fallthrough if c not a space <<<
			if (is_space(c)) continue;
			in_elem = true;
			elemstart = true;
		}
		//>>>
		if (elemstart) { // continues <<<
			if (c == '{') {
				braced = true;
				bracedepth = true;
				braceofs = ofs;
			} else if (c == '"') {
				quoted = true;
			} else if (c == '\\') {
				escaped = true;
			} else {
				elem += c;
			}
			elemstart = false;
			continue
		}
		//>>>
		if (escaped) { // sometimes falls through <<<
			if (escape_mode == '') { //<<<
				switch (c) {
					case 'a':
						elem += '\u0007';
						escaped = false;
						break;
					case 'b':
						elem += '\u0008';
						escaped = false;
						break;
					case 'f':
						elem += '\u000c';
						escaped = false;
						break;
					case 'n':
						elem += '\u000a';
						escaped = false;
						break;
					case 'r':
						elem += '\u000d';
						escaped = false;
						break;
					case 't':
						elem += '\u0009';
						escaped = false;
						break;
					case 'v':
						elem += '\u000b';
						escaped = false;
						break;

					case '0':
					case '1':
					case '2':
					case '3':
					case '4':
					case '5':
					case '6':
					case '7':
						escape_mode = 'octal';
						escape_seq += c;
						break;
	
					case 'x':
						escape_mode = 'hex';
						break;

					case 'u':
						escape_mode = 'unicode';
						break;

					default:
						elem += c;
						escaped = false;
						break;
				}
				if (!escaped) {
					escape_mode = '';
				}
				continue;
				//>>>
			} else if (escape_mode == 'octal') { //<<<
				finished = false;
				cont = false;
				switch (c) {
					case '0':
					case '1':
					case '2':
					case '3':
					case '4':
					case '5':
					case '6':
					case '7':
						escape_seq += c;
						if (escape_seq.length == 3) {
							finished = true;
						} else {
							finished = false;
						}
						cont = true;
						break;

					default:
						finished = true;
						cont = false;
						break;
				}
				if (finished) {
					acc = 0;
					pow = 0;
					while (escape_seq.length > 0) {
						var lsd = escape_seq.substr(-1,1);
						escape_seq = escape_seq.slice(0,-1);
						acc += lsd * Math.pow(8, pow);
						pow++;
					}
					elem += unicode_char(acc);
					escape_mode = '';
					escaped = false;
				}
				if (cont) continue;
				//>>>
			} else if (escape_mode == 'hex') { //<<<
				if (char_is_hex(c)) {
					escape_seq += c;
					continue;
				} else {
					if (escape_seq.length == 0) {
						elem += 'x'+c;
						escaped = false;
						escape_mode = '';
						continue;
					}
					if (escape_seq.length > 2) {
						escape_seq = escape_seq.substr(-2, 2);
					}
				}
				elem += unicode_char('0x'+escape_seq);
				escape_mode = '';
				escaped = false;
				//>>>
			} else if (escape_mode == 'unicode') { //<<<
				finished = false;
				cont = false;

				if (char_is_hex(c)) {
					escape_seq += c;
					if (escape_seq.length == 4) {
						finished = true;
					} else {
						finished = false;
					}
					cont = true;
				} else {
					finished = true;
					cont = false;
				}

				if (finished) {
					if (escape_seq.length == 0) {
						elem += 'u';
					} else {
						while (escape_seq.length < 4) {
							escape_seq = '0'+escape_seq;
						}
						elem += eval('"\\u'+escape_seq+'"');
						escape_seq = '';
					}
					escape_mode = '';
					escaped = false;
				}

				if (cont) continue
				//>>>
			} else {
				throw 'Error in escape sequence parser state: invalid state "'+escape_mode+'"';
			}
		}
		//>>>
		if (braced) { // continues <<<
			if (braceescape) {
				elem += c;
				braceescape = false;
				continue;
			}
			if (c == '{') {
				elem += c;
				bracedepth++;
			} else if (c == '}') {
				bracedepth--;
				if (bracedepth == 0) {
					braced = false;
					needspace = true;
					in_elem = false;
					parts.push(elem);
					elem = '';
				} else {
					elem += c;
				}
			} else if (c == '\\') {
				braceescape = true;
			} else {
				elem += c;
			}
			continue;
		}
		//>>>
		if (quoted) { // continues <<<
			if (c == '"') {
				quoted = false;
				in_elem = false;
				parts.push(elem);
				elem = '';
				needspace = false;
			} else if (c == '\\') {
				escaped = true;
			} else {
				elem += c;
			}
			continue;
		}
		//>>>
		if (is_space(c)) { // continues <<<
			parts.push(elem);
			elem = '';
			in_elem = false;
			continue;
		}
		//>>>
		if (c == '\\') { // continues <<<
			escaped = true;
			continue;
		}
		//>>>

		elem += c;
	}

	if (braced) { //<<<
		throw 'Open brace in string (from offset '+braceofs+')';
	}
	//>>>
	if (quoted) { //<<<
		throw 'Open quote in string (from offset '+quoteofs+')';
	}
	//>>>
	if (escaped) { //<<<
		switch (escape_mode) {
			case '':
				elem += '\\';
				parts.push(elem);
				in_elem = false;
				break;

			case 'octal':
				acc = 0;
				pow = 0;
				while (escape_seq.length > 0) {
					var lsd = escape_seq.substr(-1,1);
					escape_seq = escape_seq.slice(0,-1);
					acc += lsd * Math.pow(8, pow);
					pow++;
				}
				elem += unicode_char(acc);
				escape_mode = '';
				escaped = false;
				break;

			case 'hex':
				if (escape_seq.length == 0) {
					elem += 'x';
				} else {
					if (escape_seq.length > 2) {
						escape_seq = escape_seq.substr(-2, 2);
					}
					elem += unicode_char('0x'+escape_seq);
				}
				escape_mode = '';
				escaped = false;
				break;

			case 'unicode':
				if (escape_seq.length == 0) {
					elem += 'u';
				} else {
					while (escape_seq.length < 4) {
						escape_seq = '0'+escape_seq;
					}
					elem += eval('"\\u'+escape_seq+'"');
				}
				escape_mode = '';
				escaped = false;
				break;

			default:
				throw 'Error in escape sequence parser state: invalid state "'+escape_mode+'"';
				break;
		}
	}
	//>>>
	if (in_elem) { //<<<
		parts.push(elem);
		elem = '';
	}
	//>>>

	return parts;
}

//>>>

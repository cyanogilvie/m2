// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

function is_space(char) { //<<<
	// Not perfect
	/* This breaks ie - it things that '\v' is 'v'
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
	*/
	if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
		return true;
	} else {
		return false;
	}
}

//>>>
function unicode_char(value) { //<<<
	return String.fromCharCode(value);
	/*
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
	*/
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
	var parts = [];
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
	var lsd;

	if (typeof str == 'undefined' || str === null) {
		return [];
	}

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
			if (is_space(c)) {
				continue;
			}
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
			continue;
		}
		//>>>
		if (escaped) { // sometimes falls through <<<
			if (escape_mode === '') { //<<<
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
						lsd = escape_seq.substr(-1,1);
						escape_seq = escape_seq.slice(0,-1);
						acc += lsd * Math.pow(8, pow);
						pow++;
					}
					elem += unicode_char(acc);
					escape_mode = '';
					escaped = false;
				}
				if (cont) {
					continue;
				}
				//>>>
			} else if (escape_mode == 'hex') { //<<<
				if (char_is_hex(c)) {
					escape_seq += c;
					continue;
				} else {
					if (escape_seq.length === 0) {
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
					if (escape_seq.length === 0) {
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

				if (cont) {
					continue;
				}
				//>>>
			} else {
				throw 'Error in escape sequence parser state: invalid state "'+escape_mode+'"';
			}
		}
		//>>>
		if (braced) { // continues <<<
			if (braceescape) {
				elem += '\\'+c;
				braceescape = false;
				continue;
			}
			if (c == '{') {
				elem += c;
				bracedepth++;
			} else if (c == '}') {
				bracedepth--;
				if (bracedepth === 0) {
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
					lsd = escape_seq.substr(-1,1);
					escape_seq = escape_seq.slice(0,-1);
					acc += lsd * Math.pow(8, pow);
					pow++;
				}
				elem += unicode_char(acc);
				escape_mode = '';
				escaped = false;
				break;

			case 'hex':
				if (escape_seq.length === 0) {
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
				if (escape_seq.length === 0) {
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
function serialize_tcl_list(arr) { //<<<
	// for now...
	var i, staged, elem;
	staged = [];
	for (i=0; i<arr.length; i++) {
		elem = String(arr[i]);
		if (
			elem.length > 0 &&
			elem.indexOf(' ') == -1 &&
			elem.indexOf('"') == -1 &&
			elem.indexOf('}') == -1 &&
			elem.indexOf('{') == -1 &&
			elem.indexOf('$') == -1 &&
			elem.indexOf(';') == -1 &&
			elem.indexOf('\t') == -1 &&
			elem.indexOf('\f') == -1 &&
			elem.indexOf('\n') == -1 &&
			elem.indexOf('\r') == -1 &&
			elem.indexOf('\v') == -1 &&
			elem.indexOf('\[') == -1 &&
			elem.indexOf('\]') == -1) {
			if (elem.indexOf('\\') == -1) {
				staged.push(elem);
			} else {
				// Replace all \ with \\
				staged.push(elem.replace(/\\/g, '\\\\'));	// WARNING: flags are a spidermonkey extension
			}
		} else {
			if (
				elem.indexOf('}') == -1 &&
				elem.indexOf('{') == -1 &&
				elem.charAt(elem.length-1) != '\\') {
				staged.push('{'+elem+'}');
			} else {
				// Replace all <special> with \<special>
				elem = elem.replace(/\\| |"|\[|\]|\}|\{|\$|;/g, '\\$&');	// WARNING: flags are a spidermonkey extension
				elem = elem.replace(/\n/g, '\\n');	// WARNING: flags are a spidermonkey extension
				elem = elem.replace(/\r/g, '\\r');	// WARNING: flags are a spidermonkey extension
				elem = elem.replace(/\f/g, '\\f');	// WARNING: flags are a spidermonkey extension
				elem = elem.replace(/\t/g, '\\t');	// WARNING: flags are a spidermonkey extension
				//elem = elem.replace('/'+String.fromCharCode(0xb)+'/g', '\\v');	// WARNING: flags are a spidermonkey extension
				elem = elem.replace(/\v/g, '\\v');	// WARNING: flags are a spidermonkey extension
				staged.push(elem);
			}
		}
	}
	return staged.join(' ');
}

//>>>
function array2dict(arr) { //<<<
	var build, i;
	build = {};

	for (i=0; i<arr.length; i+=2) {
		var k, v;
		k = arr[i];
		v = arr[i+1];

		build[k] = v;
	}

	return build;
}

//>>>
function list2dict(list) { //<<<
	return array2dict(parse_tcl_list(list));
}

//>>>
function array2hash(arr) { //<<<
	var h, i;

	h = new Hash();

	for (i=0; i<arr.length; i+=2) {
		var k, v;
		k = arr[i];
		v = arr[i+1];

		h.setItem(k, v);
	}

	return h;
}

//>>>
function list2hash(list) { //<<<
	return array2hash(parse_tcl_list(list));
};

//>>>

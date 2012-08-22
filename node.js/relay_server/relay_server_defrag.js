var app = require('http').createServer(handler),
	io = require('socket.io').listen(app),
	net = require('net');

app.listen(5302);

function handler(req, res) {
	res.writeHead(500);
	res.end('No normal HTTP requests permitted');
}

function buf_indexOf(buf, char, start, end) {
	var charcode = char.charCodeAt(0), i;

	for (i=start; i<end; i++) {
		if (buf[i] === charcode) {
			return i;
		}
	}

	return -1;
}

io.sockets.on('connection', function(socket){
	var upstream, defrag_buf=new Buffer(65536), buf_start=0, buf_end=0;

	console.log('Got connection, initiating upstream connection');

	upstream = net.connect(5300, 'localhost', function(){
		console.log('Upstream connected');
	});

	function send_datagrams() {
		var lineend, dgram_len, dgram;

		while (buf_start < buf_end) {
			lineend = buf_indexOf(defrag_buf, '\n', buf_start, buf_end);
			if (lineend === -1) {
				break;
			}
			dgram_len = Number(defrag_buf.toString('utf-8', buf_start, lineend));
			if (buf_end < lineend + dgram_len) {
				break;
			}
			buf_start = lineend + dgram_len + 1;
			dgram = defrag_buf.toString('base64', lineend + 1, buf_start);

			console.log('Sending dgram downstream: ', dgram);
			socket.send(dgram, function(){
				console.log('socket.io confirms message sent');
			});
		}
		if (buf_start === buf_end) {
			buf_start = buf_end = 0;
		} else {
			buf.slice(buf_start, buf_end).copy(buf, 0);
			buf_end -= buf_start;
			buf_start = 0;
		}
		console.log('after send_datagrams, buf_start: '+buf_start+', buf_end: '+buf_end);
	}

	// From upstream
	upstream.on('data', function(data){
		var copied;
		console.log('Got data from upstream, sending downstream');
		if (socket) {
			copied = data.copy(defrag_buf, buf_end);
			if (copied < data.length) {
				throw new Error('Defrag buffer overflow, data.length: '+data.length);
			}
			buf_end += copied;
			console.log('Added '+copied+' bytes to buffer, buf_start: '+buf_start+', buf_end: '+buf_end);
			try {
				send_datagrams();
			} catch(err) {
				console.error('Error in send_datagrams: ', err);
			}
		}
	});
	upstream.on('end', function(){
		console.log('Upstream connection closed, closing downstream');
		if (socket) {
			socket.disconnect();
			socket = null;
		}
	});

	// From downstream
	socket.on('message', function(data){
		data = new Buffer(data, 'base64');
		console.log('Got data from downstream, sending up: ', data.length);
		if (upstream) {
			upstream.write(data.length+'\n'+data);
		}
	});
	socket.on('disconnect', function(){
		console.log('Downstream connection closed, closing upstream');
		if (upstream) {
			upstream.end();
			uptream = null;
		}
	});
});


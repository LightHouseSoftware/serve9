private {
	import std.conv : ConvException;
	import std.getopt;
	import std.stdio : writeln;

	import serve9.styxserver;
}

string address;
ushort port;
string path;
string uid = "user";
string gid = "user";
bool messages;
bool bytes;

void main(string[] args)
{
	try
	{
		getopt(
			args,
			std.getopt.config.required,
			"addr|a",      &address,            /* server ip */
			std.getopt.config.required,
			"port|p",      &port,               /* server port */
			std.getopt.config.required,
			std.getopt.config.caseSensitive,
			"path|d",      &path,               /* path to folder */
			"uid|u",       &uid,                /* user id */        
			"gid|g",       &gid,                /* group id */
			"messages|M",  &messages,           /* debug mode */
			"bytes|B",     &bytes,              /* show raw bytes */
			std.getopt.config.passThrough 
		);

		auto server = new StyxShareServer(path,uid, gid);
		with (server)
		{
			messagesMode(messages);
			bytesMode(bytes);
			setup6(address, port);
			run;
		}
	}
	catch (Throwable e)
	{
		writeln(e.msg);
	}
}

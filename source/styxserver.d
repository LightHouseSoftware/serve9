module serve9.styxserver;

private {
	enum uint BUFFER_SIZE = 8_192;
	enum uint CONNECTIONS_NUMBER = 60;

	import std.file : dirEntries, DirEntry, SpanMode, exists;
	import std.path : buildPath, baseName;
	import std.stdio : writeln;

	import styx2000.extrautil.casts;
	import styx2000.extrautil.dir;
	import styx2000.extrautil.dirstat;

	import styx2000.extrautil.mischelpers : createQid, createStat;
	import styx2000.extrautil.styxmessage;

	import styx2000.protoconst.modes;
	import styx2000.protoconst.messages;
	import styx2000.protoconst.qids;

	import styx2000.protomsg : decode, encode;

	import styx2000.protobj;

	import serve9.io;
	import serve9.server;
}

class StyxShareServer : GenericSimpleServer!(BUFFER_SIZE, CONNECTIONS_NUMBER)
{
	private {
		string        _dir;
		string        _uid;
		string        _gid;

		string[uint]  _pool;

		bool _messages;
		bool _bytes;
	}

	this(string dir, string uid, string gid)
	{
		_dir = dir;
		_uid = uid;
		_gid = gid;
	}

	void messagesMode(bool messages)
	{
		_messages = messages;
	}

	void bytesMode(bool bytes)
	{
		_bytes = bytes;
	}

	override ubyte[] handle(ubyte[] request)
	{
		auto rmsg = decode(request);
		auto tmsg = process(rmsg);
		auto response = encode(tmsg);

		if (_messages)
		{
			writeln(`-> `, rmsg);
			writeln(`<- `, tmsg);
		}

		if (_bytes)
		{
			writeln(`-> `, request);
			writeln(`<- `, response);
		}
		return response;
	}

	private {
		StyxMessage walk(ushort tag, uint fid, uint newfid, string[] nwname) {
			StyxMessage msg = createHeader(0, STYX_MESSAGE_TYPE.R_WALK, tag);
			
			if (nwname.length == 0)
			{
				msg ~= cast(StyxObject) new Nwqid;
				_pool[newfid] = _dir;
			}
			else
			{
				auto path = buildPath(_dir ~ nwname);
				
				if (path.exists)
				{	
					Qid[] qids;
					auto nwqid = new Nwqid;
					
					foreach (e; nwname)
					{
						auto npath = buildPath(_dir ~ nwname);
						qids ~= createQid(npath);
					}
					
					nwqid.setQid(qids);
					msg ~= cast(StyxObject) nwqid;
					
					if (path != _dir)
					{
						_pool[newfid] = path;
					}
				}
				else
				{
					msg = createRmsgError(tag, `Walk error`);
				}
			}
			
			return msg;
		}

		StyxMessage stat(ushort tag, uint fid) {
			StyxMessage msg = createHeader(0, STYX_MESSAGE_TYPE.R_STAT, tag);
			
					if (fid in _pool)
			{
				auto path = _pool[fid];
				
				msg ~= cast(StyxObject) createStat(path, 0, 0, _uid, _gid);
			}
			else
			{
				msg = createRmsgError(tag, `Stat error`);
			}
			
			return msg;
		}

		StyxMessage open(ushort tag, uint fid, STYX_FILE_MODE mode) {
			StyxMessage msg;
					
			if (fid in _pool)
			{
				auto path = _pool[fid];
				
				auto qid = createQid(_dir);
				msg = createRmsgOpen(tag, qid.getType, qid.getVers, qid.getPath);
			}
			else
			{
				msg = createRmsgError(tag, `Open error`);
			}
			
			return msg;		
		}

		StyxMessage read(ushort tag, uint fid, ulong offset, uint count) {
			StyxMessage msg = createHeader(0, STYX_MESSAGE_TYPE.R_READ, tag);
			
			if (fid in _pool)
			{
				auto path = _pool[fid];
				
				if (DirEntry(path).isDir)
				{
					Dir[] dirs;
					
					foreach (e; dirEntries(path, SpanMode.shallow))
					{
						auto dir = createStat(e.name, 0, 0, _uid, _gid).stat2dir;
						dirs ~= dir;
					}
					
					auto ds = new DirStat(dirs);
					msg ~= readAt(ds.pack, offset, count);
				}
				else
				{
					msg ~= readAt(path, offset, count);
				}
			}
			else
			{
				msg = createRmsgError(tag, `Read error`);
			}
			
			return msg;
		}

		StyxMessage write(ushort tag, uint fid, ulong offset, uint count, ubyte[] data) {
			StyxMessage msg = createHeader(0, STYX_MESSAGE_TYPE.R_WRITE, tag);
			
			if (fid in _pool)
			{
				auto path = _pool[fid];
				
				if (DirEntry(path).isDir)
				{
					msg = createRmsgError(tag, `Write error`);
				}
				else
				{
					msg ~= writeAt(path, offset, count, data);
				}
			}
			else
			{
				msg = createRmsgError(tag, `Write error`);
			}
			
			return msg;
		}

		StyxMessage processFS(STYX_MESSAGE_TYPE type, ushort tag, StyxObject[] args...) {
			StyxMessage msg;

			auto fid = args[0].toFid.getFid;
			
			switch (type)
			{
				case STYX_MESSAGE_TYPE.T_WALK:
					auto newfid = args[1].toNewFid.getFid;
					auto nwname = args[2].toNwname.getName;
					msg = walk(tag, fid, newfid, nwname);
					break;
				case STYX_MESSAGE_TYPE.T_STAT:
					msg = stat(tag, fid);
					break;
				case STYX_MESSAGE_TYPE.T_OPEN:
					auto mode = args[1].toMode.getMode;
					msg = open(tag, fid, mode);
					break;
				case STYX_MESSAGE_TYPE.T_READ:
					auto offset = args[1].toOffset.getOffset;
					auto count = args[2].toCount.getCount;
					msg = read(tag, fid, offset, count);
					break;
				case STYX_MESSAGE_TYPE.T_WRITE:
					auto offset = args[1].toOffset.getOffset;
					auto count = args[2].toCount.getCount;
					auto data = args[3].toData.getData;
					msg = write(tag, fid, offset, count, data);
					break;
				default:
					msg = createRmsgError(tag, `Wrong message`);
					break;
			}
			
			return msg;
		}

		StyxMessage process(StyxMessage query) {
			StyxMessage reply;

			auto type = query[1].toType.getType;
			auto tag =  query[2].toTag.getTag;
		
			switch (type)
			{
				case STYX_MESSAGE_TYPE.T_VERSION:
					reply = createRmsgVersion;
					break;
				case STYX_MESSAGE_TYPE.T_ATTACH:
					auto fid = query[3].toFid.getFid;
					_pool[fid] = _dir;
					reply = createRmsgAttach(tag, STYX_QID_TYPE.QTDIR);
					break;
				case STYX_MESSAGE_TYPE.T_CLUNK:
					auto fid = query[3].toFid.getFid;
					_pool.remove(fid);
					reply = createRmsgClunk(tag);
					break;
				case STYX_MESSAGE_TYPE.T_FLUSH:
					reply = createRmsgFlush(tag);
					break;
				default:
					auto args = query[3..$];
					reply = processFS(type, tag, args);
				break;
			}

			return reply;
		}
	}
}

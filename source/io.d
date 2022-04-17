module serve9.io;

private {
	import std.stdio : File;
	
	import styx2000.protobj : Count, Data, StyxObject;
}

auto readAt(string filepath, ulong offset, uint count)
{
	File file;
	file.open(filepath, `rb`);
	auto size = file.size;
	
	if (offset >= size)
	{
		return cast(StyxObject[])[
			new Count(0),
			new Data
		];
	}
	else
	{
		ubyte[] data = new ubyte[count];
		uint realCount;
		
		file.seek(offset);
		file.rawRead(data);
		
		
		if ((size - offset) < count)
		{
			realCount = cast(uint) (size - offset);
		}
		else
		{
			realCount = count;
		}
		
		return cast(StyxObject[])[
			new Count(cast(uint) realCount),
			new Data(data[0..realCount])
		];
	}
}

auto readAt(ubyte[] data, ulong offset, uint count)
{
	auto size = data.length;
	if (offset >= size)
	{
		return cast(StyxObject[])[
			new Count(0),
			new Data
		];
	}
	else
	{
		ubyte[]  bdata;
		
		if ((offset + count) > data.length)
		{
			if (offset >= data.length)
			{
				return cast(StyxObject[])[
					new Count(0),
					new Data
				];
			}
			else
			{
				bdata = data[offset..$];
			}
		}
		else
		{
			bdata = data[offset..offset+count];
		}
		
		return cast(StyxObject[])[
			new Count(cast(uint) bdata.length),
			new Data(bdata)
		];
	}
}

auto writeAt(string filepath, ulong offset, uint count, ubyte[] data)
{
	File file;
	file.open(filepath, `wb`);
	
	auto buffer = data[0..count];
	file.seek(offset);
	file.rawWrite(buffer);
	
	return cast(StyxObject[])[
		new Count(cast(uint) buffer.length)
	];
}

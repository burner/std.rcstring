import core.memory;
import std.conv : emplace;
import std.array : back, front;


pure @safe:

struct StringPayload(T) {
	T* ptr;
	size_t length;
	long refCnt;
}

struct StringPayloadSingleThreadHandler(T) {
	alias Char = T;

	static StringPayload!T* make() @trusted {
		StringPayload!T* pl;
		pl = cast(StringPayload!T*)GC.realloc(pl, typeof(*pl).sizeof);
		pl.ptr = null;
		pl.length = 0;
		pl.refCnt = 1;

		return pl;
	}

	static void allocate(StringPayload!T* pl, in size_t s) @trusted {
		import std.range : ElementEncodingType;
		import std.traits : Unqual;

		assert(s != 0);
		if(s >= pl.length) {
			pl.ptr = cast(T*)GC.realloc(pl.ptr, s);
			pl.length = s;
		}
	}

	static void deallocate(StringPayload!T* pl) @trusted {
		GC.realloc(pl.ptr, 0);
		pl.length = 0;
		GC.realloc(pl, 0);
	}

	static void incrementRefCnt(StringPayload!T* pl) {
		if(pl !is null) {
			++(pl.refCnt);
		}
	}

	static void decrementRefCnt(StringPayload!T* pl) {
		if(pl !is null) {
			--(pl.refCnt);
			if(pl.refCnt == 0) {
				deallocate(pl);
			}
		}
	}
}

unittest {
	auto pl = StringPayloadSingleThreadHandler!char.make();
	StringPayloadSingleThreadHandler!char.allocate(pl, 6);
	StringPayloadSingleThreadHandler!char.incrementRefCnt(pl);
	StringPayloadSingleThreadHandler!char.decrementRefCnt(pl);
}

struct StringImpl(T,Handler,size_t SmallSize = 16) {
	this(immutable(T)[] input) {
		this.assign(input);
	}

	~this() {
		if(this.large !is null) {
			Handler.decrementRefCnt(this.large);
		}
	}

	private void assign(immutable(T)[] input) @trusted {
		if(input.length < SmallSize) {
			this.small[0 .. input.length] = input;
		} else {
			this.large = Handler.make();
			Handler.allocate(this.large, input.length);
			this.large.ptr[0 .. input.length] = input;
		}

		this.len = input.length;
	}
	
	private T[] largePtr(in size_t low, in size_t high) @trusted {
		return this.large.ptr[low .. high];
	}

	private const(T)[] largePtr(in size_t low, in size_t high) const @trusted {
		return this.large.ptr[low .. high];
	}

	private bool isSmall() const nothrow {
		return this.len < SmallSize;
	}

	// properties

	@property bool empty() const nothrow {
		return this.offset == this.len;
	}

	@property size_t length() const nothrow {
		return cast(size_t)(this.len - this.offset);
	}

	// access

	@property auto front() const {
		assert(!this.empty);

		return this.isSmall() ? 
			this.small.front : 
			this.largePtr(this.offset, this.len).front;
	}

	@property auto back() const {
		assert(!this.empty);

		return this.isSmall() ? 
			this.small[0 .. this.len].back : 
			this.largePtr(this.offset, this.len).back;
	}

	@property T opIndex(const size_t idx) const {
		assert(!this.empty);
		assert(idx < this.len - this.offset);

		return this.isSmall() ? 
			this.small[idx] : 
			this.largePtr(this.offset, this.len)[idx];
	}

	// assign

	void opAssign(inout(char)[] n) {
		if(this.isSmall() && n.length < SmallSize) {
			this.small[0 .. n.length] = n;
		} else {
			if(this.large is null || this.large.refCnt > 1) {
				this.large = Handler.make();
			}

			Handler.allocate(this.large, n.length);
			this.largePtr(0, n.length)[] = n;
		}

		this.len = n.length;
		this.offset = 0;
	}

	void opAssign(typeof(this) n) {
		if(this.large !is null) {
			Handler.decrementRefCnt(this.large);
		}

		if(n.large !is null) {
			this.large = n.large;
			Handler.incrementRefCnt(this.large);
		} else {
			this.small = n.small;
		}

		this.offset = n.offset;
		this.len = n.len;
	}

	T[SmallSize] small;
	StringPayload!T* large;

	ptrdiff_t offset;
	ptrdiff_t len;
}

alias String = StringImpl!(char, StringPayloadSingleThreadHandler!char);

unittest {
	import std.conv : to;

	auto strs = ["HelloSuperUltraLongStringDOubleSizeBigTime", "Hello"];
	foreach(str; strs) {
		auto s = String(str);
		assert(!s.empty);
		assert(s.front == str.front, to!string(s.front));
		assert(s.back == str.back);
		assert(s[0] == str.front);
		assert(s.length == str.length);

		String t;
		assert(t.empty);

		t = str;
		assert(!t.empty);
		assert(t.front == str.front, to!string(t.front));
		assert(t.back == str.back);
		assert(t[0] == str.front);
		assert(t.length == str.length);

		s = t;
		assert(!s.empty);
		assert(s.front == str.front, to!string(t.front));
		assert(s.back == str.back);
		assert(s[0] == str.front);
		assert(s.length == str.length);
	}
}

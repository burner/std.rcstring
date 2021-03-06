module rcstring;

import core.stdc.stdlib : realloc, malloc, free;
//import core.memory;
//import std.conv : emplace;
//import std.array : back, front;
//import std.traits : Unqual;

struct StringPayload(T,M = void) {
	T* ptr;
	size_t length;
	long refCnt;

	static if(!is(M == void)) {
    	ubyte[__traits(classInstanceSize, M)] mutex;
	}
}

struct StringPayloadHandler(T) {
	alias Char = T;
	alias Payload = StringPayload!T;

	static StringPayload!T* make() @trusted {
		StringPayload!T* pl;
		pl = cast(StringPayload!T*)realloc(pl, typeof(*pl).sizeof);
		pl.ptr = null;
		pl.length = 0;
		pl.refCnt = 1;

		return pl;
	}

	static void allocate(StringPayload!T* pl, in size_t s) @trusted {
		//assert(s != 0);
		if(s >= pl.length) {
			pl.ptr = cast(T*)realloc(pl.ptr, s * T.sizeof);
			pl.length = s;
		}
	}

	static void deallocate(StringPayload!T* pl) @trusted {
		realloc(pl.ptr, 0);
		pl.length = 0;
		realloc(pl, 0);
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
	auto pl = StringPayloadHandler!char.make();
	StringPayloadHandler!char.allocate(pl, 6);
	StringPayloadHandler!char.incrementRefCnt(pl);
	StringPayloadHandler!char.decrementRefCnt(pl);
}

struct StringImpl(T,Handler,size_t SmallSize = 16) {
	this(immutable(T)[] input) {
		this.assign(input);
	}

	this(typeof(this) n) {
		this.assign(n);
	}

	this(this) {
		if(this.large !is null) {
			Handler.incrementRefCnt(this.large);
		}
	}

	~this() @trusted {
		if(this.large !is null) {
			Handler.decrementRefCnt(cast(Handler.Payload*)this.large);
		}
	}

	private void assign(typeof(this) n) @trusted {
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

	private void assign(immutable(T)[] input) @trusted {
		if(input.length > SmallSize) {
			this.allocate(input.length);
		}

		this.storePtr()[0 .. input.length] = input;
		this.len = input.length;
	}

	private void allocate(const size_t newLen) @trusted {
		if(newLen > SmallSize) {
			if(this.large is null) {
				this.large = Handler.make();
			}
			Handler.allocate(this.large, newLen);
		}
	}
	
	private T[] largePtr(in size_t low, in size_t high) @trusted {
		return this.large.ptr[low .. high];
	}

	private bool isSmall() const nothrow {
		return this.large is null;
	}

	private T* storePtr() {
		if(this.isSmall()) {
			return this.small.ptr;
		} else {
			return this.large.ptr;
		}
	}

	private const(T)* storePtr() const {
		if(this.isSmall()) {
			return this.small.ptr;
		} else {
			return this.large.ptr;
		}
	}

	// properties

	@property bool empty() const nothrow {
		return this.offset == this.len;
	}

	@property size_t length() const nothrow {
		return cast(size_t)(this.len - this.offset);
	}

	// compare
	
	import std.traits : Unqual;

	bool opEquals(S)(S other) const 
		if(is(S == Unqual!(typeof(this))) ||
			is(S == immutable(T)[])
		)
	{
		if(this.length == other.length) {
			for(size_t i = 0; i < this.length; ++i) {
				if(this[i] != other[i]) {
					return false;
				}
			}

			return true;
		} else {
			return false;
		}
	}

	// dup

	@property typeof(this) dup() @trusted {
		if(this.isSmall()) {
			return this;
		} else {
			typeof(this) ret;
			ret.large = ret.handler.make();
			ret.handler.allocate(ret.large, this.large.length);
			ret.large.ptr[0 .. this.len - this.offset] =
				this.large.ptr[this.offset .. this.len];
			ret.offset = 0;
			ret.len = this.len - this.offset;

			return ret;
		}
	}

	// concat
	typeof(this) opBinary(string op,S)(S other) @trusted
		if((is(S == Unqual!(typeof(this))) ||
			is(S == immutable(T)[])) && op == "~")
	{
		typeof(this) ret;

		const newLen = this.length + other.length;

		if(newLen < SmallSize) {
			ret.small[0 .. this.length] = 
				this.storePtr()[this.offset .. this.len];

			ret.offset = 0;
			ret.len = this.length;

			static if(is(S == immutable(T)[])) {
				ret.small[ret.length .. ret.length + other.length] =
					other;
			} else {
				ret.small[ret.length .. ret.length + other.length] =
					other.storePtr()[other.offset .. other.len];
			}

			ret.len = ret.len + other.length;
			return ret;
		} else {
			ret.large = ret.handler.make();
			ret.handler.allocate(ret.large, cast(size_t)(newLen * 1.5));

			ret.large.ptr[0 .. this.length] = this.isSmall() ? 
				this.small[this.offset .. this.len] :
				this.largePtr(this.offset, this.len);

			ret.offset = 0;
			ret.len = this.length;

			static if(is(S == immutable(T)[])) {
				ret.large.ptr[ret.length .. ret.length + other.length] =
					other;
			} else {
				ret.large.ptr[ret.length .. ret.length + other.length] =
					other.storePtr()[other.offset .. other.len];
			}

			ret.len = ret.len + other.length;
			return ret;
		}
	}

	// access

	@property T front() const @trusted {
		//assert(!this.empty);
		return this.storePtr()[this.offset .. this.len][0];
	}

	@property T back() const @trusted {
		//assert(!this.empty);
		return this.storePtr()[this.offset .. this.len][$ - 1];
	}

	@property T opIndex(const size_t idx) const @trusted {
		//assert(!this.empty);
		//assert(idx < this.len - this.offset);

		return this.storePtr()[this.offset .. this.len][idx];
	}

	typeof(this) opSlice() {
		return this;
	}

	typeof(this) opSlice(in size_t low, in size_t high) @trusted {
		//assert(low <= high);
		//assert(high < this.length);

		if(this.isSmall()) {
			return typeof(this)(
				cast(immutable(T)[])this.small[
					this.offset + low ..  this.offset + high
				]
			);
		} else {
			auto ret = typeof(this)(this);
			ret.offset += low;
			ret.len = this.offset + high;
			return ret;
		}
	}

	/*immutable(T)[] idup() @trusted const {
		return this.storePtr()[this.offset .. this.offset + this.len].idup;
	}*/

	// assign

	void opAssign(inout(T)[] n) {
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
		this.assign(n);
	}

	// modify

	/*void popFront() {
		import std.utf : stride;

		const auto l = this.isSmall() ? 
			this.small[this.offset .. this.len].stride() :
			this.largePtr(this.offset, this.len).stride();

		this.offset += l;
	}*/

	/*void popBack() {
		import std.utf : strideBack;

		const auto l = this.isSmall() ? 
			this.small[this.offset .. this.len].strideBack() :
			this.largePtr(this.offset, this.len).strideBack();

		this.len -= l;
	}*/

	void moveToFront() {
 		if(this.offset > 0) {
			immutable len = this.length;
			if(this.isSmall()) {
				for(int i = 0; i < len; ++i) {
					this.small[i] = this.small[this.offset + i];
				}
			} else {
				for(int i = 0; i < len; ++i) {
					(() @trusted => 
					this.large.ptr[i] = this.large.ptr[this.offset + i]
					)();
				}
			}
			this.offset = 0;
			this.len = len;
		}
	}

	import std.traits : isSomeChar;

	/*void opIndexAssign(S)(S s, const size_t i) @trusted if(isSomeChar!S) {
		import std.utf : decode, encode;
		import std.conv : to;
		this.moveToFront();

		size_t iCopy = i;
		T[4 / T.sizeof] correctEncoding;
		const size_t toReplaceLen = encode(correctEncoding, 
				decode(this.storePtr()[0 .. this.len], iCopy)
		);

		const size_t replacementLen = encode(correctEncoding, s);

		T* ptr;
		if(replacementLen > toReplaceLen) {
			this.allocate(this.len + (replacementLen - toReplaceLen));
			ptr = this.storePtr();
			for(int j = to!int(this.length + (replacementLen - toReplaceLen)); j != i;
					--j)
			{
				ptr[j] = ptr[j-1];
			}
		} else if(replacementLen < toReplaceLen) {
			ptr = this.storePtr();
			for(int j = to!int(i + replacementLen); j < this.length - 1; ++j) {
				ptr[j] = ptr[j + 1];
			}
		} else {
			ptr = this.storePtr();
		}
		this.len += (replacementLen - toReplaceLen);

		for(int j = 0; j < replacementLen; ++j) {
			ptr[i + j] = correctEncoding[j];
		}
	}*/

	T[SmallSize] small;
	Handler.Payload* large;
	Handler handler;

	ptrdiff_t offset;
	ptrdiff_t len;
}

public alias String = StringImpl!(char, StringPayloadHandler!char, 12);
public alias WString = StringImpl!(wchar, StringPayloadHandler!wchar, 6);
public alias DString = StringImpl!(dchar, StringPayloadHandler!dchar, 3);

void testFunc(T,size_t Buf)() {
	auto strs = ["","ABC", "HellWorld", "", "Foobar", 
		"HellWorldHellWorldHellWorldHellWorldHellWorldHellWorldHellWorldHellWorld", 
		"ABCD", "Hello", "HellWorldHellWorld", "ölleä",
		"hello\U00010143\u0100\U00010143", "£$€¥", "öhelloöö"
	];

	alias TString = 
		StringImpl!(T, StringPayloadHandler!T, Buf);

	foreach(strL; strs) {
		auto str = to!(immutable(T)[])(strL);
		auto s = TString(str);

		assert(s.length == str.length);
		assert(s.empty == str.empty);
		assert(s == str);

		auto istr = s.idup();
		assert(str == istr);

		foreach(it; strs) {
			auto cmpS = cast(immutable(T)[])(it);
			auto itStr = TString(cmpS);

			if(cmpS == str) {
				assert(s == cmpS);
				assert(s == itStr);
			} else {
				assert(s != cmpS);
				assert(s != itStr);
			}
		}

		if(s.empty) { // if str is empty we do not need to test access
			continue; //methods
		}

		assert(s.front == str.front);
		assert(s.back == str.back);
		assert(s[0] == str[0]);
		for(size_t i = 0; i < str.length; ++i) {
			assert(str[i] == s[i]);
		}

		for(size_t it = 0; it < str.length; ++it) {
			for(size_t jt = it; jt < str.length; ++jt) {
				auto ss = s[it .. jt];
				auto strc = str[it .. jt];

				assert(ss.length == strc.length);
				assert(ss.empty == strc.empty);

				for(size_t k = 0; k < ss.length; ++k) {
					assert(ss[k] == strc[k]);
				}
			}
		}

		TString t;
		assert(t.empty);

		t = str;
		assert(s == t);
		assert(!t.empty);
		assert(t.front == str.front);
		assert(t.back == str.back);
		assert(t[0] == str[0]);
		assert(t.length == str.length);

		auto tdup = t.dup;
		assert(!tdup.empty);
		assert(tdup.front == str.front);
		assert(tdup.back == str.back);
		assert(tdup[0] == str[0]);
		assert(tdup.length == str.length);

		istr = t.idup();
		assert(str == istr);
		
		if(tdup.large !is null) {
			assert(tdup.large.refCnt == 1);
		}

		foreach(it; strs) {
			auto joinStr = cast(immutable(T)[])(it);
			auto itStr = TString(joinStr);
			auto compareStr = str ~ joinStr;

			auto t2dup = tdup ~ joinStr;
			auto t2dup2 = tdup ~ itStr;

			assert(t2dup.length == compareStr.length);
			assert(t2dup2.length == compareStr.length);

			assert(t2dup == compareStr);
			assert(t2dup2 == compareStr);
		}

		s = t;
		assert(!s.empty);
		assert(s.front == str.front);
		assert(s.back == str.back);
		assert(s[0] == str[0]);
		assert(s.length == str.length);

		auto r = TString(s);
		assert(!r.empty);
		assert(r.front == str.front);
		assert(r.back == str.back);
		assert(r[0] == str[0]);
		assert(r.length == str.length);

		auto g = r[];
		assert(!g.empty);
		assert(g.front == str.front);
		assert(g.back == str.back);
		assert(g[0] == str[0]);
		assert(g.length == str.length);

		auto strC = str;
		auto strC2 = str;
		assert(!strC.empty);
		assert(!strC2.empty);

		r.popFront();
		str.popFront();
		assert(str.front == r.front);
		assert(s != r);

		r.popBack();
		str.popBack();
		assert(str.back == r.back);
		assert(str.front == r.front);

		assert(!strC.empty);
		assert(!s.empty);
		while(!strC.empty && !s.empty) {
			assert(strC.front == s.front);
			assert(strC.back == s.back);
			assert(strC.length == s.length);
			for(size_t i = 0; i < strC.length; ++i) {
				assert(strC[i] == s[i]);
			}

			strC.popFront();
			s.popFront();
		}

		assert(strC.empty);
		assert(s.empty);

		assert(!strC2.empty);
		assert(!t.empty);
		while(!strC2.empty && !t.empty) {
			assert(strC2.front == t.front);
			assert(strC2.back == t.back);
			assert(strC2.length == t.length);
			for(size_t i = 0; i < strC2.length; ++i) {
				assert(strC2[i] == t[i]);
			}

			strC2.popFront();
			t.popFront();
			t.moveToFront();

			auto idup2 = t.idup;
			assert(t == idup2);
			assert(t == strC2);
		}

		assert(strC2.empty);
		assert(t.empty);
	}
}

unittest {
	testFunc!(char,3)();
}

@safe unittest {
	import std.meta : AliasSeq;

	foreach(Buf; AliasSeq!(1,2,3,4,8,9,12,16,20,21)) {
		testFunc!(char,Buf)();
		testFunc!(wchar,Buf)();
		testFunc!(dchar,Buf)();
	}
}

@system unittest {
	String s = "Super Duper ultra long String";
	const String s2 = s;
}

@system unittest {
	String s = "Super";
	s[0] = 'A';
	assert(s == "Auper");
	//string dc = "Ä";
	//s[0] = dc[0];
	//assert(s == "Äuper");
}

/+
@system unittest {
	import std.meta : AliasSeq;
	foreach(T; AliasSeq!(string,wstring,dstring)) {
		String s = "Super Duper ultra long String";
		s[0] = 'A';
		assert(s == "Auper Duper ultra long String");

		dchar dc = 'ä';
		s[1] = dc;
		assert(s == "Aäper Duper ultra long String");
		s.popFront();

		dc = 'u';
		s[0] = dc;
		assert(s == "uper Duper ultra long String");
	}
}+/

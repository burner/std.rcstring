# RCString a reference counted string

The module rcstring provides everything necessary to replace D's build-in
strings with a reference counted version. It should be as easy as replacing
all occurrences of the keyword string with String.

Additional, to String there are WString and DString defined in this module.

```d
String str = "Hello World";
assert(str.front == "H");
assert(str.back == "d");

auto slice = str[1 .. 5];
assert(slice == "ello");

slice.popFront();
assert(slice == "llo");

```

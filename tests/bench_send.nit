# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2004-2008 Jean Privat <jean@pryen.org>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


class A
	readable writable attr _val: Int
	meth hop(a: A, b: A, c: A)
	do
		if a.val > val then
			a.hop(b, c, self)
		end
		foo(a, b)
		foo(a, c)
		foo(b, c)
		foo(c, b)
	end
	meth foo(a: A, b: A)
	do
		if a.val > val then
			a.foo(b, self)
		end
		bar(a)
		bar(b)
	end
	meth bar(a: A)
	do
		if a.val > val then
			a.bar(self)
		end
		baz
	end
	meth baz
	do
	end

	init
	do
	end
end

class B
special A
	redef meth val: Int
	do
		return 1
	end

	redef init
	do
	end
end

class C
special A
	redef meth val: Int
	do
		return 2
	end

	redef init
	do
	end
end

class D
special A
	redef meth val: Int
	do
		return 3
	end

	redef init
	do
	end
end

var a = new A
var b = new B
var c = new C
var d = new D

a.val = 0
b.val = 1
c.val = 2
d.val = 3
var i = 0
while i < 100000 do
	a.hop(b, c, d)
	i = i + 1
end
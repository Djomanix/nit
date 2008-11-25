# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2008 Jean Privat <jean@pryen.org>
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

import base_init_linext

redef class B
	redef init initb do
		'b'.output
		'1'.output
		' '.output
		super
		'b'.output
		'2'.output
		' '.output
	end
end

redef class C
	redef init initc do
		'c'.output
		'1'.output
		' '.output
		super
		'c'.output
		'2'.output
		' '.output
	end
end

redef class D
	redef init initd do
		'd'.output
		'1'.output
		' '.output
		super
		'd'.output
		'2'.output
		' '.output
	end
end

(new A.inita).work
(new B.initb).work
(new C.initc).work
(new D.initd).work
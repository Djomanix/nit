# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2005-2008 Jean Privat <jean@pryen.org>
#
# This file is free software, which comes along with NIT.  This software is
# distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without  even  the implied warranty of  MERCHANTABILITY or  FITNESS FOR A 
# PARTICULAR PURPOSE.  You can modify it is you want,  provided this header
# is kept unaltered, and a notification of the changes is added.
# You  are  allowed  to  redistribute it and sell it, alone or is a part of
# another product.

# This module is about string search and matching.
# It includes some good features
package string_search

import string

# Patterns are string motifs.
class Pattern
	# Search `self' into `s' from a certain position.
	# Return the position of the first character of the matching section.
	# Return -1 if not found.
	meth search_index_in(s: String, from: Int): Int is abstract

	# Search `self' into `s' from a certain position.
	# Return null if not found.
	meth search_in(s: String, from: Int): Match is abstract

	# Search all `self' occucences into `s'.
	meth search_all_in(s: String): Array[Match]
	do
		var res = new Array[Match] # Result
		var match = search_in(s, 0)
		while match != null do
			res.add(match)
			match = search_in(s, match.after)
		end
		return res
	end

	# Split `s' using `self' is separator.
	meth split_in(s: String): Array[Match]
	do
		var res = new Array[Match] # Result
		var i = 0 # Cursor
		var match = search_in(s, 0)
		while match != null do
			# Compute the splited part length
			var len = match.from - i
			res.add(new Match(s, i, len))
			i = match.after
			match = search_in(s, i)
		end
		# Add the last part
		res.add(new Match(s, i, s.length - i))
		return res
	end
end

# BM_Pattern are precompiled string motif for the Boyer-Moore Fast String Searching Algorithm
# (cf. A Fast String Searching Algorithm, with R.S. Boyer.
# Communications of the Association for Computing Machinery, 20(10), 1977, pp. 762-772.)
# see also http://www.cs.utexas.edu/users/moore/best-ideas/string-searching/index.html
class BM_Pattern
special Pattern 
	redef meth to_s do return _motif

	# boyer-moore search gives the position of the first occurence of a pattern starting at position `from'
	redef meth search_index_in(s, from)
	do
		assert from >= 0
		var n = s.length
		var m = _length

		var j = from
		while j < n - m + 1 do
			var i = m - 1 # Cursor in the pattern
			while i >= 0 and _motif[i] == s[i + j] do i -= 1
			if (i < 0) then
				return j
			else
				var gs = _gs[i] # Good shift
				var bc = bc(s[i+j]) - m + 1 + i # Bad char
				# Both are true, do move to the best
				if gs > bc then
					j += gs
				else
					j += bc
				end
			end
		end
		return -1 # found nothing
	end

	# boyer-moore search. Return null if not found 
	redef meth search_in(s, from)
	do
		var to = search_index_in(s, from)
		if to < 0 then
			return null
		else
			return new Match(s, to, _length)
		end
	end

	# Compile a new motif 
	init(motif: String)
	do
		_motif = motif
		_length = motif.length
		_gs = new Array[Int].with_capacity(_length)
		_bc_table = new ArrayMap[Char, Int]
		compute_gs
		compute_bc
	end

	# searched motif
	attr _motif: String

	# length of the motif
	attr _length: Int

	private meth bc(e: Char): Int
	do 
		if _bc_table.has_key(e) then
			return _bc_table[e]
		else
			return _length
		end
	end

	# good shifts
	attr _gs: Array[Int]
	
	# bad characters
	attr _bc_table: Map[Char, Int]

	private meth compute_bc
	do
		var x = _motif
		var m = _length
		var i = 0
		while i < m - 1 do
			_bc_table[x[i]] = m - i - 1
			i += 1
		end
	end

	private meth suffixes: Array[Int]
	do
		var x = _motif
		var m = _length
		var suff = new Array[Int].filled_with(m, m)

		var f = 0
		var g = m - 1
		var i = m - 2
		while i >= 0 do
			if i > g and suff[i+m-1-f] < i - g then
				suff[i] = suff[i+m-1-f]
			else
				if i < g then g = i
				f = i
				while g >= 0 and x[g] == x[g + m - 1 - f] do g -= 1
				suff[i] = f - g
			end
			i -= 1
		end
		return suff
	end

	private meth compute_gs
	do
		var x = _motif
		var m = _length
		var suff = suffixes
		var i = 0
		while i < m do
			_gs[i] = m
			i += 1
		end
		var j = 0
		i = m - 1
		while i >= -1 do
			if i == -1 or suff[i] == i + 1 then
				while j < m - 1 - i do
					if _gs[j] == m then _gs[j] = m - 1 - i
					j += 1
				end
			end
			i -= 1
		end
		i = 0
		while i < m - 1 do
			_gs[m - 1 - suff[i]] = m - 1 - i
			i += 1
		end
	end
end

# Matches are a part of a string.
class Match
	# The base string matched
	readable attr _string: String

	# The starting position in the string
	readable attr _from: Int

	# The length of the mathching part
	readable attr _length: Int

	# The position of the first character just after the matching part.
	# May be out of the base string
	meth after: Int do return _from + _length

	# The contents of the mathing part
	redef meth to_s do return _string.substring(_from, _length)

	# Matches `len' characters of `s' from `f'.
	init(s: String, f: Int, len: Int)
	do
		assert non_null_string: s != null 
		assert positive_length: len >= 0
		assert valid_from: f >= 0
		assert valid_after: f + len <= s.length
		_string = s
		_from = f
		_length = len
	end
end

redef class Char
special Pattern
	redef meth search_index_in(s, from)
	do
		var stop = s.length
		while from < stop do
			if s[from] == self then return from
			from += 1
		end
		return -1
	end

	redef meth search_in(s, from)
	do
		var pos = search_index_in(s, from)
		if pos < 0 then
			return null
		else
			return new Match(s, pos, 1)
		end
	end
end

redef class String
special Pattern
	redef meth search_index_in(s, from)
	do
		assert from >= 0
		var stop = s.length - length + 1
		while from < stop do
			var i = length - 1
			while i >= 0 and self[i] == s[i + from] do i -= 1
			# Test if we found
			if i < 0 then return from
			# Not found so try next one
			from += 1
		end
		return -1
	end

	redef meth search_in(s, from)
	do
		var pos = search_index_in(s, from)
		if pos < 0 then
			return null
		else
			return new Match(s, pos, length)
		end
	end

	# Like `search_from' but from the first chararter.
	meth search(p: Pattern): Match do return p.search_in(self, 0)

	# Search the given pattern into self from a.
	# The search starts at `from'.
	# Return null if not found.
	meth search_from(p: Pattern, from: Int): Match do return p.search_in(self, from)

	# Search all occurences of p into self.
	#
	#   var a = new Array[Int]
	#   for i in "hello world".searches('o') do
	#       a.add(i.from)
	#   end
	#   a    # -> [4, 7]
	meth search_all(p: Pattern): Array[Match] do return p.search_all_in(self)

	# Split self using p is separator.
	#   "hello world".split('o')     # -> ["hell", " w", "rld"]
	meth split_with(p: Pattern): Array[String]
	do
		var matches = p.split_in(self)
		var res = new Array[String].with_capacity(matches.length)
		for m in matches do res.add(m.to_s)
		return res
	end

	# Split self using '\n' is separator.
	#   "hello\nworld".split     # -> ["hello","world"]
	meth split: Array[String] do return split_with('\n')
end
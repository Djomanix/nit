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

# Compile method bodies, statments and expressions to C.
package compiling_methods

import compiling_base
private import syntax

redef class CompilerVisitor
	# Compile a statment node
	meth compile_stmt(n: PExpr)
	do
		n.prepare_compile_stmt(self)
		var i = _variable_index
		n.compile_stmt(self)
		_variable_index = i
	end

	# Compile is expression node
	meth compile_expr(n: PExpr): String
	do
		var i = _variable_index
		var s = n.compile_expr(self)
		_variable_index = i
		if s[0] == ' ' then
			return s
		end
		if s == variable(_variable_index-1) then
			return s
		end
		var v = get_var
		add_assignment(v, s)
		return v
	end

	# Ensure that a c expression is a var
	meth ensure_var(s: String): String
	do
		if s.substring(0,3) == "variable" then
			return s
		end
		var v = get_var
		add_assignment(v, s)
		return v
	end

	# Add a assignment between a variable and an expression
	meth add_assignment(v: String, s: String)
	do
		if v != s then
			add_instr("{v} = {s};")
		end
	end

	# Return the ith variable
	protected meth variable(i: Int): String
	do
		return "variable{i}"
	end

	# Next available variable number
	attr _variable_index: Int

	# Total number of variable
	attr _variable_index_max: Int

	# Return the next available variable
	meth get_var: String
	do
		var v = variable(_variable_index)
		_variable_index = _variable_index + 1
		if _variable_index > _variable_index_max then
			add_decl("val_t {v};")
			_variable_index_max = _variable_index 
		end
		return v
	end

	# Mark the variable available
	meth free_var(v: String)
	do
		# FIXME: So ugly..
		if v == variable(_variable_index-1) then
			_variable_index = _variable_index - 1
		end
	end

	# Clear all status related to a method body
	meth clear
	do
		_has_return = false
		indent_level = 0
		_variable_index = 0
		_variable_index_max = 0
	end

	# Association between nit variable and the corrsponding c variable
	readable attr _varnames: Map[Variable, String] = new HashMap[Variable, String] 

	# Is a "return" found in the method body
	readable writable attr _has_return: Bool

	# Association between parameters and the corresponding c variables
	readable writable attr _method_params: Array[String] 

	# Current method compiled
	readable writable attr _method: MMSrcMethod

	# Where a nit return must branch
	readable writable attr _return_label: String 
	
	# Where a nit break must branch
	readable writable attr _break_label: String 
	
	# Where a nit continue must branch
	readable writable attr _continue_label: String 

	# Variable where a functionnal nit return must store its value
	readable writable attr _return_value: String 

	# Generate an fprintf to display an error location
	meth printf_locate_error(node: PNode): String
	do
		var s = "fprintf(stderr, \""
		if method != null then s.append(" in %s")
		s.append(" (%s:%d)\\n\", ")
		if method != null then s.append("LOCATE_{method.cname}, ")
		s.append("LOCATE_{module.name}, {node.line_number});")
		return s
	end

	redef init(module: MMSrcModule)
	do
		super
		clear
	end

	meth invoke_super_init_calls_after(start_prop: MMMethod)
	do
		var n = method.node
		assert n isa AConcreteInitPropdef

		if n.super_init_calls.is_empty then return
		var i = 0
		var j = 0
		#var s = ""
		if start_prop != null then
			while n.super_init_calls[i] != start_prop do
				#s.append(" {n.super_init_calls[i]}")
				i += 1
			end
			i += 1
			#s.append(" {start_prop}")

			while n.explicit_super_init_calls[j] != start_prop do
				j += 1
			end
			j += 1
		end
		var stop_prop: MMMethod = null
		if j < n.explicit_super_init_calls.length then
			stop_prop = n.explicit_super_init_calls[j]
		end
		var l = n.super_init_calls.length
		#s.append(" [")
		while i < l do
			var p = n.super_init_calls[i]
			if p == stop_prop then break
			var cargs = method_params
			if p.signature.arity == 0 then
				cargs = [method_params[0]]
			end
			#s.append(" {p}")
			p.compile_call(self, cargs)
			i += 1
		end
		#s.append(" ]")
		#while i < l do
		#	s.append(" {n.super_init_calls[i]}")
		#	i += 1
		#end
		#if stop_prop != null then s.append(" (stop at {stop_prop})")
		#n.printl("implicit calls in {n.method}: {s}") 
	end
end

###############################################################################

redef class MMMethod
	# Compile a call on self for given arguments
	# Most calls are compiled with a table access,
	# primitive calles are inlined
	# == and != are guarded and possibly inlined
	meth compile_call(v: CompilerVisitor, cargs: Array[String]): String
	do
		var i = concrete_property
		assert i isa MMSrcMethod
		if i.node isa AInternMethPropdef or 
			(i.local_class.name == (once "Array".to_symbol) and name == (once "[]".to_symbol))
		then
			var e = i.do_compile_inside(v, cargs)
			return e
		end
		var ee = once "==".to_symbol
		var ne = once "!=".to_symbol
		if name == ne then
			var eqp = signature.recv.select_method(ee)
			var eqcall = eqp.compile_call(v, cargs)
			return "TAG_Bool(!UNTAG_Bool({eqcall}))"
		end
		if global.is_init then
			cargs = cargs.to_a
			cargs.add("init_table /*YYY*/")
		end

		var m = "(({cname}_t)CALL({cargs[0]},{global.color_id}))"
		var vcall = "{m}({cargs.join(", ")}) /*{local_class}::{name}*/"
		if name == ee then
			vcall = "UNTAG_Bool({vcall})"
			var obj = once "Object".to_symbol
			if i.local_class.name == obj then
				vcall = "(({m}=={i.cname})?(IS_EQUAL_NN({cargs[0]},{cargs[1]})):({vcall}))"
			end
			vcall = "TAG_Bool(({cargs.first} == {cargs[1]}) || (({cargs.first} != NIT_NULL) && {vcall}))"
		end
		if signature.return_type != null then
			return vcall
		else
			v.add_instr(vcall + ";")
			return null
		end
	end

	# Compile a call as constructor with given args
	meth compile_constructor_call(v: CompilerVisitor, cargs: Array[String]): String
	do
		var recv = v.get_var
		var stype = signature.recv
		v.add_instr("{recv} = NEW_{global.intro.cname}({cargs.join(", ")}); /*new {stype}*/")
		return recv
	end

	# Compile a call as call-next-method on self with given args
	meth compile_super_call(v: CompilerVisitor, cargs: Array[String]): String
	do
		var m = "(({cname}_t)CALL({cargs[0]},{color_id_for_super}))"
		var vcall = "{m}({cargs.join(", ")}) /*super {local_class}::{name}*/"
		return vcall
	end
end

redef class MMAttribute
	# Compile an acces on selffor a given reciever.
	# Result is a valid C left-value for assigment
	meth compile_access(v: CompilerVisitor, recv: String): String
	do
		return "{global.attr_access}({recv}) /*{local_class}::{name}*/"
	end
end

redef class MMConcreteProperty
	# Compile the property as a C property
	meth compile_property_to_c(v: CompilerVisitor) do end
end

redef class MMSrcMethod
	# Compile and declare the signature to C
	protected meth decl_csignature(v: CompilerVisitor, args: Array[String]): String
	do
		var params = new Array[String]
		var params_new: Array[String] = null
		if global.is_init then
			params_new = new Array[String]
		end
		params.add("val_t {args[0]}")
		for i in [0..signature.arity[ do
			var p = "val_t {args[i+1]}"
			params.add(p)
			if params_new != null then params_new.add(p)
		end
		if global.is_init then
			params.add("int* init_table")
		end
		var ret: String
		if signature.return_type != null then
			ret = "val_t"
		else
			ret = "void"
		end
		var p = params.join(", ")
		var s = "{ret} {cname}({p})"
		v.add_decl("typedef {ret} (* {cname}_t)({p});")
		v.add_decl(s + ";")
		if params_new != null then
			v.add_decl("val_t NEW_{cname}({params_new.join(", ")});")
		end
		return s
	end

	redef meth compile_property_to_c(v)
	do
		v.clear
		var args = new Array[String]
		args.add(" self")
		for i in [0..signature.arity[ do
			args.add(" param{i}")
		end
		var cs = decl_csignature(v, args)
		v.add_decl("#define LOCATE_{cname} \"{full_name}\"")

		v.add_instr("{cs} \{")
		v.indent
		var ctx_old = v.ctx
		v.ctx = new CContext

		v.add_decl("struct trace_t trace = \{NULL, LOCATE_{module.name}, {node.line_number}, LOCATE_{cname}};")
		v.add_instr("trace.prev = tracehead; tracehead = &trace;")
		var s = do_compile_inside(v, args)
		v.add_instr("tracehead = trace.prev;")
		if s == null then
			v.add_instr("return;")
		else
			v.add_instr("return {s};")
		end

		ctx_old.append(v.ctx)
		v.ctx = ctx_old
		v.unindent
		v.add_instr("}")
	end

	# Compile the method body inline
	meth do_compile_inside(v: CompilerVisitor, params: Array[String]): String is abstract
end

redef class MMReadImplementationMethod
	redef meth do_compile_inside(v, params)
	do
		return node.prop.compile_access(v, params[0])
	end
end

redef class MMWriteImplementationMethod
	redef meth do_compile_inside(v, params)
	do
		v.add_assignment(node.prop.compile_access(v, params[0]), params[1])
		return null
	end
end

redef class MMMethSrcMethod
	redef meth do_compile_inside(v, params)
	do
		return node.do_compile_inside(v, self, params)
	end
end

redef class MMType
	# Compile a subtype check to self
	# Return a NIT Bool
	meth compile_cast(v: CompilerVisitor, recv: String): String
	do
		# Fixme: handle formaltypes
		var g = local_class.global
		return "TAG_Bool(({recv}==NIT_NULL) || VAL_ISA({recv}, {g.color_id}, {g.id_id})) /*cast {self}*/"
	end

	# Compile a cast assertion
	meth compile_type_check(v: CompilerVisitor, recv: String, n: PNode)
	do
		# Fixme: handle formaltypes
		var g = local_class.global
		v.add_instr("if (({recv}!=NIT_NULL) && !VAL_ISA({recv}, {g.color_id}, {g.id_id})) \{ fprintf(stderr, \"Cast failled\"); {v.printf_locate_error(n)} nit_exit(1); } /*cast {self}*/;")
	end
end

###############################################################################

redef class AMethPropdef
	# Compile the method body
	meth do_compile_inside(v: CompilerVisitor, method: MMSrcMethod, params: Array[String]): String is abstract
end

redef class AConcreteMethPropdef
	redef meth do_compile_inside(v, method, params)
	do
		var orig_meth: MMLocalProperty = method.global.intro
		var orig_sig = orig_meth.signature.adaptation_to(method.signature.recv)
		if n_signature != null then
			var sig = n_signature
			assert sig isa ASignature
			for ap in sig.n_params do
				var cname = v.get_var
				v.varnames[ap.variable] = cname
				var orig_type = orig_sig[ap.position]
				if not orig_type < ap.variable.stype then
					# FIXME: do not test always
					# FIXME: handle formal types
					v.add_instr("/* check if p<{ap.variable.stype} with p:{orig_type} */")
					ap.variable.stype.compile_type_check(v, params[ap.position + 1], ap)
				end
				v.add_assignment(cname, params[ap.position + 1])
			end
		end
		var old_method_params = v.method_params
		var old_return_label = v.return_label
		var old_return_value = v.return_value
		var old_has_return = v.has_return

		var itpos: String = null
		if self isa AConcreteInitPropdef then
			itpos = "VAL2OBJ({params[0]})->vft[{method.local_class.global.init_table_pos_id}].i"
			# v.add_instr("printf(\"{method.full_name}: inittable[%d] = %d\\n\", {itpos}, init_table[{itpos}]);")
			v.add_instr("if (init_table[{itpos}]) return;")
		end

		v.method_params = params
		v.has_return = false
		v.return_label = "return_label{v.new_number}"
		if method.signature.return_type != null then
			v.return_value = v.get_var
			v.free_var(v.return_value)
		else
			v.return_value = null
		end
		v.method = method
		if self isa AConcreteInitPropdef then
			v.invoke_super_init_calls_after(null)
		end
		if n_block != null then
			v.compile_stmt(n_block)
		end
		if v.has_return then
			v.add_instr("{v.return_label}: while(false);")
		end
		if self isa AConcreteInitPropdef then
			v.add_instr("init_table[{itpos}] = 1;")
		end
		var ret = v.return_value
		v.method_params = old_method_params
		v.return_label = old_return_label
		v.return_value = old_return_value
		v.has_return = old_has_return
		return ret
	end
end

redef class ADeferredMethPropdef
	redef meth do_compile_inside(v, method, params)
	do
		v.add_instr("fprintf(stderr, \"Deferred method %s called\");")
		v.add_instr(v.printf_locate_error(self))
		v.add_instr("nit_exit(1);")
		if method.signature.return_type != null then
			return("NIT_NULL")
		else
			return null
		end
	end
end

redef class AExternMethPropdef
	redef meth do_compile_inside(v, method, params)
	do
		var ename = "{method.module.name}_{method.local_class.name}_{method.local_class.name}_{method.name}_{method.signature.arity}"
		if n_extern != null then
			ename = n_extern.text
			ename = ename.substring(1, ename.length-2)
		end
		var sig = method.signature
		if params.length != sig.arity + 1 then
			printl("par:{params.length} sig:{sig.arity}")
		end
		var args = new Array[String]
		args.add(sig.recv.unboxtype(params[0]))
		for i in [0..sig.arity[ do
			args.add(sig[i].unboxtype(params[i+1]))
		end
		var s = "{ename}({args.join(", ")})"
		if sig.return_type != null then
			return sig.return_type.boxtype(s)
		else
			v.add_instr("{s};")
			return null
		end
	end
end

redef class AInternMethPropdef
	redef meth do_compile_inside(v, method, p)
	do
		var c = method.local_class.name
		var n = method.name
		var s: String = null
		if c == once "Int".to_symbol then
			if n == once "object_id".to_symbol then
				s = "{p[0]}"
			else if n == once "unary -".to_symbol then
				s = "TAG_Int(-UNTAG_Int({p[0]}))"
			else if n == once "output".to_symbol then
				v.add_instr("printf(\"%d\\n\", UNTAG_Int({p[0]}));")
			else if n == once "ascii".to_symbol then
				s = "TAG_Char(UNTAG_Int({p[0]}))"
			else if n == once "succ".to_symbol then
				s = "TAG_Int(UNTAG_Int({p[0]})+1)"
			else if n == once "prec".to_symbol then
				s = "TAG_Int(UNTAG_Int({p[0]})-1)"
			else if n == once "to_f".to_symbol then
				s = "BOX_Float((float)UNTAG_Int({p[0]}))"
			else if n == once "+".to_symbol then
				s = "TAG_Int(UNTAG_Int({p[0]})+UNTAG_Int({p[1]}))" 
			else if n == once "-".to_symbol then
				s = "TAG_Int(UNTAG_Int({p[0]})-UNTAG_Int({p[1]}))" 
			else if n == once "*".to_symbol then
				s = "TAG_Int(UNTAG_Int({p[0]})*UNTAG_Int({p[1]}))" 
			else if n == once "/".to_symbol then
				s = "TAG_Int(UNTAG_Int({p[0]})/UNTAG_Int({p[1]}))" 
			else if n == once "%".to_symbol then
				s = "TAG_Int(UNTAG_Int({p[0]})%UNTAG_Int({p[1]}))" 
			else if n == once "<".to_symbol then
				s = "TAG_Bool(UNTAG_Int({p[0]})<UNTAG_Int({p[1]}))" 
			else if n == once ">".to_symbol then
				s = "TAG_Bool(UNTAG_Int({p[0]})>UNTAG_Int({p[1]}))" 
			else if n == once "<=".to_symbol then
				s = "TAG_Bool(UNTAG_Int({p[0]})<=UNTAG_Int({p[1]}))" 
			else if n == once ">=".to_symbol then
				s = "TAG_Bool(UNTAG_Int({p[0]})>=UNTAG_Int({p[1]}))" 
			else if n == once "lshift".to_symbol then
				s = "TAG_Int(UNTAG_Int({p[0]})<<UNTAG_Int({p[1]}))" 
			else if n == once "rshift".to_symbol then
				s = "TAG_Int(UNTAG_Int({p[0]})>>UNTAG_Int({p[1]}))"
			else if n == once "==".to_symbol then
				s = "TAG_Bool(({p[0]})==({p[1]}))" 
			else if n == once "!=".to_symbol then
				s = "TAG_Bool(({p[0]})!=({p[1]}))" 
			end
		else if c == once "Float".to_symbol then
			if n == once "object_id".to_symbol then
				s = "TAG_Int((int)UNBOX_Float({p[0]}))"
			else if n == once "unary -".to_symbol then
				s = "BOX_Float(-UNBOX_Float({p[0]}))"
			else if n == once "output".to_symbol then
				v.add_instr("printf(\"%f\\n\", UNBOX_Float({p[0]}));")
			else if n == once "to_i".to_symbol then
				s = "TAG_Int((int)UNBOX_Float({p[0]}))"
			else if n == once "+".to_symbol then
				s = "BOX_Float(UNBOX_Float({p[0]})+UNBOX_Float({p[1]}))" 
			else if n == once "-".to_symbol then
				s = "BOX_Float(UNBOX_Float({p[0]})-UNBOX_Float({p[1]}))" 
			else if n == once "*".to_symbol then
				s = "BOX_Float(UNBOX_Float({p[0]})*UNBOX_Float({p[1]}))" 
			else if n == once "/".to_symbol then
				s = "BOX_Float(UNBOX_Float({p[0]})/UNBOX_Float({p[1]}))" 
			else if n == once "<".to_symbol then
				s = "TAG_Bool(UNBOX_Float({p[0]})<UNBOX_Float({p[1]}))" 
			else if n == once ">".to_symbol then
				s = "TAG_Bool(UNBOX_Float({p[0]})>UNBOX_Float({p[1]}))" 
			else if n == once "<=".to_symbol then
				s = "TAG_Bool(UNBOX_Float({p[0]})<=UNBOX_Float({p[1]}))" 
			else if n == once ">=".to_symbol then
				s = "TAG_Bool(UNBOX_Float({p[0]})>=UNBOX_Float({p[1]}))" 
			end
		else if c == once "Char".to_symbol then
			if n == once "object_id".to_symbol then
				s = "TAG_Int(UNTAG_Char({p[0]}))"
			else if n == once "unary -".to_symbol then
				s = "TAG_Char(-UNTAG_Char({p[0]}))"
			else if n == once "output".to_symbol then
				v.add_instr("printf(\"%c\", (unsigned char)UNTAG_Char({p[0]}));")
			else if n == once "ascii".to_symbol then
				s = "TAG_Int((unsigned char)UNTAG_Char({p[0]}))"
			else if n == once "succ".to_symbol then
				s = "TAG_Char(UNTAG_Char({p[0]})+1)"
			else if n == once "prec".to_symbol then
				s = "TAG_Char(UNTAG_Char({p[0]})-1)"
			else if n == once "to_i".to_symbol then
				s = "TAG_Int(UNTAG_Char({p[0]})-'0')"
			else if n == once "+".to_symbol then
				s = "TAG_Char(UNTAG_Char({p[0]})+UNTAG_Char({p[1]}))" 
			else if n == once "-".to_symbol then
				s = "TAG_Char(UNTAG_Char({p[0]})-UNTAG_Char({p[1]}))" 
			else if n == once "*".to_symbol then
				s = "TAG_Char(UNTAG_Char({p[0]})*UNTAG_Char({p[1]}))" 
			else if n == once "/".to_symbol then
				s = "TAG_Char(UNTAG_Char({p[0]})/UNTAG_Char({p[1]}))" 
			else if n == once "%".to_symbol then
				s = "TAG_Char(UNTAG_Char({p[0]})%UNTAG_Char({p[1]}))" 
			else if n == once "<".to_symbol then
				s = "TAG_Bool(UNTAG_Char({p[0]})<UNTAG_Char({p[1]}))" 
			else if n == once ">".to_symbol then
				s = "TAG_Bool(UNTAG_Char({p[0]})>UNTAG_Char({p[1]}))" 
			else if n == once "<=".to_symbol then
				s = "TAG_Bool(UNTAG_Char({p[0]})<=UNTAG_Char({p[1]}))" 
			else if n == once ">=".to_symbol then
				s = "TAG_Bool(UNTAG_Char({p[0]})>=UNTAG_Char({p[1]}))" 
			else if n == once "==".to_symbol then
				s = "TAG_Bool(({p[0]})==({p[1]}))" 
			else if n == once "!=".to_symbol then
				s = "TAG_Bool(({p[0]})!=({p[1]}))" 
			end
		else if c == once "Bool".to_symbol then
			if n == once "object_id".to_symbol then
				s = "TAG_Int(UNTAG_Bool({p[0]}))"
			else if n == once "unary -".to_symbol then
				s = "TAG_Bool(-UNTAG_Bool({p[0]}))"
			else if n == once "output".to_symbol then
				v.add_instr("(void)printf(UNTAG_Bool({p[0]})?\"true\\n\":\"false\\n\");")
			else if n == once "ascii".to_symbol then
				s = "TAG_Bool(UNTAG_Bool({p[0]}))"
			else if n == once "to_i".to_symbol then
				s = "TAG_Int(UNTAG_Bool({p[0]}))"
			else if n == once "==".to_symbol then
				s = "TAG_Bool(({p[0]})==({p[1]}))" 
			else if n == once "!=".to_symbol then
				s = "TAG_Bool(({p[0]})!=({p[1]}))" 
			end
		else if c == once "NativeArray".to_symbol then
			if n == once "object_id".to_symbol then
				s = "TAG_Int(UNBOX_NativeArray({p[0]}))"
			else if n == once "[]".to_symbol then
				s = "UNBOX_NativeArray({p[0]})[UNTAG_Int({p[1]})]"
			else if n == once "[]=".to_symbol then
				v.add_instr("UNBOX_NativeArray({p[0]})[UNTAG_Int({p[1]})]={p[2]};")
			else if n == once "copy_to".to_symbol then
				v.add_instr("(void)memcpy(UNBOX_NativeArray({p[1]}), UNBOX_NativeArray({p[0]}), UNTAG_Int({p[2]})*sizeof(val_t));")
			end	
		else if c == once "NativeString".to_symbol then
			if n == once "object_id".to_symbol then
				s = "TAG_Int(UNBOX_NativeString({p[0]}))"
			else if n == once "atoi".to_symbol then
				s = "TAG_Int(atoi(UNBOX_NativeString({p[0]})))"
			else if n == once "[]".to_symbol then
				s = "TAG_Char(UNBOX_NativeString({p[0]})[UNTAG_Int({p[1]})])"
			else if n == once "[]=".to_symbol then
				v.add_instr("UNBOX_NativeString({p[0]})[UNTAG_Int({p[1]})]=UNTAG_Char({p[2]});")
			else if n == once "copy_to".to_symbol then
				v.add_instr("(void)memcpy(UNBOX_NativeString({p[1]})+UNTAG_Int({p[4]}), UNBOX_NativeString({p[0]})+UNTAG_Int({p[3]}), UNTAG_Int({p[2]}));")
			end
		else if n == once "object_id".to_symbol then
			s = "TAG_Int((int){p[0]})"
		else if n == once "sys".to_symbol then
			s = "(G_sys)"
		else if n == once "is_same_type".to_symbol then
			s = "TAG_Bool((VAL2VFT({p[0]})==VAL2VFT({p[1]})))"
		else if n == once "exit".to_symbol then
			v.add_instr("exit(UNTAG_Int({p[1]}));")
		else if n == once "calloc_array".to_symbol then
			s = "BOX_NativeArray((val_t*)malloc((UNTAG_Int({p[1]}) * sizeof(val_t))))"
		else if n == once "calloc_string".to_symbol then
			s = "BOX_NativeString((char*)malloc((UNTAG_Int({p[1]}) * sizeof(char))))"

		else
			v.add_instr("fprintf(stderr, \"Intern {n}\\n\"); nit_exit(1);")
		end
		if method.signature.return_type != null and s == null then
			s = "NIT_NULL /*stub*/"
		end
		return s
	end
end

###############################################################################

redef class PExpr
	# Compile the node as an expression
	# Only the visitor should call it
	meth compile_expr(v: CompilerVisitor): String is abstract

	# Prepare a call of node as a statement
	# Only the visitor should call it
	# It's used for local variable managment
	meth prepare_compile_stmt(v: CompilerVisitor) do end

	# Compile the node as a statement
	# Only the visitor should call it
	meth compile_stmt(v: CompilerVisitor) do printl("Error!")
end

redef class ABlockExpr
	redef meth compile_stmt(v)
	do
		for n in n_expr do
			v.compile_stmt(n)
		end
	end
end

redef class AVardeclExpr
	redef meth prepare_compile_stmt(v)
	do
		var cname = v.get_var
		v.varnames[variable] = cname
	end

	redef meth compile_stmt(v)
	do
		var cname = v.varnames[variable]
		if n_expr == null then
			var t = variable.stype
			v.add_assignment(cname, "{t.default_cvalue} /*decl variable {variable.name}*/")
		else
			var e = v.compile_expr(n_expr)
			v.add_assignment(cname, e)
		end
	end
end

redef class AReturnExpr
	redef meth compile_stmt(v)
	do
		v.has_return = true
		if n_expr != null then
			var e = v.compile_expr(n_expr)
			v.add_assignment(v.return_value, e)
		end
		v.add_instr("goto {v.return_label};")
	end
end

redef class ABreakExpr
	redef meth compile_stmt(v)
	do
		v.add_instr("goto {v.break_label};")
	end
end

redef class AContinueExpr
	redef meth compile_stmt(v)
	do
		v.add_instr("goto {v.continue_label};")
	end
end

redef class AAbortExpr
	redef meth compile_stmt(v)
	do
		v.add_instr("fprintf(stderr, \"Aborted\"); {v.printf_locate_error(self)} nit_exit(1);")
	end
end

redef class ADoExpr
	redef meth compile_stmt(v)
	do
		 if n_block != null then
			 v.compile_stmt(n_block)
		 end
	end
end

redef class AIfExpr
	redef meth compile_stmt(v)
	do
		var e = v.compile_expr(n_expr)
		v.add_instr("if (UNTAG_Bool({e})) \{ /*if*/")
		v.free_var(e)
		if n_then != null then
			v.indent
			v.compile_stmt(n_then)
			v.unindent
		end
		if n_else != null then
			v.add_instr("} else \{ /*if*/")
			v.indent
			v.compile_stmt(n_else)
			v.unindent
		end
		v.add_instr("}")
	end
end

redef class AIfexprExpr
	redef meth compile_expr(v)
	do
		var e = v.compile_expr(n_expr)
		v.add_instr("if (UNTAG_Bool({e})) \{ /*if*/")
		v.free_var(e)
		v.indent
		var e = v.ensure_var(v.compile_expr(n_then))
		v.unindent
		v.add_instr("} else \{ /*if*/")
		v.free_var(e)
		v.indent
		var e2 = v.ensure_var(v.compile_expr(n_else))
		v.add_assignment(e, e2)
		v.unindent
		v.add_instr("}")
		return e
	end
end

redef class AControlableBlock
	meth compile_inside_block(v: CompilerVisitor) is abstract
	redef meth compile_stmt(v)
	do
		var old_break_label = v.break_label
		var old_continue_label = v.continue_label
		var id = v.new_number
		v.break_label = "break_{id}"
		v.continue_label = "continue_{id}"

		compile_inside_block(v)


		v.break_label = old_break_label
		v.continue_label = old_continue_label
	end
end

redef class AWhileExpr
	redef meth compile_inside_block(v)
	do
		v.add_instr("while (true) \{ /*while*/")
		v.indent
		var e = v.compile_expr(n_expr)
		v.add_instr("if (!UNTAG_Bool({e})) break; /* while*/")
		v.free_var(e)
		if n_block != null then
			v.compile_stmt(n_block)
		end
		v.add_instr("{v.continue_label}: while(0);")
		v.unindent
		v.add_instr("}")
		v.add_instr("{v.break_label}: while(0);")
	end
end

redef class AForExpr
	redef meth compile_inside_block(v)
	do
		v.compile_stmt(n_vardecl)
	end
end

redef class AForVardeclExpr
	redef meth compile_stmt(v)
	do
		var e = v.compile_expr(n_expr)
		var prop = n_expr.stype.select_method(once "iterator".to_symbol)
		if prop == null then
			printl("No iterator")
			return
		end
		var ittype = prop.signature.return_type
		v.free_var(e)
		var iter = v.get_var
		v.add_assignment(iter, prop.compile_call(v, [e]))
		var prop2 = ittype.select_method(once "is_ok".to_symbol)
		if prop2 == null then
			printl("No is_ok")
			return
		end
		var prop3 = ittype.select_method(once "item".to_symbol)
		if prop3 == null then
			printl("No item")
			return
		end
		var prop4 = ittype.select_method(once "next".to_symbol)
		if prop4 == null then
			printl("No next")
			return
		end
		v.add_instr("while (true) \{ /*for*/")
		v.indent
		var ok = v.get_var
		v.add_assignment(ok, prop2.compile_call(v, [iter]))
		v.add_instr("if (!UNTAG_Bool({ok})) break; /*for*/")
		v.free_var(ok)
		var e = prop3.compile_call(v, [iter])
		e = v.ensure_var(e)
		v.varnames[variable] = e
		var par = parent
		assert par isa AForExpr
		var n_block = par.n_block
		if n_block != null then
			v.compile_stmt(n_block)
		end
		v.add_instr("{v.continue_label}: while(0);")
		e = prop4.compile_call(v, [iter])
		assert e == null
		v.unindent
		v.add_instr("}")
		v.add_instr("{v.break_label}: while(0);")
	end
end

redef class AAssertExpr
	redef meth compile_stmt(v)
	do
		var e = v.compile_expr(n_expr)
		var s = ""
		if n_id != null then
			s = " '{n_id.text}' "
		end
		v.add_instr("if (!UNTAG_Bool({e})) \{ fprintf(stderr, \"Assert%s failed\", \"{s}\"); {v.printf_locate_error(self)} nit_exit(1);}")
	end
end

redef class AVarExpr
	redef meth compile_expr(v)
	do
		return " {v.varnames[variable]} /*{variable.name}*/"
	end
end

redef class AVarAssignExpr
	redef meth compile_stmt(v)
	do
		var e = v.compile_expr(n_value)
		v.add_assignment(v.varnames[variable], "{e} /*{variable.name}=*/")
	end
end

redef class AVarReassignExpr
	redef meth compile_stmt(v)
	do
		var e1 = v.varnames[variable]
		var e2 = v.compile_expr(n_value)
		var e3 = assign_method.compile_call(v, [e1, e2])
		v.add_assignment(v.varnames[variable], "{e3} /*{variable.name}*/")
	end
end

redef class ASelfExpr
	redef meth compile_expr(v)
	do
		return v.method_params[0]
	end
end

redef class AOrExpr
	redef meth compile_expr(v)
	do
		var e = v.ensure_var(v.compile_expr(n_expr))
		v.add_instr("if (!UNTAG_Bool({e})) \{ /* or */")
		v.free_var(e)
		v.indent
		var e2 = v.compile_expr(n_expr2)
		v.add_assignment(e, e2)
		v.unindent
		v.add_instr("}")
		return e
	end
end

redef class AAndExpr
	redef meth compile_expr(v)
	do
		var e = v.ensure_var(v.compile_expr(n_expr))
		v.add_instr("if (UNTAG_Bool({e})) \{ /* and */")
		v.free_var(e)
		v.indent
		var e2 = v.compile_expr(n_expr2)
		v.add_assignment(e, e2)
		v.unindent
		v.add_instr("}")
		return e
	end
end

redef class ANotExpr
	redef meth compile_expr(v)
	do
		return " TAG_Bool(!UNTAG_Bool({v.compile_expr(n_expr)}))"
	end
end

redef class AEeExpr
	redef meth compile_expr(v)
	do
		var e = v.compile_expr(n_expr)
		var e2 = v.compile_expr(n_expr2)
		return "TAG_Bool(IS_EQUAL_NN({e},{e2}))"
	end
end

redef class AIsaExpr
	redef meth compile_expr(v)
	do
		var e = v.compile_expr(n_expr)
		return n_type.stype.compile_cast(v, e)
	end
end

redef class AAsCastExpr
	redef meth compile_expr(v)
	do
		var e = v.compile_expr(n_expr)
		n_type.stype.compile_type_check(v, e, self)
		return e
	end
end

redef class ATrueExpr
	redef meth compile_expr(v)
	do
		return " TAG_Bool(true)"
	end
end

redef class AFalseExpr
	redef meth compile_expr(v)
	do
		return " TAG_Bool(false)"
	end
end

redef class AIntExpr
	redef meth compile_expr(v)
	do
		return " TAG_Int({n_number.text})"
	end
end

redef class AFloatExpr
	redef meth compile_expr(v)
	do
		return "BOX_Float({n_float.text})"
	end
end

redef class ACharExpr
	redef meth compile_expr(v)
	do
		return " TAG_Char({n_char.text})"
	end
end

redef class AStringFormExpr
	redef meth compile_expr(v)
	do
		var prop = stype.select_method(once "with_native".to_symbol)
		compute_string_info
		return prop.compile_constructor_call(v, ["BOX_NativeString(\"{_cstring}\")", "TAG_Int({_cstring_length})"])
	end

	# The raw string value
	protected meth string_text: String is abstract

	# The string in a C native format
	protected attr _cstring: String

	# The string length in bytes
	protected attr _cstring_length: Int

	# Compute _cstring and _cstring_length using string_text
	protected meth compute_string_info
	do
		var len = 0
		var str = string_text
		var res = new String
		var i = 0
		while i < str.length do
			var c = str[i]
			if c == '\\' then
				i = i + 1
				var c2 = str[i]
				if c2 != '{' and c2 != '}' then
					res.add(c)
				end
				c = c2
			end
			len = len + 1
			res.add(c)
			i = i + 1
		end
		_cstring = res
		_cstring_length = len
	end
end

redef class AStringExpr
	redef meth string_text do return n_string.text.substring(1, n_string.text.length - 2)
end
redef class AStartStringExpr
	redef meth string_text do return n_string.text.substring(1, n_string.text.length - 2)
end
redef class AMidStringExpr
	redef meth string_text do return n_string.text.substring(1, n_string.text.length - 2)
end
redef class AEndStringExpr
	redef meth string_text do return n_string.text.substring(1, n_string.text.length - 2)
end

redef class ASuperstringExpr
	redef meth compile_expr(v)
	do
		var prop = stype.select_method(once "init".to_symbol)
		var recv = prop.compile_constructor_call(v, new Array[String]) 

		var prop2 = stype.select_method(once "append".to_symbol)

		var prop3 = stype.select_method(once "to_s".to_symbol)
		for ne in n_exprs do
			var e = v.ensure_var(v.compile_expr(ne))
			if ne.stype != stype then
				v.add_assignment(e, prop3.compile_call(v, [e]))
			end
			prop2.compile_call(v, [recv, e])
		end

		return recv
	end
end

redef class ANullExpr
	redef meth compile_expr(v)
	do
		return " NIT_NULL /*null*/"
	end
end

redef class AArrayExpr
	redef meth compile_expr(v)
	do
		var prop = stype.select_method(once "with_capacity".to_symbol)
		var recv = prop.compile_constructor_call(v,["TAG_Int({n_exprs.length})"])

		var prop2 = stype.select_method(once "add".to_symbol)
		for ne in n_exprs do
			var e = v.compile_expr(ne)
			prop2.compile_call(v, [recv, e])
		end
		return recv
	end
end

redef class ARangeExpr
	redef meth compile_expr(v)
	do
		var prop = stype.select_method(propname)
		var e = v.compile_expr(n_expr)
		var e2 = v.compile_expr(n_expr2)
		return prop.compile_constructor_call(v, [e, e2])
	end
	# The constructor that must be used for the range
	protected meth propname: Symbol is abstract
end

redef class ACrangeExpr
	redef meth propname do return once "init".to_symbol
end
redef class AOrangeExpr
	redef meth propname do return once "without_last".to_symbol
end

redef class ASuperExpr
	redef meth compile_stmt(v)
	do
		var e = compile_expr(v)
		if e != null then v.add_instr("{e};")
	end

	redef meth compile_expr(v)
	do
		var arity = v.method_params.length - 1
		if init_in_superclass != null then
			arity = init_in_superclass.signature.arity
		end
		var args = new Array[String].with_capacity(arity + 1)
		args.add(v.method_params[0])
		if n_args.length != arity then
			for i in [0..arity[ do
				args.add(v.method_params[i + 1])
			end
		else
			for na in n_args do
				args.add(v.compile_expr(na))
			end
		end
		#return "{prop.cname}({args.join(", ")}) /*super {prop.local_class}::{prop.name}*/"
		if init_in_superclass != null then
			return init_in_superclass.compile_call(v, args)
		else
			if prop.global.is_init then args.add("init_table")
			return prop.compile_super_call(v, args)
		end
	end
end

redef class AAttrExpr
	redef meth compile_expr(v)
	do
		var e = v.compile_expr(n_expr)
		return prop.compile_access(v, e)
	end
end

redef class AAttrAssignExpr
	redef meth compile_stmt(v)
	do
		var e = v.compile_expr(n_expr)
		var e2 = v.compile_expr(n_value)
		v.add_assignment(prop.compile_access(v, e), e2)
	end
end
redef class AAttrReassignExpr
	redef meth compile_stmt(v)
	do
		var e1 = v.compile_expr(n_expr)
		var e2 = prop.compile_access(v, e1)
		var e3 = v.compile_expr(n_value)
		var e4 = assign_method.compile_call(v, [e2, e3])
		v.add_assignment(e2, e4)
	end
end

redef class ASendExpr
	redef meth compile_expr(v)
	do
		var recv = v.compile_expr(n_expr)
		var cargs = new Array[String]
		cargs.add(recv)
		for a in arguments do
			cargs.add(v.compile_expr(a))
		end

		var e = prop.compile_call(v, cargs)
		if prop.global.is_init then
			v.invoke_super_init_calls_after(prop)
		end
		return e
	end

	redef meth compile_stmt(v)
	do
		var e = compile_expr(v)
		if e != null then
			v.add_instr(e + ";")
		end
	end
end

redef class ASendReassignExpr
	redef meth compile_expr(v)
	do
		var recv = v.compile_expr(n_expr)
		var cargs = new Array[String]
		cargs.add(recv)
		for a in arguments do
			cargs.add(v.compile_expr(a))
		end

		var e2 = read_prop.compile_call(v, cargs)
		var e3 = v.compile_expr(n_value)
		var e4 = assign_method.compile_call(v, [e2, e3])
		cargs.add(e4)
		return prop.compile_call(v, cargs)
	end
end

redef class ANewExpr
	redef meth compile_expr(v)
	do
		var cargs = new Array[String]
		for a in arguments do
			cargs.add(v.compile_expr(a))
		end
		return prop.compile_constructor_call(v, cargs) 
	end
end

redef class AProxyExpr
	redef meth compile_expr(v)
	do
		return v.compile_expr(n_expr)
	end
end

redef class AOnceExpr
	redef meth compile_expr(v)
	do
		var i = v.new_number
		var cvar = v.get_var
		v.add_decl("static val_t once_value_{cvar}_{i}; static int once_bool_{cvar}_{i};")
		v.add_instr("if (once_bool_{cvar}_{i}) {cvar} = once_value_{cvar}_{i};")
		v.add_instr("else \{")
		v.indent
		v.free_var(cvar)
		var e = v.compile_expr(n_expr)
		v.add_assignment(cvar, e)
		v.add_instr("once_value_{cvar}_{i} = {cvar};")
		v.add_instr("once_bool_{cvar}_{i} = true;")
		v.unindent
		v.add_instr("}")
		return cvar
	end
end
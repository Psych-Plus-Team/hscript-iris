package crowplexus.iris.scripted;

import crowplexus.hscript.Expr;
import crowplexus.hscript.Interp;
import crowplexus.iris.scripted.ClassDeclEx;
import crowplexus.iris.scripted.InterpEx;

using StringTools;

enum Param
{
	Unused;
}

/**
 * Represents an instance of a scripted class.
 * Manages the interpretation and execution of script class methods and variables.
 * 
 * Based on polymod.hscript._internal.PolymodScriptClass
 */
@:access(crowplexus.hscript.Interp)
class ScriptClass
{
	// Instance variables
	private var _c:ClassDeclEx;
	private var _interp:InterpEx;
	
	public var superClass:Dynamic = null;
	public var className(get, null):String;
	
	private var _cachedFieldDecls:Map<String, FieldDecl> = null;
	private var _cachedFunctionDecls:Map<String, FunctionDecl> = null;
	private var _cachedVarDecls:Map<String, VarDecl> = null;
	private var __superClassFieldList:Array<String> = null;

	/**
	 * Creates a new script class instance.
	 * @param c The class declaration
	 * @param args Constructor arguments
	 */
	public function new(c:ClassDeclEx, args:Array<Dynamic>)
	{
		var targetClass:Class<Dynamic> = null;
		
		switch (c.extend)
		{
			case CTPath(pth, params):
				var clsPath = pth.join('.');
				var clsName = pth[pth.length - 1];

				if (ScriptClassManager.scriptClassOverrides.exists(clsPath))
				{
					targetClass = ScriptClassManager.scriptClassOverrides.get(clsPath);
				}
				else if (c.imports.exists(clsName))
				{
					var importedClass:ClassImport = c.imports.get(clsName);
					if (importedClass != null && importedClass.cls != null)
					{
						targetClass = importedClass.cls;
					}
					else if (importedClass != null && importedClass.cls == null)
					{
						trace('Could not determine target class for "${pth.join('.')}" (blacklisted type?)');
					}
					else
					{
						trace('Could not determine target class for "${pth.join('.')}" (unregistered type?)');
					}
				}
				else
				{
					trace('Could not determine target class for "${pth.join('.')}" (unregistered type?)');
				}
			default:
				trace('Could not determine target class for "${c.extend}" (unknown type?)');
		}
		
		_interp = new InterpEx(targetClass, this);
		_c = c;
		buildCaches();

		var ctorField = findField("new");
		if (ctorField != null)
		{
			callFunction("new", args);
			if (superClass == null && _c.extend != null)
			{
				throw new Error(ECustom("Super constructor not called"), 0, 0, "ScriptClass", 0);
			}
		}
		else if (_c.extend != null)
		{
			createSuperClass(args);
		}
	}

	private function get_className():String
	{
		var name = "";
		if (_c.pkg != null)
		{
			name += _c.pkg.join(".");
		}
		name += _c.name;
		return name;
	}

	public function superHasField(name:String):Bool
	{
		if (superClass == null)
			return false;
			
		// Cache field list for performance
		if (__superClassFieldList == null)
		{
			__superClassFieldList = Reflect.fields(superClass).concat(Type.getInstanceFields(Type.getClass(superClass)));
		}
		return __superClassFieldList.indexOf(name) != -1;
	}

	private function createSuperClass(args:Array<Dynamic> = null)
	{
		if (args == null)
		{
			args = [];
		}

		var fullExtendString = new crowplexus.hscript.Printer().typeToString(_c.extend);

		// Remove template parameters
		if (fullExtendString.indexOf('<') != -1)
		{
			fullExtendString = fullExtendString.split('<')[0];
		}

		var fullExtendStringParts = fullExtendString.split('.');
		var extendString = fullExtendStringParts[fullExtendStringParts.length - 1];

		var classDescriptor = InterpEx.findScriptClassDescriptor(extendString);
		if (classDescriptor != null)
		{
			var abstractSuperClass:AbstractScriptClass = new ScriptClass(classDescriptor, args);
			superClass = abstractSuperClass;
		}
		else
		{
			var clsToCreate:Class<Dynamic> = null;

			if (ScriptClassManager.scriptClassOverrides.exists(fullExtendString))
			{
				clsToCreate = ScriptClassManager.scriptClassOverrides.get(fullExtendString);

				if (clsToCreate == null)
				{
					throw new Error(ECustom('Cannot create superclass: ${fullExtendString}'), 0, 0, "ScriptClass", 0);
				}
			}
			else if (_c.imports.exists(extendString))
			{
				clsToCreate = _c.imports.get(extendString).cls;

				if (clsToCreate == null)
				{
					throw new Error(ECustom('Cannot create superclass: ${extendString} (blacklisted)'), 0, 0, "ScriptClass", 0);
				}
			}
			else
			{
				throw new Error(ECustom('Cannot create superclass: ${extendString} (missing import)'), 0, 0, "ScriptClass", 0);
			}

			superClass = Type.createInstance(clsToCreate, args);
		}
	}

	private function superConstructor(arg0:Dynamic = Unused, arg1:Dynamic = Unused, arg2:Dynamic = Unused, arg3:Dynamic = Unused)
	{
		var args = [];
		if (arg0 != Unused)
			args.push(arg0);
		if (arg1 != Unused)
			args.push(arg1);
		if (arg2 != Unused)
			args.push(arg2);
		if (arg3 != Unused)
			args.push(arg3);
		createSuperClass(args);
	}

	@:privateAccess(crowplexus.hscript.Interp)
	public function callFunction(fnName:String, args:Array<Dynamic> = null):Dynamic
	{
		var field = findField(fnName);
		var r:Dynamic = null;
		var fn = (field != null) ? findFunction(fnName, true) : null;

		if (fn != null)
		{
			// Store previous values to restore after function call
			var previousValues:Map<String, Dynamic> = [];
			var i = 0;
			
			for (a in fn.args)
			{
				var value:Dynamic = null;

				if (args != null && i < args.length)
				{
					value = args[i];
				}
				else if (a.value != null)
				{
					value = _interp.expr(a.value);
				}

				if (_interp.variables.exists(a.name))
				{
					previousValues.set(a.name, _interp.variables.get(a.name));
				}
				_interp.variables.set(a.name, value);
				i++;
			}

			try
			{
				r = _interp.expr(fn.expr);
			}
			catch (err:Error)
			{
				trace('Error while executing function ${className}.${fnName}(): ${err}');
				purgeFunction(fnName);
				return null;
			}

			// Restore previous values
			for (a in fn.args)
			{
				if (previousValues.exists(a.name))
				{
					_interp.variables.set(a.name, previousValues.get(a.name));
				}
				else
				{
					_interp.variables.remove(a.name);
				}
			}
		}
		else
		{
			// Call superclass function
			var fixedArgs = [];
			var fixedName = '__super_${fnName}';
			
			for (a in args)
			{
				if (Std.isOfType(a, ScriptClass))
				{
					fixedArgs.push(cast(a, ScriptClass).superClass);
				}
				else
				{
					fixedArgs.push(a);
				}
			}
			
			var fn = Reflect.field(superClass, fixedName);
			if (fn == null)
			{
				trace('Error: Super function "${fnName}" does not exist!');
				return null;
			}
			r = Reflect.callMethod(superClass, fn, fixedArgs);
		}
		return r;
	}

	public function hasFunction(name:String):Bool
	{
		return findFunction(name, false) != null;
	}

	private inline function callFunction0(name:String):Dynamic
	{
		return callFunction(name);
	}

	private inline function callFunction1(name:String, arg0:Dynamic):Dynamic
	{
		return callFunction(name, [arg0]);
	}

	private inline function callFunction2(name:String, arg0:Dynamic, arg1:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1]);
	}

	private inline function callFunction3(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2]);
	}

	private inline function callFunction4(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3]);
	}

	private inline function callFunction5(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4]);
	}

	private inline function callFunction6(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic, arg5:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4, arg5]);
	}

	private inline function callFunction7(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic, arg5:Dynamic,
			arg6:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4, arg5, arg6]);
	}

	private inline function callFunction8(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic, arg5:Dynamic, arg6:Dynamic,
			arg7:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7]);
	}

	private function findFunction(name:String, cacheOnly:Bool = true):Null<FunctionDecl>
	{
		if (_cachedFunctionDecls != null)
		{
			return _cachedFunctionDecls.get(name);
		}
		if (cacheOnly) return null;

		for (f in _c.fields)
		{
			if (f.name == name)
			{
				switch (f.kind)
				{
					case KFunction(fn):
						return fn;
					case _:
				}
			}
		}

		return null;
	}

	private function purgeFunction(name:String):Void
	{
		if (_cachedFunctionDecls != null)
		{
			_cachedFunctionDecls.remove(name);
		}
	}

	public function findVar(name:String, cacheOnly:Bool = false):Null<VarDecl>
	{
		if (_cachedVarDecls != null)
		{
			return _cachedVarDecls.get(name);
		}
		if (cacheOnly) return null;

		for (f in _c.fields)
		{
			if (f.name == name)
			{
				switch (f.kind)
				{
					case KVar(v):
						return v;
					case _:
				}
			}
		}

		return null;
	}

	private function findField(name:String, cacheOnly:Bool = true):Null<FieldDecl>
	{
		if (_cachedFieldDecls != null)
		{
			return _cachedFieldDecls.get(name);
		}
		if (cacheOnly) return null;

		for (f in _c.fields)
		{
			if (f.name == name)
			{
				return f;
			}
		}
		return null;
	}

	public function listFunctions():Map<String, FunctionDecl>
	{
		return _cachedFunctionDecls;
	}

	private function buildCaches()
	{
		_cachedFieldDecls = [];
		_cachedFunctionDecls = [];
		_cachedVarDecls = [];

		for (f in _c.fields)
		{
			_cachedFieldDecls.set(f.name, f);
			switch (f.kind)
			{
				case KFunction(fn):
					_cachedFunctionDecls.set(f.name, fn);
				case KVar(v):
					_cachedVarDecls.set(f.name, v);
					if (v.expr != null)
					{
						var varValue = this._interp.expr(v.expr);
						this._interp.variables.set(f.name, varValue);
					}
				default:
					throw 'Unknown field kind: ${f.kind}';
			}
		}
	}
}

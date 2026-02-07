package crowplexus.iris.scripted;

import crowplexus.hscript.Expr;
import crowplexus.hscript.Interp;
import crowplexus.iris.scripted.ClassDeclEx;
import crowplexus.iris.scripted.AbstractScriptClass;
import crowplexus.iris.scripted.ScriptClass;
import crowplexus.iris.scripted.HScriptedClass;

/**
 * Extended interpreter for handling scripted classes.
 * 
 * Based on polymod.hscript._internal.PolymodInterpEx
 */
@:access(crowplexus.iris.scripted.ScriptClass)
@:access(crowplexus.iris.scripted.AbstractScriptClass)
class InterpEx extends Interp
{
	var targetCls:Class<Dynamic>;
	private var _proxy:AbstractScriptClass = null;

	public static var _scriptClassDescriptors:Map<String, ClassDeclEx> = new Map<String, ClassDeclEx>();

	public function new(targetCls:Class<Dynamic>, proxy:AbstractScriptClass)
	{
		super();
		_proxy = proxy;
		variables.set("Math", Math);
		variables.set("Std", Std);
		this.targetCls = targetCls;
	}

	public static function registerScriptClass(c:ClassDeclEx)
	{
		var name = c.name;
		if (c.pkg != null)
		{
			name = c.pkg.join(".") + "." + name;
		}
		_scriptClassDescriptors.set(name, c);
	}

	public static function findScriptClassDescriptor(name:String)
	{
		return _scriptClassDescriptors.get(name);
	}

	override function cnew(cl:String, args:Array<Dynamic>):Dynamic
	{
		if (_scriptClassDescriptors.exists(cl))
		{
			var proxy:AbstractScriptClass = new ScriptClass(_scriptClassDescriptors.get(cl), args);
			return proxy;
		}
		else if (_proxy != null)
		{
			@:privateAccess
			if (_proxy._c.pkg != null)
			{
				@:privateAccess
				var packagedClass = _proxy._c.pkg.join(".") + "." + cl;
				if (_scriptClassDescriptors.exists(packagedClass))
				{
					var proxy:AbstractScriptClass = new ScriptClass(_scriptClassDescriptors.get(packagedClass), args);
					return proxy;
				}
			}

			@:privateAccess
			if (_proxy._c.imports != null && _proxy._c.imports.exists(cl))
			{
				var importedClass:ClassImport = _proxy._c.imports.get(cl);
				if (_scriptClassDescriptors.exists(importedClass.fullPath))
				{
					var proxy:AbstractScriptClass = new ScriptClass(_scriptClassDescriptors.get(importedClass.fullPath), args);
					return proxy;
				}

				var c = importedClass.cls;
				if (c == null)
				{
					error(ECustom('Cannot instantiate blacklisted class: ${importedClass.fullPath}'));
				}
				else
				{
					return Type.createInstance(c, args);
				}
			}
		}

		// Fallback to regular class resolution
		var cls = Type.resolveClass(cl);
		if (cls == null)
			cls = resolve(cl);
		if (cls == null)
			error(ECustom('Cannot find class: ${cl}'));
		return Type.createInstance(cls, args);
	}

	override function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic
	{
		// Handle super calls to prevent infinite recursion
		if (_proxy != null && o == _proxy.superClass)
		{
			return super.fcall(o, '__super_${f}', args);
		}
		else if (Std.isOfType(o, ScriptClass))
		{
			var proxy:ScriptClass = cast(o, ScriptClass);
			return proxy.callFunction(f, args);
		}

		var func = get(o, f);

		// HTML5 workaround for contains/includes
		if (func == null && f == "contains")
		{
			func = get(o, "includes");
		}

		if (func == null)
		{
			if (Std.isOfType(o, HScriptedClass))
			{
				error(ECustom('Cannot call scripted function "${f}" directly. Use scriptCall() instead.'));
			}
			else
			{
				error(EInvalidAccess(f));
			}
		}
		return call(o, func, args);
	}

	override function setVar(id:String, v:Dynamic)
	{
		if (_proxy != null && _proxy.superClass != null)
		{
			if (_proxy.superHasField(id))
			{
				Reflect.setProperty(_proxy.superClass, id, v);
				return;
			}
		}

		super.setVar(id, v);
	}

	override function assign(e1:Expr, e2:Expr):Dynamic
	{
		switch (Tools.expr(e1))
		{
			case EIdent(id):
				if (_proxy != null && _proxy.superClass != null)
				{
					if (_proxy.superHasField(id))
					{
						var v = expr(e2);
						Reflect.setProperty(_proxy.superClass, id, v);
						return v;
					}
				}
			case EField(e0, id, s):
				switch (Tools.expr(e0))
				{
					case EIdent(id0):
						if (id0 == "this")
						{
							if (_proxy != null && _proxy.superClass != null)
							{
								if (_proxy.superHasField(id))
								{
									var v = expr(e2);
									Reflect.setProperty(_proxy.superClass, id, v);
									return v;
								}
							}
						}
					default:
				}
			default:
		}
		return super.assign(e1, e2);
	}
}

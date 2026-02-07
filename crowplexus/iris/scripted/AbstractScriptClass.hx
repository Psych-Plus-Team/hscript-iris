package crowplexus.iris.scripted;

import crowplexus.hscript.Expr;
import crowplexus.hscript.Interp;
import crowplexus.iris.scripted.ScriptClass;

/**
 * Represents an instance of a scripted class at runtime.
 * 
 * Based on polymod.hscript._internal.PolymodAbstractScriptClass
 */
@:forward
@:access(crowplexus.iris.scripted.ScriptClass)
abstract AbstractScriptClass(ScriptClass) from ScriptClass
{
	/**
	 * Read a field value from the scripted class instance.
	 */
	@:op(a.b) public function fieldRead(name:String):Dynamic
	{
		return resolveField(name);
	}

	/**
	 * Write a value to a field in the scripted class instance.
	 */
	@:op(a.b) public function fieldWrite(name:String, value:Dynamic):Dynamic
	{
		switch (name)
		{
			case _:
				if (this.findVar(name) != null)
				{
					this._interp.variables.set(name, value);
					return value;
				}
				else if (Reflect.hasField(this.superClass, name))
				{
					Reflect.setProperty(this.superClass, name, value);
					return value;
				}
				else if (this.superClass != null && Std.isOfType(this.superClass, ScriptClass))
				{
					var superScriptClass:AbstractScriptClass = cast(this.superClass, ScriptClass);
					try
					{
						return superScriptClass.fieldWrite(name, value);
					}
					catch (e:Dynamic)
					{
					}
				}
		}

		if (this.superClass == null)
		{
			throw "field '" + name + "' does not exist in script class '" + this.className + "'";
		}
		else
		{
			var superClassName = Type.getClass(this.superClass) != null ? Type.getClassName(Type.getClass(this.superClass)) : "Unknown";
			throw "field '" + name + "' does not exist in script class '" + this.className + "' or super class '" + superClassName + "'";
		}
	}

	private function resolveField(name:String):Dynamic
	{
		switch (name)
		{
			case "superClass":
				return this.superClass;
			case "findFunction":
				return this.findFunction;
			case "callFunction":
				return this.callFunction;
			case "hasFunction":
				return this.hasFunction;
			case _:
				// Check if it's a function
				if (this.findFunction(name) != null)
				{
					var fn = this.findFunction(name);
					var nargs = 0;
					if (fn.args != null)
					{
						nargs = fn.args.length;
					}
					
					// Return bound function based on argument count
					switch (nargs)
					{
						case 0: return this.callFunction0.bind(name);
						case 1: return this.callFunction1.bind(name, _);
						case 2: return this.callFunction2.bind(name, _, _);
						case 3: return this.callFunction3.bind(name, _, _, _);
						case 4: return this.callFunction4.bind(name, _, _, _, _);
						case 5: return this.callFunction5.bind(name, _, _, _, _, _);
						case 6: return this.callFunction6.bind(name, _, _, _, _, _, _);
						case 7: return this.callFunction7.bind(name, _, _, _, _, _, _, _);
						case 8: return this.callFunction8.bind(name, _, _, _, _, _, _, _, _);
						case _: throw "Too many params in script class function (max 8): " + name;
					}
				}
				// Check if it's a variable
				else if (this.findVar(name) != null)
				{
					var v = this.findVar(name);
					var varValue:Dynamic = null;
					
					if (this._interp.variables.exists(name) == false)
					{
						if (v.expr != null)
						{
							varValue = this._interp.expr(v.expr);
							this._interp.variables.set(name, varValue);
						}
					}
					else
					{
						varValue = this._interp.variables.get(name);
					}
					return varValue;
				}
				// Check superclass
				else if (this.superClass == null)
				{
					throw "field '" + name + "' does not exist in script class '" + this.className + "'";
				}
				else if (Type.getClass(this.superClass) == null)
				{
					// Anonymous structure
					if (Reflect.hasField(this.superClass, name))
					{
						return Reflect.field(this.superClass, name);
					}
					else
					{
						throw "field '" + name + "' does not exist in script class '" + this.className + "' or super class";
					}
				}
				else if (Std.isOfType(this.superClass, ScriptClass))
				{
					// Another ScriptClass
					var superScriptClass:AbstractScriptClass = cast(this.superClass, ScriptClass);
					try
					{
						return superScriptClass.fieldRead(name);
					}
					catch (e:Dynamic)
					{
					}
				}
				else
				{
					// Regular class object
					var fields = Type.getInstanceFields(Type.getClass(this.superClass));
					if (fields.contains(name) || fields.contains('get_$name'))
					{
						return Reflect.getProperty(this.superClass, name);
					}
					else
					{
						var superClassName = Type.getClassName(Type.getClass(this.superClass));
						throw "field '" + name + "' does not exist in script class '" + this.className + "' or super class '" + superClassName + "'";
					}
				}
		}

		if (this.superClass == null)
		{
			throw "field '" + name + "' does not exist in script class '" + this.className + "'";
		}
		else
		{
			var superClassName = Type.getClass(this.superClass) != null ? Type.getClassName(Type.getClass(this.superClass)) : "Unknown";
			throw "field '" + name + "' does not exist in script class '" + this.className + "' or super class '" + superClassName + "'";
		}
	}
}

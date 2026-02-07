package crowplexus.iris.scripted;

import crowplexus.hscript.Parser;
import crowplexus.hscript.Printer;
import crowplexus.hscript.Expr;
import crowplexus.iris.scripted.ClassDeclEx;
import crowplexus.iris.scripted.AbstractScriptClass;
import crowplexus.iris.scripted.ScriptClass;
import crowplexus.iris.scripted.InterpEx;

using StringTools;

/**
 * Manages registration, parsing, and instantiation of scripted classes.
 * 
 * Based on polymod.hscript._internal.PolymodScriptClass
 */
class ScriptClassManager
{
	private static final scriptInterp = new InterpEx(null, null);

	/**
	 * Define a list of script classes to override the default behavior.
	 * For example, script classes should import `ScriptedSprite` instead of `Sprite`.
	 */
	public static final scriptClassOverrides:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

	/**
	 * Provide a class name along with a corresponding class to override imports.
	 * You can set the value to `null` to prevent the class from being imported.
	 */
	public static final importOverrides:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

	/**
	 * Provide a class name along with a corresponding class to import it in every scripted class.
	 */
	public static final defaultImports:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

	/**
	 * Register a scripted class by parsing the text of that script.
	 */
	public static function registerScriptClassByString(body:String, path:String = null):Void
	{
		var parser = new Parser();
		parser.allowTypes = true;
		parser.allowJSON = false;
		parser.allowMetadata = true;
		
		try
		{
			var ast = parser.parseString(body, path != null ? path : 'hscriptClass');
			parseClassDecl(ast, path);
		}
		catch (err:Error)
		{
			trace('Error while parsing scripted class "${path}": ${err}');
		}
	}

	/**
	 * Register a scripted class by retrieving the script from the given path.
	 */
	public static function registerScriptClassByPath(path:String):Void
	{
		#if sys
		try
		{
			var scriptBody = sys.io.File.getContent(path);
			if (scriptBody == null)
			{
				trace('Error while loading script "${path}", could not retrieve script contents!');
				return;
			}
			registerScriptClassByString(scriptBody, path);
		}
		catch (err:Dynamic)
		{
			trace('Error while loading script "${path}": ${err}');
		}
		#else
		trace('Error: registerScriptClassByPath not available on this platform');
		#end
	}

	private static function parseClassDecl(e:Expr, path:String):Void
	{
		switch (e)
		{
			case EBlock(exprs):
				for (expr in exprs)
				{
					parseClassDecl(expr, path);
				}
			case EClass(c):
				var classDecl:ClassDeclEx = cast c;
				
				// Process imports
				classDecl.imports = new Map<String, ClassImport>();
				
				// Add default imports
				for (key => value in defaultImports)
				{
					var pkg = key.split('.');
					var name = pkg.pop();
					classDecl.imports.set(name, {
						name: name,
						pkg: pkg,
						fullPath: key,
						cls: value,
						enm: null
					});
				}
				
				InterpEx.registerScriptClass(classDecl);
				trace('Registered scripted class: ${classDecl.name}');
			case EPackage(path, e2):
				// Parse package declaration
				var pkg = path.split('.');
				parseClassDecl(e2, path);
			case EImport(path, everything):
				// Imports are handled at class level
			default:
				// Ignore other expressions
		}
	}

	/**
	 * Returns a list of all registered classes.
	 */
	public static function listScriptClasses():Array<String>
	{
		var result = [];
		@:privateAccess
		for (key => _value in InterpEx._scriptClassDescriptors)
		{
			result.push(key);
		}
		return result;
	}

	/**
	 * Returns a list of all registered classes which extend the class specified by the given name.
	 */
	public static function listScriptClassesExtending(clsPath:String):Array<String>
	{
		var result = [];
		@:privateAccess
		for (key => value in InterpEx._scriptClassDescriptors)
		{
			var superClasses = getSuperClasses(value);
			if (superClasses.indexOf(clsPath) != -1)
			{
				result.push(key);
			}
		}
		return result;
	}

	/**
	 * Returns a list of all registered classes which extend the specified class.
	 */
	public static function listScriptClassesExtendingClass(cls:Class<Dynamic>):Array<String>
	{
		return listScriptClassesExtending(Type.getClassName(cls));
	}

	static function getSuperClasses(classDecl:ClassDeclEx):Array<String>
	{
		if (classDecl.extend == null)
		{
			return [];
		}

		var extendString = (new Printer()).typeToString(classDecl.extend);
		if (classDecl.pkg != null && extendString.indexOf('.') == -1)
		{
			var extendPkg = classDecl.pkg.join('.');
			extendString = '$extendPkg.$extendString';
		}

		// Check if the superclass is a scripted class
		var classDescriptor:ClassDeclEx = InterpEx.findScriptClassDescriptor(extendString);

		if (classDescriptor != null)
		{
			var result = [extendString];
			return result.concat(getSuperClasses(classDescriptor));
		}
		else
		{
			// Remove templates
			if (extendString.indexOf('<') != -1)
			{
				extendString = extendString.split('<')[0];
			}

			var superCls:Class<Dynamic> = null;

			if (classDecl.imports.exists(extendString))
			{
				var importedClass:ClassImport = classDecl.imports.get(extendString);
				if (importedClass != null && importedClass.cls != null)
				{
					superCls = importedClass.cls;
				}
			}

			if (superCls == null)
			{
				superCls = Type.resolveClass(extendString);
			}

			if (superCls != null)
			{
				var result = [];
				while (superCls != null)
				{
					result.push(Type.getClassName(superCls));
					superCls = Type.getSuperClass(superCls);
				}
				return result;
			}
			else
			{
				var clsName = classDecl.pkg != null ? '${classDecl.pkg.join('.')}.${classDecl.name}' : classDecl.name;
				trace('Could not parse superclass "$extendString" of scripted class "${clsName}"');
				return [];
			}
		}
	}

	public static function createScriptClassInstance(name:String, args:Array<Dynamic> = null):AbstractScriptClass
	{
		var classDescriptor = InterpEx.findScriptClassDescriptor(name);
		if (classDescriptor == null)
		{
			trace('Error: Scripted class not found: ${name}');
			return null;
		}

		if (args == null)
			args = [];

		try
		{
			var scriptClass = new ScriptClass(classDescriptor, args);
			return cast scriptClass;
		}
		catch (err:Dynamic)
		{
			trace('Error creating scripted class instance "${name}": ${err}');
			return null;
		}
	}
}

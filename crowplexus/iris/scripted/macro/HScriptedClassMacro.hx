package crowplexus.iris.scripted.macro;

import haxe.macro.Context;
import haxe.macro.Expr;

using Lambda;
using haxe.macro.ComplexTypeTools;
using haxe.macro.ExprTools;
using haxe.macro.TypeTools;

/**
 * Macro for building scripted classes.
 * 
 * Based on polymod.hscript._internal.HScriptedClassMacro
 */
class HScriptedClassMacro
{
	public static macro function build():Array<Field>
	{
		var cls:haxe.macro.Type.ClassType = Context.getLocalClass().get();
		var initialFields:Array<Field> = Context.getBuildFields();
		var fields:Array<Field> = [].concat(initialFields);

		// Check if already processed
		var alreadyProcessed = cls.meta.get().find(function(m) return m.name == ':hscriptClassPreProcessed');

		if (alreadyProcessed == null)
		{
			var superCls:haxe.macro.Type.ClassType = cls.superClass.t.get();

			// Build script utility functions
			var newFields:Array<Field> = buildScriptedClassUtils(cls, superCls);
			fields = fields.concat(newFields);

			// Build main class functionality
			fields = buildHScriptClass(cls, fields);

			cls.meta.add(":hscriptClassPreProcessed", [], cls.pos);
			return fields;
		}

		return null;
	}

	static function buildScriptedClassUtils(cls:haxe.macro.Type.ClassType, superCls:haxe.macro.Type.ClassType):Array<Field>
	{
		var clsTypeName:String = cls.pack.join('.') != '' ? '${cls.pack.join('.')}.${cls.name}' : cls.name;
		var superClsTypeName:String = superCls.pack.join('.') != '' ? '${superCls.pack.join('.')}.${superCls.name}' : superCls.name;

		var function_scriptGet:Field = {
			name: 'scriptGet',
			doc: 'Retrieves the value of a local variable of a scripted class.',
			access: [APublic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [{name: 'varName', type: Context.toComplexType(Context.getType('String'))}],
				params: null,
				ret: Context.toComplexType(Context.getType('Dynamic')),
				expr: macro
				{
					return _asc.fieldRead(varName);
				},
			}),
		}

		var function_scriptSet:Field = {
			name: 'scriptSet',
			doc: 'Directly modifies the value of a local variable of a scripted class.',
			access: [APublic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [
					{name: 'varName', type: Context.toComplexType(Context.getType('String'))},
					{
						name: 'varValue',
						type: Context.toComplexType(Context.getType('Dynamic')),
						value: macro null,
					}
				],
				params: null,
				ret: Context.toComplexType(Context.getType('Dynamic')),
				expr: macro
				{
					return _asc.fieldWrite(varName, varValue);
				},
			}),
		}

		var function_scriptCall:Field = {
			name: 'scriptCall',
			doc: 'Calls a function of the scripted class with the given name and arguments.',
			access: [APublic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [
					{name: 'funcName', type: Context.toComplexType(Context.getType('String'))},
					{
						name: 'funcArgs',
						type: toComplexTypeArray(Context.toComplexType(Context.getType('Dynamic'))),
						value: macro null,
					}
				],
				params: null,
				ret: Context.toComplexType(Context.getType('Dynamic')),
				expr: macro
				{
					return _asc.callFunction(funcName, funcArgs == null ? [] : funcArgs);
				},
			}),
		};

		var var__asc:Field = {
			name: '_asc',
			doc: "The AbstractScriptClass instance which any variable or function calls are redirected to internally.",
			access: [APrivate],
			kind: FVar(Context.toComplexType(Context.getType('crowplexus.iris.scripted.AbstractScriptClass'))),
			pos: cls.pos,
		};

		var function_listScriptClasses:Field = {
			name: 'listScriptClasses',
			doc: "Returns a list of all the scripted classes which extend this class.",
			access: [APublic, AStatic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [],
				params: null,
				ret: toComplexTypeArray(Context.toComplexType(Context.getType('String'))),
				expr: macro
				{
					return crowplexus.iris.scripted.ScriptClassManager.listScriptClassesExtending($v{superClsTypeName});
				},
			}),
		};

		return [function_scriptGet, function_scriptSet, function_scriptCall, var__asc, function_listScriptClasses];
	}

	static function buildHScriptClass(cls:haxe.macro.Type.ClassType, fields:Array<Field>):Array<Field>
	{
		var script_class_meta = cls.meta.get().find(function(m) return m.name == ':hscriptClass');
		if (script_class_meta != null)
		{
			var superCls:haxe.macro.Type.ClassType = cls.superClass.t.get();

			var constructor = fields.find(function(field) return field.name == 'new');

			if (constructor != null)
			{
				Context.error("Error: Constructor already defined for this class", Context.currentPos());
			}
			else
			{
				if (superCls.constructor != null)
				{
					var superClsConstType:haxe.macro.Type = superCls.constructor.get().type;
					switch (superClsConstType)
					{
						case TFun(args, ret):
							var constArgs = [
								for (arg in args)
									{name: arg.name, opt: arg.opt, type: Context.toComplexType(arg.t)}
							];
							var initField:Field = buildScriptedClassInit(cls, superCls, constArgs);
							fields.push(initField);
							constructor = buildScriptedClassConstructor(constArgs);
						case TLazy(builder):
							var builtValue = builder();
							switch (builtValue)
							{
								case TFun(args, ret):
									var constArgs = [
										for (arg in args)
											{name: arg.name, opt: arg.opt, type: Context.toComplexType(arg.t)}
									];
									var initField:Field = buildScriptedClassInit(cls, superCls, constArgs);
									fields.push(initField);
									constructor = buildScriptedClassConstructor(constArgs);
								default:
									Context.error('Error: Lazy superclass constructor is not a function (got ${builtValue})', Context.currentPos());
							}
						default:
							Context.error('Error: super constructor is not a function (got ${superClsConstType})', Context.currentPos());
					}
				}
				else
				{
					constructor = buildEmptyScriptedClassConstructor();
					var initField:Field = buildScriptedClassInit(cls, superCls, []);
					fields.push(initField);
					fields.push(constructor);
				}
			}

			fields = fields.concat(buildScriptedClassFieldOverrides(cls));
		}

		return fields;
	}

	static function buildScriptedClassInit(cls:haxe.macro.Type.ClassType, superCls:haxe.macro.Type.ClassType, superConstArgs:Array<FunctionArg>):Field
	{
		var clsTypeName:String = cls.pack.join('.') != '' ? '${cls.pack.join('.')}.${cls.name}' : cls.name;
		var superClsTypeName:String = superCls.pack.join('.') != '' ? '${superCls.pack.join('.')}.${superCls.name}' : superCls.name;

		var constArgs = [for (arg in superConstArgs) macro $i{arg.name}];
		var typePath:haxe.macro.TypePath = {
			pack: cls.pack,
			name: cls.name,
		};

		var function_init:Field = {
			name: 'init',
			doc: "Initializes a scripted class instance using the given scripted class name and constructor arguments.",
			access: [APublic, AStatic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [{name: 'clsName', type: Context.toComplexType(Context.getType('String'))},].concat(superConstArgs),
				params: null,
				ret: Context.toComplexType(Context.getType(clsTypeName)),
				expr: macro
				{
					crowplexus.iris.scripted.ScriptClassManager.scriptClassOverrides.set($v{superClsTypeName}, Type.resolveClass($v{clsTypeName}));

					var asc:crowplexus.iris.scripted.AbstractScriptClass = crowplexus.iris.scripted.ScriptClassManager.createScriptClassInstance(clsName, $a{constArgs});
					if (asc == null)
					{
						trace('Could not construct instance of scripted class (${clsName} extends ' + $v{clsTypeName} + ')');
						return null;
					}
					var scriptedObj = asc.superClass;

					Reflect.setField(scriptedObj, '_asc', asc);

					return scriptedObj;
				},
			}),
		};

		return function_init;
	}

	static function buildScriptedClassConstructor(superConstArgs:Array<FunctionArg>):Field
	{
		var constArgs = [for (arg in superConstArgs) macro $i{arg.name}];
		
		return {
			name: 'new',
			doc: 'Constructor for scripted class. Do not call directly, use init() instead.',
			access: [APrivate],
			pos: Context.currentPos(),
			kind: FFun({
				args: superConstArgs,
				ret: null,
				expr: macro
				{
					super($a{constArgs});
				},
			}),
		};
	}

	static function buildEmptyScriptedClassConstructor():Field
	{
		return {
			name: 'new',
			doc: 'Empty constructor for scripted class. Do not call directly, use init() instead.',
			access: [APrivate],
			pos: Context.currentPos(),
			kind: FFun({
				args: [],
				ret: null,
				expr: macro
				{
					super();
				},
			}),
		};
	}

	static function buildScriptedClassFieldOverrides(cls:haxe.macro.Type.ClassType):Array<Field>
	{
		var fields:Array<Field> = [];
		var superCls:haxe.macro.Type.ClassType = cls.superClass.t.get();
		
		// Get all fields from superclass that can be overridden
		var superFields = superCls.fields.get();
		
		for (field in superFields)
		{
			// Skip non-public fields, static fields, and constructors
			if (!field.isPublic || field.meta.has(':final') || field.name == 'new')
				continue;

			switch (field.kind)
			{
				case FMethod(k):
					// Only override methods
					if (k == MethInline || field.meta.has(':generic'))
						continue;
					
					var overrideField = buildMethodOverride(cls, field);
					if (overrideField != null)
						fields.push(overrideField);
				default:
					// Skip non-method fields
			}
		}

		return fields;
	}

	static function buildMethodOverride(cls:haxe.macro.Type.ClassType, field:haxe.macro.Type.ClassField):Field
	{
		var fieldName = field.name;
		
		// Get the function type
		var fieldType = field.type;
		
		switch (fieldType)
		{
			case TFun(args, ret):
				var functionArgs:Array<FunctionArg> = [];
				var callArgs:Array<Expr> = [];
				
				for (arg in args)
				{
					var complexType = try Context.toComplexType(arg.t) catch(e:Dynamic) null;
					if (complexType == null) return null; // Skip if cannot convert type
					
					functionArgs.push({
						name: arg.name,
						type: complexType,
						opt: arg.opt
					});
					callArgs.push(macro $i{arg.name});
				}
				
				var retType = try Context.toComplexType(ret) catch(e:Dynamic) null;
				
				return {
					name: fieldName,
					access: [APublic, AOverride],
					pos: cls.pos,
					kind: FFun({
						args: functionArgs,
						ret: retType,
						expr: macro
						{
							if (_asc != null && _asc.hasFunction($v{fieldName}))
							{
								return _asc.callFunction($v{fieldName}, $a{callArgs});
							}
							else
							{
								return super.$fieldName($a{callArgs});
							}
						},
					}),
				};
			default:
				return null;
		}
	}

	static function toComplexTypeArray(ct:ComplexType):ComplexType
	{
		return TPath({pack: [], name: 'Array', params: [TPType(ct)]});
	}
}

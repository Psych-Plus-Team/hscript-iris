package crowplexus.iris.scripted;

import crowplexus.hscript.Expr.ClassDecl;

/**
 * Extended class declaration with additional metadata for scripted classes.
 */
typedef ClassDeclEx =
{
	> ClassDecl,
	
	/**
	 * Package path of the class
	 */
	@:optional var pkg:Array<String>;
	
	/**
	 * Imports resolved at interpretation time for performance and sandboxing
	 */
	@:optional var imports:Map<String, ClassImport>;
}

/**
 * Represents an imported class or enum
 */
typedef ClassImport = {
	@:optional var name:String;
	@:optional var pkg:Array<String>;
	@:optional var fullPath:String; // pkg.pkg.pkg.name
	@:optional var cls:Class<Dynamic>;
	@:optional var enm:Enum<Dynamic>;
}

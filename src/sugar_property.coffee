# @property "prop", { desc... }
Function::property = (prop, desc) ->
	Object.defineProperty @prototype, prop, desc

# defineProperty "prop", { desc... }
#Object::defineProperty = (prop, desc) -> Object.defineProperty @, prop, desc

# propertiesof obj
#global.propertiesof = (obj) ->
#  Object.getOwnPropertyNames(obj).concat(
#    Object.getOwnPropertyNames(obj.constructor.prototype or {}))

# descriptorof obj, name
#global.descriptorof = (obj, name) -> Object.getOwnPropertyDescriptor obj, name

module.exports = exports = {}

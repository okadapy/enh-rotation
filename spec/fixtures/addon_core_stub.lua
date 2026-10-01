-- stands in for addon/core.lua in spec/build_spec.lua: records what the build passes to boot
return { boot = function(o) BOOTED = o end }

-- Loads Roblox-style ModuleScripts under Lune by faking `script` as a path object,
-- so shared modules keep `require(script.Parent.Config.Eggs)` and still run headless.
-- Only pure modules (no game/workspace/Enum) can be loaded this way.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local harness = {}

local cache: { [string]: any } = {}
local PATH = newproxy(true)

local function dirname(path: string): string
	return path:match("^(.*)/[^/]+$") or "."
end

local makeScript

local function resolve(path: string): (string?, boolean)
	for _, ext in { ".luau", ".lua" } do
		if fs.isFile(path .. ext) then
			return path .. ext, false
		end
	end
	for _, name in { "/init.luau", "/init.lua" } do
		if fs.isFile(path .. name) then
			return path .. name, true
		end
	end
	return nil, false
end

function makeScript(path: string)
	return setmetatable({ [PATH] = path }, {
		__index = function(self, key)
			if key == "Parent" then
				return makeScript(dirname(path))
			elseif key == "Name" then
				return path:match("[^/]+$")
			end
			return makeScript(path .. "/" .. key)
		end,
		__tostring = function()
			return "Script(" .. path .. ")"
		end,
	})
end

local function requireModule(target)
	if type(target) == "string" then
		return require(target)
	end
	local path = rawget(target, PATH)
	assert(path, "harness require expects a script path object")
	if cache[path] ~= nil then
		return cache[path]
	end
	local file = resolve(path)
	assert(file, "module not found: " .. path)
	local chunk = luau.load(fs.readFile(file), {
		debugName = file,
		environment = { script = makeScript(path), require = requireModule },
	})
	local result = chunk()
	cache[path] = result
	return result
end

-- harness.require("src/shared/Format") -> module
function harness.require(path: string)
	return requireModule(makeScript(path))
end

return harness

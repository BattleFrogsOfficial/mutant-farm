-- Loads Roblox-style ModuleScripts under Lune by faking `script` as a path object,
-- so shared modules keep `require(script.Parent.Config.Eggs)` and still run headless.
-- Only pure modules (no game/workspace/Enum) can be loaded this way.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local harness = {}

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

-- ReplicatedStorage.Shared is src/shared (what Rojo maps it to).
local ALIASES = { ["@RS/Shared"] = "src/shared" }

local function unalias(path: string): string
	for from, to in ALIASES do
		if path == from or path:sub(1, #from + 1) == from .. "/" then
			return to .. path:sub(#from + 1)
		end
	end
	return path
end

-- A module loader with its own cache, extra globals and whole-module overrides (keyed by path,
-- e.g. "src/shared/Remotes").
function harness.loader(env: { [string]: any }?, overrides: { [string]: any }?)
	local cache: { [string]: any } = {}
	local function requireModule(target)
		if type(target) == "string" then
			return require(target)
		end
		local path = rawget(target, PATH)
		assert(path, "harness require expects a script path object")
		if overrides and overrides[path] ~= nil then
			return overrides[path]
		end
		path = unalias(path)
		if overrides and overrides[path] ~= nil then
			return overrides[path]
		end
		if cache[path] ~= nil then
			return cache[path]
		end
		local file = resolve(path)
		assert(file, "module not found: " .. path)
		local environment = if env then table.clone(env) else {}
		environment.script = makeScript(path)
		environment.require = requireModule
		local chunk = luau.load(fs.readFile(file), { debugName = file, environment = environment })
		local result = chunk()
		cache[path] = result
		return result
	end
	return function(path: string)
		return requireModule(makeScript(path))
	end
end

-- harness.require("src/shared/Format") -> module (one shared cache for tests and the sim)
harness.require = harness.loader()

-- A script path object, e.g. harness.script("@RS") stands in for ReplicatedStorage.
function harness.script(path: string)
	return makeScript(path)
end

return harness

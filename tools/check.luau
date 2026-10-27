-- Compiles every Luau file in src/ and tools/ to catch syntax errors without Studio.
-- Usage: lune run tools/check
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local failures = 0
local count = 0

local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif name:match("%.luau?$") then
			count += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failures += 1
				print("SYNTAX " .. path .. "\n  " .. tostring(err))
			end
		end
	end
end

walk("src")
walk("tools")
walk("tests")
print(string.format("%d files compiled, %d failed", count, failures))
process.exit(if failures > 0 then 1 else 0)

-- Runs every tests/*.spec.luau. Usage: lune run tools/test
local fs = require("@lune/fs")
local process = require("@lune/process")
local harness = require("./harness")

local passed, failed = 0, 0

local function deepEqual(a, b): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local t = {}

function t.eq(actual, expected, label: string?)
	if not deepEqual(actual, expected) then
		error(
			string.format(
				"%sexpected %s, got %s",
				if label then label .. ": " else "",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function t.near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(
			string.format(
				"%sexpected %s ± %s, got %s",
				if label then label .. ": " else "",
				expected,
				tolerance,
				actual
			),
			2
		)
	end
end

function t.ok(value, label: string?)
	if not value then
		error((label or "expected truthy value"), 2)
	end
end

t.require = harness.require

local files = fs.readDir("tests")
table.sort(files)
for _, file in files do
	if file:match("%.spec%.luau$") then
		local spec = require("../tests/" .. file:gsub("%.luau$", ""))
		for name, fn in spec(t) do
			local ok, err = pcall(fn)
			if ok then
				passed += 1
			else
				failed += 1
				print(string.format("FAIL %s > %s\n     %s", file, name, tostring(err)))
			end
		end
	end
end

print(string.format("%d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)

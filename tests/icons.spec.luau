-- Icons are UI/Icons glyphs, never emoji or images: no line of client UI code (comments aside)
-- holds an emoji-like codepoint (anything above U+2FFF, plus the arrows / symbols / dingbats
-- blocks and variation selectors), and no ImageLabel / ImageButton exists outside Viewport.lua.
-- Chat lines (ChatController) and server messages keep their emoji (toasts drop them).
local fs = require("@lune/fs")

return function(t)
	local Format = t.require("src/shared/Format")

	local function files(dir: string, out: { string })
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				files(path, out)
			elseif name:match("%.lua$") then
				table.insert(out, path)
			end
		end
		return out
	end

	return {
		["no emoji in the client's UI code (chat lines excepted)"] = function()
			local bad = {}
			for _, path in files("src/client", {}) do
				if path:match("ChatController%.lua$") then
					continue
				end
				local n = 0
				for line in (fs.readFile(path) .. "\n"):gmatch("(.-)\n") do
					n += 1
					local code = line:gsub("%-%-.*$", "")
					for _, cp in utf8.codes(code) do
						if Format.isEmoji(cp) then
							table.insert(bad, string.format("%s:%d: %s", path, n, line:gsub("^%s+", "")))
							break
						end
					end
				end
			end
			t.eq(#bad, 0, "emoji in the UI:\n" .. table.concat(bad, "\n"))
		end,
		["no ImageLabel or ImageButton outside Viewport.lua"] = function()
			local bad = {}
			for _, path in files("src/client", {}) do
				if path:match("Viewport%.lua$") then
					continue
				end
				local text = fs.readFile(path):gsub("%-%-[^\n]*", "")
				if text:find("ImageLabel") or text:find("ImageButton") then
					table.insert(bad, path)
				end
			end
			t.eq(#bad, 0, "images in: " .. table.concat(bad, ", "))
		end,
		["stripEmoji keeps the words"] = function()
			t.eq(Format.stripEmoji("🥚 Lab Egg unlocked!"), "Lab Egg unlocked!")
			t.eq(Format.stripEmoji("📖 50 species! +25 Gems"), "50 species! +25 Gems")
			t.eq(Format.stripEmoji("Done · x5"), "Done · x5")
		end,
	}
end

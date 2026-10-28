-- Runs the real server services (src/server/Services) headlessly under Lune, against fake Roblox
-- services, fake players and an in-memory ProfileStore, on a fake clock. Lets tests drive the
-- actual handlers: join, send intents, advance time, leave and rejoin, read the profile.
--
--   local world = ServerHarness.new()
--   local player, data = world:join(1, { cash = 1_000_000 })
--   world:send(player, "Rebirth")
--   world:advance(3 * 3600) -- runs every service loop whose wait is due
--
-- Not covered (they build or read the map's Instances): PlotService, World.
-- task.wait yields to a small scheduler; time only moves when a test calls advance().

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local harness = require("./harness")

local Rng = harness.require("src/shared/Rng")

local ServerHarness = {}
ServerHarness.__index = ServerHarness

local SERVICES = {
	"DataService",
	"GroupRewardService",
	"EconomyService",
	"GrowthService",
	"DailyService",
	"IncomeService",
	"MonetizationService",
	"RebirthService",
	"WeatherService",
	"LeaderboardService",
}

-- Just enough of an Instance for leaderstats: Name, Value, Parent and FindFirstChild.
local function fakeInstance(className: string)
	local children = {}
	local inst = { ClassName = className, Name = className, children = children }
	function inst.FindFirstChild(_, name)
		return children[name]
	end
	return setmetatable({}, {
		__index = inst,
		__newindex = function(self, k, v)
			if k == "Parent" then
				if v then
					v.children[self.Name] = self
				end
			end
			rawset(inst, k, v)
		end,
	})
end

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

-- Fills keys missing from `data` with copies of `template` values (ProfileStore's Reconcile).
local function reconcile(data, template)
	for k, v in template do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil then
			reconcile(data[k], v)
		end
	end
end

function ServerHarness.new(options: { now: number?, seed: number?, groupId: number? }?)
	local opts = options or {}
	local self = setmetatable({}, ServerHarness)
	self.now = opts.now or 1_800_000_000
	self.saved = {} -- ProfileStore: key -> data
	self.players = {} -- userId -> player
	self.sent = {} -- { player, name, args }
	self.broadcast = {} -- { name, args }
	self.handlers = {} -- remote name -> server handler
	self.sleeping = {} -- { co, wakeAt }
	self.groups = {} -- userId -> { groupId }
	self.ownedGamePasses = {} -- userId -> { [gamePassId] = true }
	self.ordered = {} -- OrderedDataStore name -> { key -> value }
	self.chat = {} -- system chat lines
	self.warnings = {}
	local world = self
	local rng = Rng.new(opts.seed or 12345)

	---------------------------------------------------------------- scheduler

	local function resume(co, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			error(debug.traceback(co, tostring(err)), 0)
		end
	end
	local task = {
		spawn = function(f, ...)
			local co = if type(f) == "thread" then f else coroutine.create(f)
			resume(co, ...)
			return co
		end,
		defer = function(f, ...)
			local co = coroutine.create(f)
			resume(co, ...)
			return co
		end,
		delay = function(seconds, f, ...)
			local args = table.pack(...)
			local co = coroutine.create(function()
				f(table.unpack(args, 1, args.n))
			end)
			table.insert(world.sleeping, { co = co, wakeAt = world.now + (seconds or 0) })
			return co
		end,
		wait = function(seconds)
			local co = coroutine.running()
			table.insert(world.sleeping, { co = co, wakeAt = world.now + math.max(seconds or 0, 1e-3) })
			coroutine.yield()
			return seconds or 0
		end,
	}
	self.task = task

	---------------------------------------------------------------- fake signals / services

	local function signal()
		local handlers = {}
		return {
			Connect = function(_, fn)
				table.insert(handlers, fn)
				return {
					Disconnect = function()
						local i = table.find(handlers, fn)
						if i then
							table.remove(handlers, i)
						end
					end,
				}
			end,
			Fire = function(_, ...)
				for _, fn in table.clone(handlers) do
					task.spawn(fn, ...)
				end
			end,
		}
	end
	self.signal = signal

	local attributes = {}
	local fakeWorkspace = {
		GetServerTimeNow = function()
			return world.now
		end,
		SetAttribute = function(_, k, v)
			attributes[k] = v
		end,
		GetAttribute = function(_, k)
			return attributes[k]
		end,
		AttributeChanged = signal(),
	}
	self.workspace = fakeWorkspace

	local Players = {
		PlayerAdded = signal(),
		PlayerRemoving = signal(),
		GetPlayers = function()
			local list = {}
			for _, p in world.players do
				table.insert(list, p)
			end
			table.sort(list, function(a, b)
				return a.UserId < b.UserId
			end)
			return list
		end,
		GetPlayerByUserId = function(_, id)
			return world.players[id]
		end,
		GetNameFromUserIdAsync = function(_, id)
			return "Player" .. id
		end,
	}
	self.Players = Players

	local function orderedStore(name)
		world.ordered[name] = world.ordered[name] or {}
		local map = world.ordered[name]
		return {
			SetAsync = function(_, key, value)
				map[key] = value
			end,
			GetAsync = function(_, key)
				return map[key]
			end,
			GetSortedAsync = function(_, ascending, pageSize)
				local list = {}
				for key, value in map do
					table.insert(list, { key = key, value = value })
				end
				table.sort(list, function(a, b)
					if a.value ~= b.value then
						return if ascending then a.value < b.value else a.value > b.value
					end
					return a.key < b.key
				end)
				local page = {}
				for i = 1, math.min(pageSize, #list) do
					page[i] = list[i]
				end
				return {
					GetCurrentPage = function()
						return page
					end,
					IsFinished = true,
				}
			end,
		}
	end

	local services = {
		Players = Players,
		RunService = {
			IsStudio = function()
				return true
			end,
			IsServer = function()
				return true
			end,
			IsClient = function()
				return false
			end,
			Heartbeat = signal(),
		},
		MarketplaceService = {
			PromptProductPurchaseFinished = signal(),
			PromptGamePassPurchaseFinished = signal(),
			UserOwnsGamePassAsync = function(_, userId, id)
				return (world.ownedGamePasses[userId] or {})[id] == true
			end,
		},
		PolicyService = {
			GetPolicyInfoForPlayerAsync = function()
				return { ArePaidRandomItemsRestricted = false }
			end,
		},
		GroupService = {
			GetGroupsAsync = function(_, userId)
				local list = {}
				for _, id in world.groups[userId] or {} do
					table.insert(list, { Id = id })
				end
				return list
			end,
		},
		AnalyticsService = {
			LogEconomyEvent = function() end,
			LogOnboardingFunnelStepEvent = function() end,
			LogFunnelStepEvent = function() end,
		},
		DataStoreService = {
			GetOrderedDataStore = function(_, name)
				return orderedStore(name)
			end,
		},
		HttpService = {
			JSONEncode = function(_, v)
				return require("@lune/serde").encode("json", v)
			end,
		},
		TextChatService = {},
	}
	local fakeGame = {
		GetService = function(_, name)
			if name == "ReplicatedStorage" then
				return harness.script("@RS")
			elseif name == "Workspace" then
				return fakeWorkspace
			end
			local s = services[name]
			assert(s, "server harness: no fake for service " .. name)
			return s
		end,
		BindToClose = function() end,
	}
	self.services = services

	---------------------------------------------------------------- module overrides

	local remotes = {}
	local function remote(name)
		if not remotes[name] then
			remotes[name] = {
				OnServerEvent = {
					Connect = function(_, fn)
						world.handlers[name] = fn
					end,
				},
				FireClient = function(_, player, ...)
					table.insert(world.sent, { player = player, name = name, args = table.pack(...) })
				end,
				FireAllClients = function(_, ...)
					table.insert(world.broadcast, { name = name, args = table.pack(...) })
				end,
			}
		end
		return remotes[name]
	end

	local ProfileStore = {
		IsClosing = false,
		SetConstant = function() end,
		New = function(_, template)
			return {
				StartSessionAsync = function(_, key)
					local data = world.saved[key] or deepCopy(template)
					world.saved[key] = data
					local profile = {
						Data = data,
						OnLastSave = signal(),
						OnSessionEnd = signal(),
						OnAfterSave = signal(),
					}
					function profile.AddUserId() end
					function profile.Reconcile()
						reconcile(profile.Data, template)
					end
					function profile.IsActive()
						return not profile.ended
					end
					function profile.Save()
						profile.OnAfterSave:Fire()
					end
					function profile.EndSession()
						profile.ended = true
						profile.OnSessionEnd:Fire()
					end
					return profile
				end,
			}
		end,
	}

	local overrides = {
		["@RS/Packages/ProfileStore"] = ProfileStore,
		["src/shared/Remotes"] = {
			init = function() end,
			get = remote,
		},
		["src/server/Util/RateLimiter"] = {
			allow = function()
				return true
			end,
		},
	}

	local env = {
		game = fakeGame,
		workspace = fakeWorkspace,
		task = task,
		Enum = roblox.Enum,
		Instance = { new = fakeInstance },
		Vector3 = roblox.Vector3,
		Color3 = roblox.Color3,
		Random = {
			new = function(seed)
				local r = Rng.new(seed or rng:integer(1, 2 ^ 31 - 1))
				return {
					NextNumber = function(_, min, max)
						local x = r:next()
						return if min then min + x * (max - min) else x
					end,
					NextInteger = function(_, min, max)
						return r:integer(min, max)
					end,
				}
			end,
		},
		warn = function(...)
			local parts = {}
			for _, v in { ... } do
				table.insert(parts, tostring(v))
			end
			table.insert(world.warnings, table.concat(parts, " "))
		end,
	}

	self.modules = harness.loader(env, overrides)

	---------------------------------------------------------------- start the services

	if opts.groupId then
		self.modules("src/shared/Config/Game").groupId = opts.groupId
	end
	self.service = {}
	for _, name in SERVICES do
		self.service[name] = self.modules("src/server/Services/" .. name)
	end
	for _, name in SERVICES do
		self.service[name].Init()
	end
	for _, name in SERVICES do
		task.spawn(self.service[name].Start)
	end
	return self
end

-- Runs every coroutine whose wait is due, until none is (time doesn't move).
function ServerHarness.runDue(self)
	for _ = 1, 10_000 do
		local due = nil
		for i, s in self.sleeping do
			if s.wakeAt <= self.now and (not due or s.wakeAt < self.sleeping[due].wakeAt) then
				due = i
			end
		end
		if not due then
			return
		end
		local s = table.remove(self.sleeping, due)
		local ok, err = coroutine.resume(s.co)
		if not ok then
			error(debug.traceback(s.co, tostring(err)), 0)
		end
	end
	error("server harness: scheduler did not settle")
end

-- Moves the clock forward. With `step`, wakes the loops every `step` seconds on the way (use it
-- for online play); without, jumps straight there (an offline gap: loops run once at the end).
function ServerHarness.advance(self, seconds: number, step: number?)
	local target = self.now + seconds
	if step then
		while self.now + step < target do
			self.now += step
			self:runDue()
		end
	end
	self.now = target
	self:runDue()
end

-- A player joins. `profile` (optional) seeds their saved data before the session loads; fields
-- are merged over the template by Reconcile.
function ServerHarness.join(self, userId: number, profile: { [string]: any }?)
	local key = tostring(userId)
	if profile and not self.saved[key] then
		self.saved[key] = deepCopy(profile)
	end
	local player = {
		UserId = userId,
		Name = "Player" .. userId,
		Parent = self.Players,
		attributes = {},
		children = {},
	}
	function player.Kick(_, message)
		player.kicked = message
	end
	function player.SetAttribute(_, k, v)
		player.attributes[k] = v
	end
	function player.GetAttribute(_, k)
		return player.attributes[k]
	end
	function player.FindFirstChild(_, name)
		return player.children[name]
	end
	function player.IsInGroup(_, groupId)
		return table.find(self.groups[userId] or {}, groupId) ~= nil
	end
	self.players[userId] = player
	self.Players.PlayerAdded:Fire(player)
	self:runDue()
	return player, self.service.DataService.get(player)
end

function ServerHarness.leave(self, player)
	self.Players.PlayerRemoving:Fire(player)
	player.Parent = nil
	self.players[player.UserId] = nil
	self:runDue()
end

-- Sends a client intent through Net (validation, profile check) to the real handler.
function ServerHarness.send(self, player, name: string, ...)
	local handler = self.handlers[name]
	assert(handler, "no server handler for " .. name)
	self.task.spawn(handler, player, ...)
	self:runDue()
end

-- Remote calls the server made to `player` named `name` (each an args table).
function ServerHarness.received(self, player, name: string): { any }
	local out = {}
	for _, m in self.sent do
		if m.player == player and m.name == name then
			table.insert(out, m.args)
		end
	end
	return out
end

function ServerHarness.data(self, player)
	return self.service.DataService.get(player)
end

return ServerHarness

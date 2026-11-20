-- Rules: the game's own rule tables (shared by its scripts and ours). Changing a number here changes what the game's client scripts do; each tweak is restored on switch-off.
--   Kick.Rules.Miss        random miss on kicks (set to 0 = perfect accuracy)
--   Dribble.Rules.Pickup   how far the ball can be taken / kept from (widened = sticky ball)
local RS = game:GetService("ReplicatedStorage")

local Rules = { Accurate = false, Sticky = false, StickyMult = 1.6, Info = "ready" }
local saved = {}

local function load(path)
	local ok, t = pcall(function()
		local m = RS
		for _, part in ipairs(path) do m = m:WaitForChild(part, 3) end
		return require(m)
	end)
	return ok and type(t) == "table" and t or nil
end

function Rules.SetAccurate(on)
	Rules.Accurate = on
	local R = load({ "Shared", "Game", "Kick", "Rules" })
	local miss = R and R.Miss
	if type(miss) ~= "table" then Rules.Info = "kick rules not found"; return false end
	pcall(function()
		if on then
			saved.miss = saved.miss or { Scale = miss.Scale, WeakFoot = miss.WeakFoot, Across = miss.Across }
			miss.Scale = 0; miss.WeakFoot = 1; miss.Across = 0
		elseif saved.miss then
			miss.Scale, miss.WeakFoot, miss.Across = saved.miss.Scale, saved.miss.WeakFoot, saved.miss.Across
		end
	end)
	return true
end

local PICK = { "FootReach", "BodyReach", "CushionReach", "MaxCarry", "KeepOut" }
function Rules.SetSticky(on, mult)
	Rules.Sticky = on
	if mult then Rules.StickyMult = mult end
	local R = load({ "Shared", "Game", "Dribble", "Rules" })
	local pickup = R and R.Pickup
	if type(pickup) ~= "table" then Rules.Info = "dribble rules not found"; return false end
	pcall(function()
		saved.pick = saved.pick or {}
		for _, k in ipairs(PICK) do
			if type(pickup[k]) == "number" then
				if saved.pick[k] == nil then saved.pick[k] = pickup[k] end
				pickup[k] = on and saved.pick[k] * Rules.StickyMult or saved.pick[k]
			end
		end
	end)
	return true
end

function Rules.Destroy()
	if Rules.Accurate then Rules.SetAccurate(false) end
	if Rules.Sticky then Rules.SetSticky(false) end
end

return Rules

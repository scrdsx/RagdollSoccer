-- Input: the game's controls are Roblox InputActions (found under PlayerScripts or inside your Mannequin: "Sprint", "KickStrike", ...).
-- Firing an action with true / false is the same as holding / releasing its button.
local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local Input = {}
local cache = {}

local function find(name)
	local a = cache[name]
	if a and a.Parent then return a end
	cache[name] = nil
	local roots = { lp:FindFirstChild("PlayerScripts"), lp.Character }
	for _, r in ipairs(roots) do
		local x = r and r:FindFirstChild(name, true)
		if x and x:IsA("InputAction") then cache[name] = x; return x end
	end
	return nil
end
Input.find = find

local held = {}
function Input.Set(name, on)
	if held[name] == on then return true end
	local a = find(name)
	if not a then return false end
	local ok = pcall(function() a:Fire(on) end)
	if ok then held[name] = on end
	return ok
end

function Input.Sprint(on) return Input.Set("Sprint", on) end

function Input.Destroy()
	for name, on in pairs(held) do
		if on then pcall(function() local a = find(name); if a then a:Fire(false) end end) end
	end
	held = {}
end

return Input

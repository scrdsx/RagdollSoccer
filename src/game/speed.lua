-- Speed: the game moves your player from ReplicatedStorage.Shared.Game.MannequinAnimation.Tuning.Speed (Walk 8, Jog 19, Sprint 31 ...): its own movement script writes
-- BaseMoveSpeed from those numbers every frame. Scaling the numbers in that table is the clean way to change your speed. If the table cannot be loaded, the
-- ControllerManager's BaseMoveSpeed is scaled instead.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local World = __import("game/world")

local Speed = { Mult = 1, Info = "off" }
local KEYS = { "Walk", "Jog", "Sprint", "SideStep", "BackStep", "SideStepSprint", "BackStepSprint", "Strafe", "StrafeBack", "SideSprint", "BackSprint" }
local orig, tuning
local conn, lastSet = nil, setmetatable({}, { __mode = "k" })

local function load()
	if tuning then return tuning end
	local ok, t = pcall(function()
		local m = RS
		for _, p in ipairs({ "Shared", "Game", "MannequinAnimation", "Tuning" }) do m = m:WaitForChild(p, 3) end
		return require(m)
	end)
	if ok and type(t) == "table" and type(t.Speed) == "table" then tuning = t.Speed end
	return tuning
end

function Speed.Set(mult)
	Speed.Mult = mult
	local sp = load()
	if sp then
		orig = orig or {}
		for _, k in ipairs(KEYS) do
			if type(sp[k]) == "number" then
				if orig[k] == nil then orig[k] = sp[k] end
				sp[k] = orig[k] * mult
			end
		end
		Speed.Info = ("x%.2f (Tuning.Speed)"):format(mult)
		if conn then conn:Disconnect(); conn = nil end
	else
		-- fallback: boost BaseMoveSpeed after the game wrote it
		Speed.Info = ("x%.2f (controller)"):format(mult)
		if not conn then
			conn = RunService.PreSimulation:Connect(function()
				local me = World.me()
				if not (me and me.cm) or Speed.Mult == 1 then return end
				local cur, mine = me.cm.BaseMoveSpeed, lastSet[me.cm]
				if mine == nil or math.abs(cur - mine) > 1e-3 then
					lastSet[me.cm] = cur * Speed.Mult
					me.cm.BaseMoveSpeed = cur * Speed.Mult
				end
			end)
		end
	end
end

function Speed.Destroy()
	Speed.Set(1)
	if conn then conn:Disconnect(); conn = nil end
end

return Speed

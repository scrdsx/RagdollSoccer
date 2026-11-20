-- Kick: silent aim at the goal, and shooting.
--  Aim:   the game computes a kick locally and sends KickPlan (the plan: dir, power, family ...) and then DribbleRelease (ball position, launch velocity, spin ...).
--         The horizontal direction is turned to a point inside the opponent's goal: KickPlan.dir is replaced and the release velocity / spin are rotated by exactly
--         the same angle, so the two still agree with each other.
--  Shoot: the game's own input action "KickStrike" (the kick button) is held for the charge time and released. If no KickPlan follows, the left mouse button
--         (the game binds the kick tool to it as well) is used once as a fallback.
local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local World = __import("game/world")
local Net = __import("game/net")
local Input = __import("game/input")
local Log = __import("game/log")

local Kick = {
	Aim = false, AllKicks = true, MaxDist = 170, Corner = "Far from keeper", Charge = 0.42,
	Shots = 0, LastPlan = -99, Notify = nil, Info = "off", Shooting = false,
}
Kick.Corners = { "Far from keeper", "Left post", "Right post", "Centre" }

local lastAim = { rot = nil, t = -99 }

local function onPlan(args)
	Kick.LastPlan = os.clock()
	local plan = args[1]
	if type(plan) ~= "table" or typeof(plan.dir) ~= "Vector3" or typeof(plan.ball) ~= "Vector3" then return nil end
	local me = World.me()
	if not me then return nil end
	local target = World.shotTarget(me.team, plan.ball, Kick.Corner)
	if not target then Log.add("KickPlan: no goal found"); return nil end
	local toGoal = World.horiz(target - plan.ball)
	if toGoal.Magnitude < 1 or toGoal.Magnitude > Kick.MaxDist then return nil end
	local oldDir = World.horiz(plan.dir)
	if oldDir.Magnitude < 0.01 then return nil end
	local newDir, oldUnit = toGoal.Unit, oldDir.Unit
	if not Kick.AllKicks then
		local ang = math.deg(math.acos(math.clamp(oldUnit:Dot(newDir), -1, 1)))
		if ang > 75 then return nil end -- "shots only": a kick that points away from the goal is a pass, leave it
	end
	local np = table.clone(plan)
	np.dir = newDir
	lastAim.rot = CFrame.lookAt(Vector3.zero, newDir) * CFrame.lookAt(Vector3.zero, oldUnit):Inverse()
	lastAim.t = os.clock()
	Kick.Shots = Kick.Shots + 1
	Log.add(("KickPlan aimed at goal: %d studs, family %s, power %s"):format(math.floor(toGoal.Magnitude), tostring(plan.family), tostring(plan.power)))
	if Kick.Notify then Kick.Notify(("Shot sent at goal (%d studs)"):format(math.floor(toGoal.Magnitude))) end
	local out = table.clone(args)
	out[1] = np
	return out
end

local function onRelease(args)
	-- DribbleRelease(pid, kind, ballPos, vel, t, nil, spin, family)
	if not lastAim.rot or os.clock() - lastAim.t > 1.5 then return nil end
	local vel = args[4]
	if typeof(vel) ~= "Vector3" then return nil end
	local out = table.clone(args)
	out[4] = lastAim.rot * vel
	if typeof(args[7]) == "Vector3" then out[7] = lastAim.rot * args[7] end
	lastAim.rot = nil
	Log.add("DribbleRelease rotated to match")
	return out
end

local function onClaim(args)
	Log.add("DribbleClaim sent (ball taken)")
	return nil
end

function Kick.SetAim(on)
	Kick.Aim = on
	if on then
		if not Net.Start() then Kick.Info = Net.Error or "hook failed"; Log.add("hook failed: " .. tostring(Net.Error)); return false end
		Net.On("KickPlan", onPlan)
		Net.On("DribbleRelease", onRelease)
		Net.On("DribbleClaim", onClaim)
		Kick.Info = "aiming"
	else
		Net.Off("KickPlan"); Net.Off("DribbleRelease"); Net.Off("DribbleClaim")
		Kick.Info = "off"
	end
	return true
end

-- SHOOT ---------------------------------------------------------------------------------------------------------------------------
local function mouseKick(hold)
	local cam = workspace.CurrentCamera
	local vs = cam and cam.ViewportSize or Vector2.new(960, 540)
	pcall(function() VIM:SendMouseButtonEvent(vs.X / 2, vs.Y / 2, 0, true, game, 0) end)
	task.wait(hold)
	pcall(function() VIM:SendMouseButtonEvent(vs.X / 2, vs.Y / 2, 0, false, game, 0) end)
end

function Kick.Shoot()
	if Kick.Shooting then return false end
	Kick.Shooting = true
	task.spawn(function()
		local before = Kick.LastPlan
		local pressed = Input.Set("KickStrike", true)
		if pressed then
			task.wait(Kick.Charge)
			Input.Set("KickStrike", false)
		else
			mouseKick(Kick.Charge)
		end
		task.wait(0.55)
		if Kick.LastPlan == before then
			-- the button did nothing: try the mouse once
			Log.add("shoot: no KickPlan after the button, trying the mouse")
			mouseKick(Kick.Charge)
		end
		task.wait(0.3)
		Kick.Shooting = false
	end)
	return true
end

function Kick.Destroy()
	Kick.SetAim(false)
	Input.Set("KickStrike", false)
end

return Kick

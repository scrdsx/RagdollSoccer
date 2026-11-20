-- Kick: assist for YOUR shots. You still aim, charge and kick yourself; this changes what is sent to the server.
--  The game computes a kick locally and sends KickPlan (the plan: dir, power, family ...) and then DribbleRelease (ball position, launch velocity, spin ...).
--  * Aim:   the horizontal direction is turned to a point inside the opponent's goal (away from the keeper). KickPlan.dir is replaced and the release velocity /
--           spin are rotated by the same angle, so the two still agree with each other.
--  * Boost: the horizontal speed of the release is scaled, more for longer distances (a shot from far still arrives, and the keeper gets less time).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local World = __import("game/world")
local Net = __import("game/net")
local Log = __import("game/log")

local Kick = {
	Aim = false, Boost = true, BoostMax = 2.2, AllKicks = true, MaxDist = 400, Corner = "Far from keeper",
	Shots = 0, Notify = nil, Info = "off",
}
Kick.Corners = { "Far from keeper", "Left post", "Right post", "Centre" }

local lastAim = { rot = nil, dist = 0, t = -99 }
local rejectConn

local function onPlan(args)
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
	lastAim.dist = toGoal.Magnitude
	lastAim.t = os.clock()
	Kick.Shots = Kick.Shots + 1
	Log.add(("KickPlan aimed at goal: %d studs, family %s, power %s"):format(math.floor(toGoal.Magnitude), tostring(plan.family), tostring(plan.power)))
	local out = table.clone(args)
	out[1] = np
	return out
end

local function onRelease(args)
	-- DribbleRelease(pid, kind, ballPos, vel, t, nil, spin, family)
	if not lastAim.rot or os.clock() - lastAim.t > 1.5 then return nil end
	local vel = args[4]
	if typeof(vel) ~= "Vector3" then return nil end
	local v = lastAim.rot * vel
	local scale = 1
	if Kick.Boost then
		-- farther goal -> more speed: 1.0x up to about 40 studs, then growing, capped at BoostMax. Height is kept, so the arc stays the same.
		scale = math.clamp(0.5 + lastAim.dist / 80, 1, Kick.BoostMax)
		v = Vector3.new(v.X * scale, v.Y, v.Z * scale)
	end
	local out = table.clone(args)
	out[4] = v
	if typeof(args[7]) == "Vector3" then out[7] = lastAim.rot * args[7] end
	lastAim.rot = nil
	Log.add(("DribbleRelease rotated, speed x%.2f"):format(scale))
	if Kick.Notify then Kick.Notify(("Shot at goal  -  %d st  -  power x%.1f"):format(math.floor(lastAim.dist), scale)) end
	return out
end

-- the server tells you when it refuses a release; log it so a too strong boost can be spotted
local function watchRejects()
	if rejectConn then return end
	pcall(function()
		for _, d in ipairs(RS:GetDescendants()) do
			if d:IsA("RemoteEvent") and d.Name:find("DribbleReject", 1, true) then
				rejectConn = d.OnClientEvent:Connect(function(...)
					Log.add("SERVER REJECTED a dribble / kick call: " .. tostring((...)))
					if Kick.Notify then Kick.Notify("Server rejected the last kick  -  lower the power boost") end
				end)
				break
			end
		end
	end)
end

function Kick.SetAim(on)
	Kick.Aim = on
	if on then
		if not Net.Start() then Kick.Info = Net.Error or "hook failed"; Log.add("hook failed: " .. tostring(Net.Error)); return false end
		Net.On("KickPlan", onPlan)
		Net.On("DribbleRelease", onRelease)
		watchRejects()
		Kick.Info = "aiming"
	else
		Net.Off("KickPlan"); Net.Off("DribbleRelease")
		Kick.Info = "off"
	end
	return true
end

function Kick.Destroy()
	Kick.SetAim(false)
	if rejectConn then rejectConn:Disconnect(); rejectConn = nil end
end

return Kick

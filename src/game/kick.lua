-- Kick: assist for YOUR shots. You still aim, charge and kick yourself; this changes what is sent to the server.
--  The game computes a kick locally and sends KickPlan (the plan: dir, power, family ...) and then DribbleRelease (ball position, launch velocity, spin, family).
--  * Aim:        the horizontal direction is turned to a point inside the opponent's goal (away from the keeper). KickPlan.dir is replaced and the release velocity /
--                spin are rotated by the same angle, so the two still agree with each other.
--  * Super shot: the kick is sent as the strongest family ("Power") with the highest speed the server allows, along the FLATTEST path that still reaches the goal
--                (solved with the game's own drag and gravity), so the ball arrives as fast as possible. The server clamps the speed per kick family (seen in the log:
--                Backheel ~75, RunOutside ~117, Laced ~138, Power ~156); the clamp is learned from the server's reply, so every shot asks for a bit more until it is found.
local RS = game:GetService("ReplicatedStorage")
local World = __import("game/world")
local Net = __import("game/net")
local Log = __import("game/log")

local Kick = {
	Aim = false, Super = true, Family = "Power", MaxAngle = 55, AllKicks = true, MaxDist = 400, Corner = "Far from keeper",
	Shots = 0, Notify = nil, Info = "off",
}
Kick.Corners = { "Far from keeper", "Left post", "Right post", "Centre" }
Kick.Families = { "Power", "Laced", "Finesse" }
Kick.Cap = {}      -- family -> highest speed the server has accepted so far
local CAP_GUESS = 150

local lastAim = { rot = nil, dir = nil, dist = 0, y = 1.9, t = -99 }
local lastSuper = { t = -99, family = nil }
local rejectConn, flightConn

-- height of the ball when it has travelled `dist` horizontally, launched at speed s and angle ang (quadratic drag, gravity g); -1e9 if it lands before
local function heightAt(s, ang, dist, y0, g, k)
	local vx, vy = s * math.cos(ang), s * math.sin(ang)
	local x, y = 0, y0
	local dt = 1 / 100
	for _ = 1, 2000 do
		local sp = math.sqrt(vx * vx + vy * vy)
		vx = vx - k * sp * vx * dt
		vy = vy - (g + k * sp * vy) * dt
		local nx, ny = x + vx * dt, y + vy * dt
		if nx >= dist then return y + (ny - y) * ((dist - x) / math.max(nx - x, 1e-6)) end
		if ny < y0 - 0.3 and vy < 0 then return -1e9 end
		x, y = nx, ny
	end
	return -1e9
end

-- the flattest launch angle (radians) that still has the ball at height yt when it reaches dist, at a fixed speed
function Kick.SolveAngle(dist, speed, y0, yt, g, k, maxDeg)
	local lo, hi = math.rad(1), math.rad(maxDeg)
	if heightAt(speed, hi, dist, y0, g, k) < yt then return hi end -- not reachable: steepest allowed
	if heightAt(speed, lo, dist, y0, g, k) >= yt then return lo end -- reachable flat
	for _ = 1, 26 do
		local mid = (lo + hi) / 2
		if heightAt(speed, mid, dist, y0, g, k) >= yt then hi = mid else lo = mid end
	end
	return hi
end

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
	if Kick.Super then np.family = Kick.Family; np.power = 1 end
	lastAim.rot = CFrame.lookAt(Vector3.zero, newDir) * CFrame.lookAt(Vector3.zero, oldUnit):Inverse()
	lastAim.dist = toGoal.Magnitude
	lastAim.dir = newDir
	lastAim.y = plan.ball.Y
	lastAim.t = os.clock()
	Kick.Shots = Kick.Shots + 1
	Log.add(("KickPlan aimed at goal: %d studs, family %s -> %s, power %s"):format(math.floor(toGoal.Magnitude), tostring(plan.family), Kick.Super and Kick.Family or "unchanged", tostring(plan.power)))
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
	local v = lastAim.rot * vel
	local note
	if Kick.Super and lastAim.dir then
		local ball = World.ball()
		local g = (ball and tonumber(ball:GetAttribute("Gravity"))) or 46
		local air = (ball and tonumber(ball:GetAttribute("AirDrag"))) or 1
		local k = 0.024366064765727467 * air * 0.213
		local cap = Kick.Cap[Kick.Family] or CAP_GUESS
		local ask = cap * 1.12 -- a little above what has been accepted so far; the server clamps and the reply tells the real limit
		local y0 = lastAim.y
		local ang = Kick.SolveAngle(lastAim.dist, cap, y0, y0 + 0.9, g, k, Kick.MaxAngle)
		v = lastAim.dir * (ask * math.cos(ang)) + Vector3.new(0, ask * math.sin(ang), 0)
		out[8] = Kick.Family
		out[7] = Vector3.zero
		lastSuper.t, lastSuper.family = os.clock(), Kick.Family
		note = ("SUPER SHOT  -  %d st  -  %d studs/s"):format(math.floor(lastAim.dist), math.floor(ask))
		Log.add(("SUPER: %d studs, asked %.0f studs/s at %.1f deg (known cap %.0f, family %s)"):format(math.floor(lastAim.dist), ask, math.deg(ang), cap, Kick.Family))
	else
		if typeof(args[7]) == "Vector3" then out[7] = lastAim.rot * args[7] end
		note = ("Shot at goal  -  %d st"):format(math.floor(lastAim.dist))
		Log.add("DribbleRelease rotated")
	end
	out[4] = v
	lastAim.rot = nil
	if Kick.Notify then Kick.Notify(note) end
	return out
end

-- the server tells you when it refuses a release; log it
local function watchRejects()
	if rejectConn then return end
	pcall(function()
		for _, d in ipairs(RS:GetDescendants()) do
			if d:IsA("RemoteEvent") and d.Name:find("DribbleReject", 1, true) then
				rejectConn = d.OnClientEvent:Connect(function(...)
					Log.add("SERVER REJECTED a dribble / kick call: " .. tostring((...)))
				end)
				break
			end
		end
	end)
end

-- what the SERVER did with the kick: its KickFlight attribute holds the launch velocity it accepted. That is how the speed cap per family is learned.
-- format: version | id | t | pos x y z | vel x y z | spin x y z | player | family
local function watchFlight()
	local ball = World.ball()
	if not ball or flightConn then return end
	flightConn = ball:GetAttributeChangedSignal("KickFlight"):Connect(function()
		local raw = tostring(ball:GetAttribute("KickFlight"))
		Log.add("server KickFlight: " .. raw:sub(1, 140))
		if os.clock() - lastSuper.t < 3 then
			local f = string.split(raw, "|")
			local vx, vy, vz = tonumber(f[7]), tonumber(f[8]), tonumber(f[9])
			local fam = f[14]
			if vx and vy and vz and fam == lastSuper.family then
				local sp = math.sqrt(vx * vx + vy * vy + vz * vz)
				local prev = Kick.Cap[fam] or 0
				if sp > prev or sp < prev * 0.9 then
					Kick.Cap[fam] = sp
					Log.add(("learned: %s accepted up to %.0f studs/s"):format(fam, sp))
					if Kick.Notify then Kick.Notify(("Server accepted %.0f studs/s"):format(sp)) end
				end
				lastSuper.t = -99
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
		watchFlight()
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
	if flightConn then flightConn:Disconnect(); flightConn = nil end
end

return Kick

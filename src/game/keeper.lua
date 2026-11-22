-- Keeper: assist for when YOU are the goalkeeper (Role == "Goalkeeper"). Does nothing while you play outfield.
--  * Goal-line lock: you slide to the best spot between the ball and the middle of the goal (or to the exact spot a shot will cross the line), staying inside the goal width and
--    a little off the line. You still move yourself; this only adds a correction every frame, faster than a normal run.
--  * Auto dive: the ball's flight is predicted with the game's drag + gravity; when it is going to cross the goal line inside the posts, the right dive key is pressed at the
--    right time (Q / E mid, Z / C low, jump + Q / E high, X smother). The game still does the dive itself, so the server sees a normal dive.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local World = __import("game/world")
local Log = __import("game/log")
local lp = Players.LocalPlayer

local Keeper = {
	Enabled = false, Dive = true, Lock = true, FaceBall = true,
	Reaction = 0.8,    -- seconds before the ball crosses the line at which the dive is pressed
	Out = 7,           -- how far off the goal line you stand when the ball is far (studs)
	Speed = 42,        -- slide speed of the goal-line lock (studs/s)
	MinDive = 2.2,     -- a shot this close to you is not dived at (you are already there)
	Smother = true, Rush = true, RushRange = 30, Saves = 0, Info = "off",
}

local conn
local vel, lastPos = Vector3.zero, nil
local lastDive, lastLog = -99, -99
local floorY, loggedGoal = nil, false
local flight, flightBall, flightConn

-- the server's own KickFlight record: exact start position and velocity of every kick, known the moment it happens
local function hookFlight(ball)
	if flightBall == ball then return end
	if flightConn then flightConn:Disconnect() end
	flightBall = ball
	flightConn = ball:GetAttributeChangedSignal("KickFlight"):Connect(function()
		local f = string.split(tostring(ball:GetAttribute("KickFlight")), "|")
		local px, py, pz, vx, vy, vz = tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8]), tonumber(f[9])
		if px and pz and vx and vz then flight = { p = Vector3.new(px, py, pz), v = Vector3.new(vx, vy or 0, vz), t0 = os.clock() } end
	end)
end
local actions = {}

local function horiz(v) return Vector3.new(v.X, 0, v.Z) end

-- InputActions are created by the game's input layer under PlayerScripts (one InputContext per group); found by name
local function action(name)
	local a = actions[name]
	if a and a.Parent then return a end
	local ps = lp:FindFirstChild("PlayerScripts")
	if not ps then return nil end
	for _, ctx in ipairs(ps:GetChildren()) do
		if ctx:IsA("InputContext") then
			local x = ctx:FindFirstChild(name)
			if x and x:IsA("InputAction") then actions[name] = x; return x end
		end
	end
	return nil
end

local function press(name, hold)
	local a = action(name)
	if not a then Log.add("keeper: input action not found: " .. name); return false end
	local ok = pcall(function() a:Fire(true) end)
	task.delay(hold or 0.12, function() pcall(function() a:Fire(false) end) end)
	return ok
end

-- ball velocity: the physics velocity when it has one, otherwise the movement between frames
local function trackBall(ball, dt)
	local p = ball.Position
	local v = ball.AssemblyLinearVelocity
	if v.Magnitude < 3 and lastPos and dt > 0 then
		local est = (p - lastPos) / dt
		if est.Magnitude < 500 then v = vel:Lerp(est, 0.6) end
	end
	lastPos = p
	vel = v
	return p, v
end

-- where and when the ball crosses the goal line plane x = goalX (outward = sign of the goal's side). nil if it never gets there within 3 s.
local function predict(p, v, goalX, outward, g, k, floor)
	local x, y, z = p.X, p.Y, p.Z
	local vx, vy, vz = v.X, v.Y, v.Z
	local dt = 1 / 60
	for i = 1, 180 do
		local sp = math.sqrt(vx * vx + vy * vy + vz * vz)
		vx = vx - k * sp * vx * dt
		vy = vy - (g + k * sp * vy) * dt
		vz = vz - k * sp * vz * dt
		local nx = x + vx * dt
		if (nx - goalX) * outward >= 0 then
			local f = ((goalX - x) / math.max(nx - x, 1e-6))
			f = math.clamp(f, 0, 1)
			return i * dt, y + vy * dt * f, z + vz * dt * f
		end
		x, y, z = nx, y + vy * dt, z + vz * dt
		if y < floor then -- ground: the ball bounces a little, then rolls
			y = floor
			vy = vy < -6 and -vy * 0.5 or 0
		end
	end
	return nil
end

local function step(dt)
	if not Keeper.Enabled then return end
	local me = World.me()
	if not me or me.role ~= "Goalkeeper" then Keeper.Info = "not in goal"; return end
	local ball = World.ball()
	local goal = World.ownGoal(me.team)
	if not (ball and goal) then Keeper.Info = "no goal found"; return end
	Keeper.Info = "guarding"
	if not loggedGoal then
		loggedGoal = true
		Log.add(("keeper: own goal at (%.0f, %.0f) size (%.0f, %.0f, %.0f), outward %d, half width used %.1f"):format(goal.pos.X, goal.pos.Z, goal.size.X, goal.size.Y, goal.size.Z, goal.outward, math.max(goal.size.Z, goal.size.X) / 2))
	end

	hookFlight(ball)
	local bp, bv = trackBall(ball, dt)
	-- ground level for the ball = the lowest it has been seen (it rests there); forgotten slowly in case the pitch differs
	floorY = floorY and math.min(floorY + dt * 0.05, bp.Y) or bp.Y
	local root = me.root
	local half = math.max(goal.size.Z, goal.size.X) / 2
	local gx, gz = goal.pos.X, goal.pos.Z
	local outward = goal.outward -- +1 when the goal is on the +X end
	local g = tonumber(ball:GetAttribute("Gravity")) or 46
	local air = tonumber(ball:GetAttribute("AirDrag")) or 1
	local k = 0.024366064765727467 * air * 0.213

	-- is a shot on its way?
	local lineX = gx - outward * math.max(goal.size.X / 2 - 1, 0) -- the front of the goal, where the ball counts as in
	local possession = World.possession(ball, me)
	local threat
	local p0, v0, elapsed = bp, bv, 0
	if flight and possession == "free" and os.clock() - flight.t0 < 3 then p0, v0, elapsed = flight.p, flight.v, os.clock() - flight.t0 end
	if v0.X * outward > 16 then
		local t, y, z = predict(p0, v0, lineX, outward, g, k, floorY)
		if t then
			t = t - elapsed
			if t > -0.08 and math.abs(z - gz) <= half + 4 and y - root.Position.Y < 12 then threat = { t = math.max(t, 0), y = y, z = z } end
		end
	end

	local hasBall = possession == "me"
	local busy = me.state ~= nil and me.state ~= "Animated"

	-- goal-line lock
	if Keeper.Lock and not busy and not hasBall then
		local inward = -outward
		local tz, depth
		local d2goal = horiz(bp - Vector3.new(gx, 0, gz)).Magnitude
		local rush = Keeper.Rush and possession == "other" and not threat and d2goal < Keeper.RushRange
		if rush then
			-- somebody dribbles at you: come off the line to the ball, on the line ball -> goal centre, to shrink the angle
			local dirv = horiz(Vector3.new(gx, 0, gz) - bp)
			dirv = dirv.Magnitude > 0.5 and dirv.Unit or Vector3.new(inward, 0, 0)
			local want = bp + dirv * 4.5
			tz = math.clamp(want.Z, gz - (half - 1.5), gz + (half - 1.5))
			depth = math.clamp((want.X - lineX) * inward, 1.5, Keeper.RushRange)
			if horiz(bp - root.Position).Magnitude < 9 and os.clock() - lastDive > 1.6 then
				lastDive = os.clock()
				press("Smother")
				Log.add(("keeper: rush smother, ball %.1f studs away"):format(horiz(bp - root.Position).Magnitude))
			end
		elseif threat then
			tz = math.clamp(threat.z, gz - (half - 1), gz + (half - 1))
			depth = 2.5
		else
			local centre = Vector3.new(gx, root.Position.Y, gz)
			local dirv = horiz(bp - centre)
			if dirv.Magnitude < 1 then dirv = Vector3.new(inward, 0, 0) end
			dirv = dirv.Unit
			local want = Vector3.new(lineX, 0, gz) + dirv * math.min(Keeper.Out, (horiz(bp - centre)).Magnitude * 0.5)
			tz = math.clamp(want.Z, gz - (half - 1.5), gz + (half - 1.5))
			depth = math.clamp((want.X - lineX) * inward, 1.5, Keeper.Out + 2)
		end
		local target = Vector3.new(lineX + inward * depth, root.Position.Y, tz)
		local cur = root.Position
		local delta = horiz(target - cur)
		local mag = delta.Magnitude
		if mag > 0.25 then
			local sp = Keeper.Speed * ((threat or rush) and 1.8 or 1)
			local np = cur + delta.Unit * math.min(mag, sp * dt)
			local face = root.CFrame - root.CFrame.Position
			if Keeper.FaceBall then
				local look = horiz(bp - np)
				if look.Magnitude > 0.5 then face = CFrame.lookAt(Vector3.zero, look) end
			end
			pcall(function() root.CFrame = CFrame.new(np) * face end)
		end
	end

	-- auto dive
	if Keeper.Dive and threat and not busy and not hasBall and threat.t <= Keeper.Reaction and os.clock() - lastDive > 1.1 then
		local cam = workspace.CurrentCamera
		local right = cam and horiz(cam.CFrame.RightVector)
		if right and right.Magnitude > 0.05 then
			right = right.Unit
			local cross = Vector3.new(lineX, threat.y, threat.z)
			local rel = horiz(cross - root.Position)
			local lat = rel:Dot(right)
			local high = threat.y - root.Position.Y > 3.4
			local low = threat.y - root.Position.Y < 0.4
			lastDive = os.clock()
			if math.abs(lat) < Keeper.MinDive then
				if Keeper.Smother and not high and rel.Magnitude < 12 and threat.t <= Keeper.Reaction * 0.6 then
					press("Smother")
					Log.add(("keeper: smother (ball %.1f s away, %.1f off-centre)"):format(threat.t, lat))
				else
					lastDive = -99
				end
			else
				local side = lat > 0 and "Right" or "Left"
				Keeper.Saves = Keeper.Saves + 1
				if high then
					press("Jump", 0.35)
					task.delay(0.04, function() press("Dive" .. side) end)
				elseif low then
					press("LowDive" .. side)
				else
					press("Dive" .. side)
				end
				Log.add(("keeper: dive %s (%s), ball crosses in %.2fs, %.1f studs away, height %.1f"):format(side, high and "high" or low and "low" or "mid", threat.t, lat, threat.y - root.Position.Y))
			end
		end
	end

	if threat and os.clock() - lastLog > 1 then
		lastLog = os.clock()
		Log.add(("keeper: shot coming, crosses in %.2fs at z offset %.1f, height %.1f"):format(threat.t, threat.z - gz, threat.y - root.Position.Y))
	end
end

function Keeper.Start()
	if conn then return end
	conn = RunService.PreSimulation:Connect(function(dt) pcall(step, dt) end)
end

function Keeper.Set(on)
	Keeper.Enabled = on
	if not on then Keeper.Info = "off"; vel, lastPos = Vector3.zero, nil end
end

function Keeper.Destroy()
	if flightConn then flightConn:Disconnect(); flightConn = nil end
	if conn then conn:Disconnect(); conn = nil end
	Keeper.Enabled = false
end

return Keeper

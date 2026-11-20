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
	Rocket = true, RocketFrom = 70, RocketStyle = "Missile (fast, flat)", RocketTune = 1.0,
	Shots = 0, Notify = nil, Info = "off",
}
Kick.Corners = { "Far from keeper", "Left post", "Right post", "Centre" }

Kick.ANGLES = { ["Missile (fast, flat)"] = 14, ["Rocket"] = 32, ["Lob (high, slow)"] = 58 }
Kick.Styles = { "Missile (fast, flat)", "Rocket", "Lob (high, slow)" }
Kick.MaxSpeed = 320

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

-- the smallest speed for which the ball is still at height `yt` when it reaches `dist` (a coming-down crossing)
function Kick.Solve(dist, ang, y0, yt, g, k)
	local lo, hi = 4, Kick.MaxSpeed
	if heightAt(hi, ang, dist, y0, g, k) < yt then return hi end -- cannot get there at this angle: as fast as allowed
	for _ = 1, 28 do
		local mid = (lo + hi) / 2
		if heightAt(mid, ang, dist, y0, g, k) >= yt then hi = mid else lo = mid end
	end
	return hi
end

local lastAim = { rot = nil, dir = nil, dist = 0, t = -99 }
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
	lastAim.dir = newDir
	lastAim.y = plan.ball.Y
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
	local rocket = Kick.Rocket and lastAim.dist >= Kick.RocketFrom and lastAim.dir ~= nil
	if rocket then
		-- ROCKET: the launch speed that makes the ball arrive at the goal. The game's flight model has a quadratic air drag (BallPath: drag = 0.0243 * AirDrag * 0.213)
		-- and the ball's own gravity (attribute Gravity, 46), so the arrival is solved numerically instead of with the drag-free formula (which fell far short).
		local ball = World.ball()
		local g = (ball and tonumber(ball:GetAttribute("Gravity"))) or 46
		local air = (ball and tonumber(ball:GetAttribute("AirDrag"))) or 1
		local k = 0.024366064765727467 * air * 0.213
		local ang = math.rad(Kick.ANGLES[Kick.RocketStyle] or 16)
		local y0 = lastAim.y or 1.9
		local s = Kick.Solve(lastAim.dist * Kick.RocketTune, ang, y0, y0 + 0.9, g, k)
		v = lastAim.dir * (s * math.cos(ang)) + Vector3.new(0, s * math.sin(ang), 0)
		scale = s
		Log.add(("ROCKET %s: %d studs, speed %.0f at %d deg (g %.0f, drag %.4f)"):format(Kick.RocketStyle, math.floor(lastAim.dist), s, math.floor(math.deg(ang)), g, k))
		Kick.Landing(lastAim.dir, lastAim.dist)
	elseif Kick.Boost then
		-- farther goal -> more speed: 1.0x up to about 40 studs, then growing, capped at BoostMax. Height is kept, so the arc stays the same.
		scale = math.clamp(0.5 + lastAim.dist / 80, 1, Kick.BoostMax)
		v = Vector3.new(v.X * scale, v.Y, v.Z * scale)
	end
	local out = table.clone(args)
	out[4] = v
	if typeof(args[7]) == "Vector3" then out[7] = rocket and Vector3.zero or lastAim.rot * args[7] end
	lastAim.rot = nil
	if not rocket then Log.add(("DribbleRelease rotated, speed x%.2f"):format(scale)) end
	if Kick.Notify then
		Kick.Notify(rocket and ("ROCKET  -  %d st"):format(math.floor(lastAim.dist)) or ("Shot at goal  -  %d st  -  power x%.1f"):format(math.floor(lastAim.dist), scale))
	end
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

-- after a rocket: what did the ball do? apex, height when it reached the goal distance, and where it came down
local landing
function Kick.Landing(dir, want)
	local ball = World.ball()
	if not ball then return end
	local start = ball.Position
	if landing then landing:Disconnect() end
	local t0, apex, crossed = os.clock(), start.Y, false
	landing = game:GetService("RunService").Heartbeat:Connect(function()
		local dt = os.clock() - t0
		local b = World.ball()
		if not b or dt > 10 then
			if landing then landing:Disconnect(); landing = nil end
			return
		end
		local p = b.Position
		apex = math.max(apex, p.Y)
		local along = World.horiz(p - start):Dot(dir)
		if not crossed and along >= want * 0.98 then
			crossed = true
			Log.add(("ROCKET reached the goal distance at %.1fs, height %.1f (apex so far %.0f)"):format(dt, p.Y, apex))
		end
		if apex > start.Y + 3 and p.Y < start.Y + 1.5 and dt > 0.4 then
			Log.add(("ROCKET came down %.0f studs along the aim (wanted %.0f, side %.0f), apex %.0f, after %.1fs"):format(along, want, (World.horiz(p - start) - dir * along).Magnitude, apex, dt))
			landing:Disconnect(); landing = nil
		end
	end)
end

local flightConn
local function watchFlight()
	local ball = World.ball()
	if not ball or flightConn then return end
	flightConn = ball:GetAttributeChangedSignal("KickFlight"):Connect(function()
		-- what the SERVER decided for the kick (to compare with what we sent)
		Log.add("server KickFlight: " .. tostring(ball:GetAttribute("KickFlight")):sub(1, 140))
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
	if landing then landing:Disconnect(); landing = nil end
end

return Kick

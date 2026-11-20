-- Fun: silly mechanics for your own player. All of it only drives your own ControllerManager (FacingDirection) / Root, before every physics step.
--   Spinbot    your player spins on the spot while you play (the kick still goes where the aim assist sends it)
--   Moonwalk   you face away from where you run
--   Sideways   you run sideways (face 90 degrees off your direction)
--   Jitter     your player shakes: other people see you vibrate around your real spot
--   Ball magnet  teleport behind a loose ball that is within range (blatant)
local RunService = game:GetService("RunService")
local World = __import("game/world")
local Log = __import("game/log")

local Fun = {
	RainbowBall = false, AimLine = false, Corner = "Far from keeper",
	Spin = false, SpinRate = 900, Moonwalk = false, Sideways = false, Jitter = false, JitterSize = 1.6, Magnet = false, MagnetRange = 60,
}

local conn
local spinAngle, lastMagnet, jitterFlip = 0, -99, 1

local line, hue = nil, 0
local function ensureLine()
	if line and line.Parent then return line end
	line = Instance.new("Part")
	line.Name = tostring(math.random(1e6, 9e6)); line.Anchored = true; line.CanCollide = false; line.CanQuery = false; line.CanTouch = false
	line.Material = Enum.Material.Neon; line.Color = Color3.fromRGB(80, 220, 140); line.Transparency = 0.35
	line.Size = Vector3.new(0.25, 0.25, 1); line.Parent = workspace
	return line
end
local function killLine()
	if line then pcall(function() line:Destroy() end); line = nil end
end

local function visuals(dt)
	local ball = World.ball()
	if Fun.RainbowBall and ball then
		hue = (hue + dt * 0.6) % 1
		pcall(function() ball.Color = Color3.fromHSV(hue, 0.85, 1) end)
	end
	if Fun.AimLine and ball then
		local me = World.me()
		local target = me and World.shotTarget(me.team, ball.Position, Fun.Corner)
		if target and (me.root.Position - ball.Position).Magnitude < 40 then
			local a, b = ball.Position, target
			local l = ensureLine()
			local len = (b - a).Magnitude
			l.Size = Vector3.new(0.25, 0.25, math.max(len, 0.1))
			l.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2)
		else
			killLine()
		end
	elseif line then
		killLine()
	end
end

local function step(dt)
	visuals(dt)
	if not (Fun.Spin or Fun.Moonwalk or Fun.Sideways or Fun.Jitter or Fun.Magnet) then return end
	local me = World.me()
	if not me or not me.cm then return end
	if me.state ~= nil and me.state ~= "Animated" then return end
	local cm, root = me.cm, me.root
	local move = World.horiz(cm.MovingDirection)

	-- facing games (one wins, in this order)
	if Fun.Spin then
		spinAngle = (spinAngle + math.rad(Fun.SpinRate) * dt) % (math.pi * 2)
		pcall(function() cm.FacingDirection = Vector3.new(math.cos(spinAngle), 0, math.sin(spinAngle)) end)
	elseif move.Magnitude > 0.1 then
		if Fun.Moonwalk then
			pcall(function() cm.FacingDirection = -move.Unit end)
		elseif Fun.Sideways then
			local d = move.Unit
			pcall(function() cm.FacingDirection = Vector3.new(-d.Z, 0, d.X) end)
		end
	end

	-- jitter: tiny sideways offsets every frame, alternating, so everybody else sees a vibrating player
	if Fun.Jitter then
		jitterFlip = -jitterFlip
		local side = root.CFrame.RightVector
		pcall(function() root.CFrame = root.CFrame + side * (Fun.JitterSize * 0.12 * jitterFlip) end)
	end

	-- ball magnet
	if Fun.Magnet and os.clock() - lastMagnet > 0.6 and me.role ~= "Goalkeeper" then
		local ball = World.ball()
		if ball and World.possession(ball, me) == "free" then
			local pos, bp = root.Position, ball.Position
			local d = World.horiz(bp - pos).Magnitude
			if d > 6 and d <= Fun.MagnetRange then
				lastMagnet = os.clock()
				local target = World.shotTarget(me.team, bp, "Centre")
				local back = target and World.horiz(target - bp).Unit * -2.2 or Vector3.zero
				local np = Vector3.new(bp.X + back.X, pos.Y, bp.Z + back.Z)
				pcall(function()
					root.CFrame = CFrame.new(np, np - (back.Magnitude > 0 and back or Vector3.new(0, 0, 1)))
					root.AssemblyLinearVelocity = Vector3.zero
				end)
				Log.add(("magnet: teleported to the ball (%d studs)"):format(math.floor(d)))
			end
		end
	end
end

function Fun.Start()
	if conn then return end
	conn = RunService.PreSimulation:Connect(function(dt) pcall(step, dt) end)
end

function Fun.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	killLine()
	Fun.Spin, Fun.Moonwalk, Fun.Sideways, Fun.Jitter, Fun.Magnet, Fun.RainbowBall, Fun.AimLine = false, false, false, false, false, false, false
end

return Fun

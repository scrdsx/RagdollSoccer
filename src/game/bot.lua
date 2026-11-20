-- Bot ("Ronaldini Banini"): one loop that does everything, before every physics step (so our values are the ones the controller uses).
--   AUTO PLAY   ball free / opponent has it -> run to the ball, approaching from behind (so you run THROUGH it towards the goal and the game picks it up)
--               team mate has it            -> support run
--               you have it                 -> carry it at the goal, steering round defenders
--   AUTO SHOOT  (auto play or manual) when you have the ball, or it is loose at your feet, and you are inside the shooting distance: press the kick button;
--               kick.lua turns the shot to the goal.
--   FUN         spinbot (your character spins), teleport to the loose ball (blatant, the server may not like it)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local World = __import("game/world")
local Kick = __import("game/kick")
local Input = __import("game/input")
local Log = __import("game/log")

local Bot = {
	Enabled = false, Auto = true, AutoShoot = true, ShootDist = 34, Dodge = true, Sprint = true, PauseOnKeys = true, ChaseRange = 700,
	Spin = false, SpinRate = 720, TP = false, TPRange = 70,
	Status = "off",
}

local conn, gui, pillText
local lastShot, lastTP, pauseUntil, spinAngle, lastStatus = -99, -99, 0, 0, ""
local WASD = { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right }

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end

local function pill()
	if gui then return end
	gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 5; gui.Enabled = false; gui.Parent = guiParent()
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(.5, 0); f.Position = UDim2.new(.5, 0, 0, 16); f.Size = UDim2.fromOffset(0, 32); f.AutomaticSize = Enum.AutomaticSize.X
	f.BackgroundColor3 = Color3.fromRGB(21, 21, 24); f.BackgroundTransparency = 0.08; f.BorderSizePixel = 0; f.Parent = gui
	Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(52, 52, 58); st.Parent = f
	local pd = Instance.new("UIPadding"); pd.PaddingLeft = UDim.new(0, 16); pd.PaddingRight = UDim.new(0, 16); pd.Parent = f
	pillText = Instance.new("TextLabel")
	pillText.BackgroundTransparency = 1; pillText.Size = UDim2.fromOffset(0, 32); pillText.AutomaticSize = Enum.AutomaticSize.X
	pillText.Font = Enum.Font.BuilderSansBold; pillText.TextSize = 14; pillText.TextColor3 = Color3.fromRGB(240, 240, 245); pillText.Text = ""; pillText.Parent = f
end

local function status(s)
	if s == Bot.Status then return end
	Bot.Status = s
	if pillText then pillText.Text = "Ronaldini  -  " .. s end
	-- the label changes a lot with distances; only the kind of state goes to the log
	local kind = s:match("^[%a ]+")
	if kind ~= lastStatus then lastStatus = kind; Log.add("state: " .. s) end
end

local function keysDown()
	for _, k in ipairs(WASD) do
		if UIS:IsKeyDown(k) then return true end
	end
	return false
end

-- steer away from opponents standing close to the path
local function steer(dir, pos, opps)
	if not Bot.Dodge then return dir end
	local push = Vector3.zero
	for _, o in ipairs(opps) do
		if o.d > 14 then break end
		local away = World.horiz(pos - o.pos)
		if away.Magnitude > 0.01 and World.horiz(o.pos - pos).Unit:Dot(dir) > 0.15 then
			local side = away.Unit - dir * away.Unit:Dot(dir)
			push = push + side * ((14 - o.d) / 14) * 1.6
		end
	end
	local out = dir + push
	return out.Magnitude < 0.01 and dir or out.Unit
end

local function drive(me, dir)
	local d = World.horiz(dir)
	if d.Magnitude < 0.01 then return end
	d = d.Unit
	pcall(function()
		me.cm.MovingDirection = d
		me.cm.FacingDirection = d
	end)
end

local function step(dt)
	if not Bot.Enabled then return end
	local me = World.me()
	local ball = World.ball()
	if not me or not me.cm or not ball then status("waiting"); return end
	if me.state ~= nil and me.state ~= "Animated" then status("down"); return end
	local pos = me.root.Position
	local bp = ball.Position
	local poss = World.possession(ball, me)
	local dBall = World.horiz(bp - pos).Magnitude
	local keeper = me.role == "Goalkeeper"
	local target = World.shotTarget(me.team, bp, Kick.Corner)

	-- AUTO SHOOT (both modes)
	if Bot.AutoShoot and target and not keeper and not Kick.Shooting and os.clock() - lastShot > 1.2 then
		local dGoal = World.horiz(target - pos).Magnitude
		local mine = poss == "me" or (poss == "free" and dBall < 5.5)
		if mine and dGoal <= Bot.ShootDist then
			Log.add(("shoot: %d studs from goal, ball %s"):format(math.floor(dGoal), poss))
			status("SHOOTING")
			if Kick.Shoot() then lastShot = os.clock() end
			if Bot.Auto then drive(me, World.horiz(target - pos)) end -- keep facing the goal while it charges
			return
		end
	end

	-- AUTO PLAY
	local busy = Kick.Shooting
	if Bot.Auto and not keeper and not busy then
		if Bot.PauseOnKeys and keysDown() then pauseUntil = os.clock() + 0.35 end
		if os.clock() < pauseUntil then
			status("you are driving")
		else
			if Bot.Sprint then Input.Sprint(true) end
			local opps = World.opponents(me.team, pos)
			local goalDir = target and World.horiz(target - bp)
			if goalDir and goalDir.Magnitude > 0.01 then goalDir = goalDir.Unit else goalDir = nil end
			if poss == "me" then
				if target then
					status(("carrying  -  goal %d st"):format(math.floor(World.horiz(target - pos).Magnitude)))
					drive(me, steer(World.horiz(target - pos).Unit, pos, opps))
				end
			else
				local mate = false
				if poss == "other" then
					local p = ball:GetAttribute("Possessor")
					for _, pl in ipairs(Players:GetPlayers()) do
						local c = pl.Character
						if c and pl ~= lp and c:GetAttribute("DribbleId") == p then mate = c:GetAttribute("Team") == me.team end
					end
				end
				if mate then
					if goalDir then
						local spot = bp + goalDir * math.min(World.horiz(target - bp).Magnitude * 0.5, 26)
						local d = World.horiz(spot - pos)
						if d.Magnitude > 4 then status("support run"); drive(me, steer(d.Unit, pos, opps)) else status("in position") end
					end
				elseif dBall <= Bot.ChaseRange then
					-- head for where the ball will be; from behind it (relative to the goal) and then through it
					local bv = World.horiz(ball.AssemblyLinearVelocity)
					local lead = math.clamp(dBall / math.max(me.cm.BaseMoveSpeed, 8), 0, 0.7)
					local aim = bp + bv * lead
					if goalDir then
						if dBall > 7 then aim = aim - goalDir * 2.4 else aim = aim + goalDir * 4 end
					end
					status(("%s  -  %d st"):format(poss == "other" and "pressing" or "chasing the ball", math.floor(dBall)))
					drive(me, World.horiz(aim - pos))
				else
					status("ball too far")
				end
			end
		end
	elseif keeper then
		status("keeper - idle")
	end

	-- FUN
	if Bot.TP and poss == "free" and dBall > 6 and dBall <= Bot.TPRange and os.clock() - lastTP > 0.6 and not keeper then
		lastTP = os.clock()
		local behind = target and (World.horiz(target - bp).Unit * -2.2) or Vector3.zero
		local np = Vector3.new(bp.X + behind.X, pos.Y, bp.Z + behind.Z)
		pcall(function()
			me.root.CFrame = CFrame.new(np, np + (behind.Magnitude > 0 and -behind or Vector3.new(0, 0, -1)))
			me.root.AssemblyLinearVelocity = Vector3.zero
		end)
		Log.add(("teleported to the ball (%d studs)"):format(math.floor(dBall)))
	end
	if Bot.Spin and not Kick.Shooting then
		spinAngle = (spinAngle + math.rad(Bot.SpinRate) * dt) % (math.pi * 2)
		pcall(function() me.cm.FacingDirection = Vector3.new(math.cos(spinAngle), 0, math.sin(spinAngle)) end)
	end
end

function Bot.SetEnabled(on)
	Bot.Enabled = on
	pill()
	gui.Enabled = on
	if on then
		status("starting")
	else
		Input.Sprint(false)
		local me = World.me()
		if me and me.cm then pcall(function() me.cm.MovingDirection = Vector3.zero end) end
		status("off")
	end
end

function Bot.Start()
	if conn then return end
	pill()
	-- PreSimulation runs after the game's own input scripts and right before the physics step
	conn = RunService.PreSimulation:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and Bot.Status ~= "error" then Bot.Status = "error"; Log.add("bot error: " .. tostring(err)); warn("[RagdollSoccer] bot: " .. tostring(err)) end
	end)
end

function Bot.Destroy()
	Bot.Enabled = false
	if conn then conn:Disconnect(); conn = nil end
	if gui then pcall(function() gui:Destroy() end); gui = nil end
end

return Bot

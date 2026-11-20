-- World: what the other modules need to know about the match (read from the dump of the game):
--   your character is a "Mannequin" model: a part called Root, a ControllerManager that moves it, attributes Team / Role / BodyState / DribbleId.
--   the ball is Workspace.Ball (tag SoccerBall); its attribute Possessor is the DribbleId of whoever has it (0 = nobody).
--   the goals are the two models / parts tagged SoccerGoalFrame; the pitch runs along X, workspace attribute BlueSide says which side Blue defends.
-- Goals and opponents are cached (the bot asks for them every frame).
local Players = game:GetService("Players")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer

local World = {}
local function horiz(v) return Vector3.new(v.X, 0, v.Z) end
World.horiz = horiz

function World.me()
	local ch = lp.Character
	local root = ch and ch:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then return nil end
	return {
		char = ch, root = root, cm = ch:FindFirstChildOfClass("ControllerManager"),
		team = ch:GetAttribute("Team"), role = ch:GetAttribute("Role"), state = ch:GetAttribute("BodyState"), id = ch:GetAttribute("DribbleId"),
	}
end

local ballCache
function World.ball()
	if ballCache and ballCache.Parent then return ballCache end
	local b = workspace:FindFirstChild("Ball")
	if not (b and b:IsA("BasePart")) then
		b = nil
		for _, x in ipairs(CS:GetTagged("SoccerBall")) do
			if x:IsA("BasePart") then b = x; break end
		end
	end
	ballCache = b
	return b
end

-- "me", "other" (somebody has it) or "free"
function World.possession(ball, me)
	local p = ball:GetAttribute("Possessor")
	if type(p) ~= "number" or p == 0 then return "free" end
	if me and me.id and p == me.id then return "me" end
	return "other", p
end

-- both goals { pos, size }, cached for 3 s
local goalsAt, goalsList = -99, {}
function World.goals()
	local now = os.clock()
	if now - goalsAt < 3 and #goalsList >= 2 then return goalsList end
	goalsAt = now
	local list = {}
	for _, inst in ipairs(CS:GetTagged("SoccerGoalFrame")) do
		local pos, size
		if inst:IsA("Model") then
			local ok, cf, sz = pcall(function() return inst:GetBoundingBox() end)
			if ok then pos, size = cf.Position, sz end
		elseif inst:IsA("BasePart") then
			pos, size = inst.Position, inst.Size
		end
		if pos then list[#list + 1] = { pos = pos, size = size } end
	end
	goalsList = list
	return list
end

-- the goal this team shoots at
function World.attackGoal(team)
	if team ~= "Blue" and team ~= "Red" then return nil end
	local g = World.goals()
	if #g < 2 then return nil end
	local cx = 0
	for _, x in ipairs(g) do cx = cx + x.pos.X end
	cx = cx / #g
	local side = workspace:GetAttribute("BlueSide") == 1 and 1 or -1
	local own = team == "Blue" and side or -side -- our own goal is on this side (sign of x)
	for _, x in ipairs(g) do
		if (x.pos.X - cx) * own < 0 then return x end
	end
	return nil
end

-- opponents (nearest first) and the opposing keeper's position; the player scan is cached for 0.15 s
local oppAt, oppList, oppKeeper, oppTeam = -99, {}, nil, nil
function World.opponents(team, from)
	local now = os.clock()
	if now - oppAt > 0.15 or oppTeam ~= team then
		oppAt, oppTeam = now, team
		local list, keeper = {}, nil
		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character
			if c and p ~= lp then
				local t = c:GetAttribute("Team")
				if t ~= nil and t ~= team then
					local r = c:FindFirstChild("Root")
					if r then
						if c:GetAttribute("Role") == "Goalkeeper" then keeper = r.Position end
						list[#list + 1] = { pos = r.Position }
					end
				end
			end
		end
		oppList, oppKeeper = list, keeper
	end
	for _, o in ipairs(oppList) do o.d = (o.pos - from).Magnitude end
	table.sort(oppList, function(a, b) return a.d < b.d end)
	return oppList, oppKeeper
end

-- where to shoot: a point inside the goal mouth, chosen by `mode`
function World.shotTarget(team, ballPos, mode)
	local attack = World.attackGoal(team)
	if not attack then return nil end
	local half = math.max(attack.size.Z, attack.size.X) / 2
	local off = math.max(half * 0.66, 1)
	local gz = attack.pos.Z
	local zs
	if mode == "Left post" then zs = -1
	elseif mode == "Right post" then zs = 1
	elseif mode == "Centre" then zs = 0
	else
		local _, keeper = World.opponents(team, ballPos)
		if keeper then zs = keeper.Z >= gz and -1 or 1 else zs = ballPos.Z >= gz and -1 or 1 end
	end
	return Vector3.new(attack.pos.X, ballPos.Y, gz + zs * off), attack
end

return World

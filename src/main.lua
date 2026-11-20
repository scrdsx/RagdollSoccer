-- Ragdoll Soccer: entry point. One window, one module (Ronaldini Banini) with everything inside its settings, and a small Settings tab.
-- Ronaldini is an ASSISTER: you move, aim, charge and kick yourself; it fixes the shot (goal, power, accuracy), keeps the ball with you and adds silly mechanics.
local UIS = game:GetService("UserInputService")
local UI = __import("lib/ui")
local Sfx = __import("lib/sfx")
local Config = __import("lib/config")
local Log = __import("game/log")
local Net = __import("game/net")
local Rules = __import("game/rules")
local Speed = __import("game/speed")
local Kick = __import("game/kick")
local Fun = __import("game/fun")

local env = getgenv and getgenv() or _G
local VERSION = tostring(env.RSVersion or "dev")
print("[RagdollSoccer] running " .. VERSION)

-- a second run replaces the first
if env.__RagdollSoccer then pcall(env.__RagdollSoccer) end

local win = UI.new({ Title = "Ragdoll Soccer", Subtitle = "v" .. VERSION })
local alive = true
Log.Start()
Log.add("loaded v" .. VERSION)
Kick.Notify = function(msg) win:Notify(msg, 2) end

-- RONALDINI ---------------------------------------------------------------------------------------------------------------
local tMain = win:Tab("Ronaldini", { Section = "Play", Icon = 13 })
local speedMult, sticky, accurate = 1.0, true, true
local funState = { Spin = false, Moonwalk = false, Sideways = false, Jitter = false, Magnet = false, RainbowBall = false, AimLine = false }
local mBan

local function applyFun(on)
	for k, v in pairs(funState) do Fun[k] = on and v end
end

local function apply(on)
	Kick.SetAim(on)
	Rules.SetAccurate(on and accurate)
	Rules.SetSticky(on and sticky)
	Speed.Set(on and speedMult or 1)
	applyFun(on)
	win:Notify(on and "Ronaldini Banini ON" or "Ronaldini Banini off", 2)
	Log.add(on and "Ronaldini ON" or "Ronaldini off")
end

mBan = tMain:Module({ Name = "Ronaldini Banini", Default = false, Callback = apply })
local key = mBan:Keybind({ Name = "Toggle key", Default = Enum.KeyCode.Z })

mBan:Section("Your shots")
mBan:Choice({ Name = "Where in the goal", Options = Kick.Corners, Default = Kick.Corner, Callback = function(v) Kick.Corner = v; Fun.Corner = v end })
mBan:Choice({ Name = "Applies to", Options = { "All kicks", "Shots only" }, Default = "All kicks", Callback = function(v) Kick.AllKicks = v == "All kicks" end })
mBan:Toggle({ Name = "ROCKET: far shots fly up high and drop on the goal", Default = Kick.Rocket, Callback = function(v) Kick.Rocket = v end })
mBan:Slider({ Name = "Rocket from", Min = 30, Max = 300, Step = 5, Default = Kick.RocketFrom, Suffix = " st", Callback = function(v) Kick.RocketFrom = v end })
mBan:Slider({ Name = "Rocket height (0 = automatic)", Min = 0, Max = 160, Step = 5, Default = Kick.RocketHeight, Suffix = " st", Callback = function(v) Kick.RocketHeight = v end })
mBan:Slider({ Name = "Rocket range tuning", Min = 0.6, Max = 1.6, Step = 0.02, Default = Kick.RocketTune, Suffix = "x", Callback = function(v) Kick.RocketTune = v end })
mBan:Toggle({ Name = "Power boost (more speed the farther you are)", Default = Kick.Boost, Callback = function(v) Kick.Boost = v end })
mBan:Slider({ Name = "Max power boost", Min = 1, Max = 4, Step = 0.1, Default = Kick.BoostMax, Suffix = "x", Callback = function(v) Kick.BoostMax = v end })
mBan:Slider({ Name = "Works up to", Min = 40, Max = 500, Step = 10, Default = Kick.MaxDist, Suffix = " st", Callback = function(v) Kick.MaxDist = v end })

mBan:Section("Ball")
mBan:Toggle({ Name = "Perfect accuracy", Default = true, Callback = function(v) accurate = v; if mBan:Get() then Rules.SetAccurate(v) end end })
mBan:Toggle({ Name = "Sticky ball (wider pickup reach)", Default = true, Callback = function(v) sticky = v; if mBan:Get() then Rules.SetSticky(v) end end })
mBan:Slider({ Name = "Sticky reach", Min = 1, Max = 3.5, Step = 0.1, Default = Rules.StickyMult, Suffix = "x", Callback = function(v) Rules.StickyMult = v; if mBan:Get() and sticky then Rules.SetSticky(true, v) end end })

mBan:Section("Speed")
mBan:Slider({ Name = "Speed multiplier", Min = 1, Max = 3, Step = 0.05, Default = speedMult, Suffix = "x", Callback = function(v) speedMult = v; if mBan:Get() then Speed.Set(v) end end })

mBan:Section("Funny")
local function fun(name, label)
	mBan:Toggle({ Name = label, Default = false, Callback = function(v) funState[name] = v; if mBan:Get() then Fun[name] = v end end })
end
mBan:Toggle({ Name = "Rainbow ball", Default = false, Callback = function(v) funState.RainbowBall = v; if mBan:Get() then Fun.RainbowBall = v end end })
mBan:Toggle({ Name = "Aim line (shows where the shot goes)", Default = false, Callback = function(v) funState.AimLine = v; if mBan:Get() then Fun.AimLine = v end end })
fun("Spin", "Spinbot")
mBan:Slider({ Name = "Spin speed", Min = 90, Max = 3000, Step = 30, Default = Fun.SpinRate, Suffix = " deg/s", Callback = function(v) Fun.SpinRate = v end })
fun("Moonwalk", "Moonwalk (face away from where you run)")
fun("Sideways", "Run sideways")
fun("Jitter", "Jitter (others see you vibrate)")
mBan:Slider({ Name = "Jitter size", Min = 0.5, Max = 6, Step = 0.1, Default = Fun.JitterSize, Suffix = " st", Callback = function(v) Fun.JitterSize = v end })
fun("Magnet", "Teleport to the loose ball (blatant)")
mBan:Slider({ Name = "Teleport range", Min = 15, Max = 200, Step = 5, Default = Fun.MagnetRange, Suffix = " st", Callback = function(v) Fun.MagnetRange = v end })

-- SETTINGS ---------------------------------------------------------------------------------------------------------------------
local tSet = win:Tab("Settings", { Section = "Client", Icon = 9 })
tSet:Section("Window")
tSet:Slider({ Name = "UI scale", Min = 0.7, Max = 1.4, Step = 0.05, Default = 1, Callback = function(v) win:SetScale(v) end })
tSet:Slider({ Name = "Blur behind the window", Min = 0, Max = 30, Step = 1, Default = 0, Callback = function(v) win:SetBlur(v) end })
tSet:Toggle({ Name = "Interface sounds", Default = true, Callback = function(v) Sfx.Enabled = v end })
tSet:Section("Theme")
local THEMES = {
	{ "Mono", UI.Palette().accent, UI.Palette().bg }, { "Aurora", Color3.fromRGB(139, 92, 246), Color3.fromRGB(11, 10, 22) },
	{ "Pitch", Color3.fromRGB(46, 204, 120), Color3.fromRGB(10, 18, 14) }, { "Ocean", Color3.fromRGB(52, 152, 219), Color3.fromRGB(10, 16, 26) },
	{ "Crimson", Color3.fromRGB(231, 76, 60), Color3.fromRGB(20, 11, 11) },
}
local themeNames = {}
for _, t in ipairs(THEMES) do themeNames[#themeNames + 1] = t[1] end
tSet:Choice({ Name = "Theme", Options = themeNames, Default = "Mono", Callback = function(v)
	for _, t in ipairs(THEMES) do
		if t[1] == v then win:ApplyPalette(UI.Palette(t[2], t[3])) end
	end
end })
tSet:Section("About")
tSet:Label({ Name = "Version", Value = VERSION })
tSet:Label({ Name = "Hide / show window", Value = "Right Shift" })
tSet:Label({ Name = "Event log", Value = "RagdollSoccer/log.txt" })

-- unload / autosave ----------------------------------------------------------------------------------------------------------------
local function save() if Config.Available then pcall(function() Config.Write("default", { v = 1, flags = win:GetConfig() }) end) end end
local function unload()
	pcall(save)
	alive = false
	Fun.Destroy(); Kick.Destroy(); Rules.Destroy(); Speed.Destroy(); Net.Destroy(); Log.Destroy()
	win:Destroy()
	env.__RagdollSoccer = nil
end
tSet:Button({ Name = "Unload", NoSave = true, Callback = unload })
env.__RagdollSoccer = unload

Fun.Start()

if Config.Available then
	local data = Config.Read("default")
	if data and data.flags then win:ApplyConfig(data.flags) end
	task.spawn(function()
		while alive do
			task.wait(5)
			save()
		end
	end)
end

table.insert(win.conns, UIS.InputBegan:Connect(function(i)
	if i.KeyCode == Enum.KeyCode.RightShift then win:Toggle(); return end
	if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or key:IsListening() then return end
	if key:Get() == i.KeyCode then mBan:Set(not mBan:Get()) end
end))

win:Notify("Ragdoll Soccer loaded  -  press Z to turn Ronaldini on", 4, "success")

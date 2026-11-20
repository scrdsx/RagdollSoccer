-- Ragdoll Soccer: entry point. One window, one module (Ronaldini) with everything inside its settings, and a small Settings tab.
local UIS = game:GetService("UserInputService")
local UI = __import("lib/ui")
local Sfx = __import("lib/sfx")
local Config = __import("lib/config")
local Log = __import("game/log")
local Net = __import("game/net")
local Rules = __import("game/rules")
local Speed = __import("game/speed")
local Input = __import("game/input")
local Kick = __import("game/kick")
local Bot = __import("game/bot")

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
local speedMult = 1.0
local sticky, accurate = true, true
local mBan

local function apply(on)
	Bot.SetEnabled(on)
	Kick.SetAim(on)
	Rules.SetAccurate(on and accurate)
	Rules.SetSticky(on and sticky)
	Speed.Set(on and speedMult or 1)
	win:Notify(on and "Ronaldini Banini ON" or "Ronaldini Banini off", 2)
	Log.add(on and "Ronaldini ON" or "Ronaldini off")
end

mBan = tMain:Module({ Name = "Ronaldini Banini", Default = false, Callback = apply })
local key = mBan:Keybind({ Name = "Toggle key", Default = Enum.KeyCode.Z })

mBan:Section("Mode")
mBan:Choice({ Name = "Play", Options = { "Auto play", "Manual (I move)" }, Default = "Auto play", Callback = function(v) Bot.Auto = v == "Auto play" end })
mBan:Toggle({ Name = "Sprint the whole time", Default = Bot.Sprint, Callback = function(v) Bot.Sprint = v end })
mBan:Toggle({ Name = "Steer round defenders", Default = Bot.Dodge, Callback = function(v) Bot.Dodge = v end })
mBan:Toggle({ Name = "Hand control back when I press WASD", Default = Bot.PauseOnKeys, Callback = function(v) Bot.PauseOnKeys = v end })
mBan:Slider({ Name = "Chase the ball up to", Min = 50, Max = 800, Step = 10, Default = Bot.ChaseRange, Suffix = " st", Callback = function(v) Bot.ChaseRange = v end })

mBan:Section("Shooting (silent aim)")
mBan:Choice({ Name = "Where in the goal", Options = Kick.Corners, Default = Kick.Corner, Callback = function(v) Kick.Corner = v end })
mBan:Choice({ Name = "Aim", Options = { "All kicks", "Shots only" }, Default = "All kicks", Callback = function(v) Kick.AllKicks = v == "All kicks" end })
mBan:Toggle({ Name = "Shoot by itself near the goal", Default = Bot.AutoShoot, Callback = function(v) Bot.AutoShoot = v end })
mBan:Slider({ Name = "Shoot from", Min = 12, Max = 90, Step = 1, Default = Bot.ShootDist, Suffix = " st", Callback = function(v) Bot.ShootDist = v end })
mBan:Slider({ Name = "Charge time", Min = 0.1, Max = 0.5, Step = 0.02, Default = Kick.Charge, Suffix = " s", Callback = function(v) Kick.Charge = v end })
mBan:Slider({ Name = "Max distance to the goal", Min = 30, Max = 250, Step = 5, Default = Kick.MaxDist, Suffix = " st", Callback = function(v) Kick.MaxDist = v end })

mBan:Section("Ball")
mBan:Toggle({ Name = "Perfect accuracy", Default = true, Callback = function(v) accurate = v; if mBan:Get() then Rules.SetAccurate(v) end end })
mBan:Toggle({ Name = "Sticky ball (wider pickup reach)", Default = true, Callback = function(v) sticky = v; if mBan:Get() then Rules.SetSticky(v) end end })
mBan:Slider({ Name = "Sticky reach", Min = 1, Max = 3.5, Step = 0.1, Default = Rules.StickyMult, Suffix = "x", Callback = function(v) Rules.StickyMult = v; if mBan:Get() and sticky then Rules.SetSticky(true, v) end end })

mBan:Section("Speed")
mBan:Slider({ Name = "Speed multiplier", Min = 1, Max = 3, Step = 0.05, Default = speedMult, Suffix = "x", Callback = function(v) speedMult = v; if mBan:Get() then Speed.Set(v) end end })

mBan:Section("Funny")
mBan:Toggle({ Name = "Spinbot", Default = false, Callback = function(v) Bot.Spin = v end })
mBan:Slider({ Name = "Spin speed", Min = 90, Max = 2400, Step = 30, Default = Bot.SpinRate, Suffix = " deg/s", Callback = function(v) Bot.SpinRate = v end })
mBan:Toggle({ Name = "Teleport to the ball (blatant)", Default = false, Callback = function(v) Bot.TP = v end })
mBan:Slider({ Name = "Teleport range", Min = 15, Max = 200, Step = 5, Default = Bot.TPRange, Suffix = " st", Callback = function(v) Bot.TPRange = v end })
tMain:Button({ Name = "Shoot now", NoSave = true, Callback = function() Kick.Shoot() end })

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
	Bot.Destroy(); Kick.Destroy(); Rules.Destroy(); Speed.Destroy(); Input.Destroy(); Net.Destroy(); Log.Destroy()
	win:Destroy()
	env.__RagdollSoccer = nil
end
tSet:Button({ Name = "Unload", NoSave = true, Callback = unload })
env.__RagdollSoccer = unload

Bot.Start()

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

win:Notify("Ragdoll Soccer loaded  -  press Z to start Ronaldini", 4, "success")

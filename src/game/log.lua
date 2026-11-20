-- Log: small event log written to RagdollSoccer/log.txt (about every 2 s). When something does not work, this file shows what the script saw and did.
local RunService = game:GetService("RunService")

local Log = { lines = {}, dirty = false }
local conn, acc = nil, 0

function Log.add(msg)
	local l = Log.lines
	l[#l + 1] = ("%s  %s"):format(os.date("%H:%M:%S"), tostring(msg))
	if #l > 300 then table.remove(l, 1) end
	Log.dirty = true
end

local function flush()
	if not Log.dirty or type(writefile) ~= "function" then return end
	Log.dirty = false
	pcall(function()
		if makefolder then pcall(makefolder, "RagdollSoccer") end
		writefile("RagdollSoccer/log.txt", table.concat(Log.lines, "\n"))
	end)
end

function Log.Start()
	if conn then return end
	conn = RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc >= 2 then acc = 0; flush() end
	end)
end

function Log.Destroy()
	flush()
	if conn then conn:Disconnect(); conn = nil end
end

return Log

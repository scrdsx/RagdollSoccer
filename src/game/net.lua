-- Net: one __namecall hook for the whole script. Modules register a handler for a remote's name; the handler gets the packed arguments and may return a
-- replacement packed argument table, or nil to leave the call alone. Only FireServer / InvokeServer are looked at.
local Net = { handlers = {}, hooked = false, Error = nil }
local oldNC

local function nc(self, ...)
	local m = getnamecallmethod()
	if (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance" then
		local n = self.Name
		for key, h in pairs(Net.handlers) do
			if n:find(key, 1, true) and not (key == "KickPlan" and n:find("Relay", 1, true)) then
				local packed = table.pack(...)
				local ok, res = pcall(h, packed, self)
				if ok and res then return oldNC(self, table.unpack(res, 1, res.n or packed.n)) end
				break
			end
		end
	end
	return oldNC(self, ...)
end

function Net.On(key, fn) Net.handlers[key] = fn end
function Net.Off(key) Net.handlers[key] = nil end

function Net.Start()
	if Net.hooked then return true end
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then Net.Error = "executor has no hookmetamethod"; return false end
	local ok, err = pcall(function() oldNC = hookmetamethod(game, "__namecall", newcclosure and newcclosure(nc) or nc) end)
	Net.hooked = ok
	if not ok then Net.Error = tostring(err) end
	return ok
end

function Net.Destroy() Net.handlers = {} end

return Net

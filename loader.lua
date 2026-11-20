-- Ragdoll Soccer loader. raw.githubusercontent.com keeps a branch cached for minutes, so the newest commit is looked up first and the bundle is fetched by that
-- commit (those links never go stale). One request for the code: dist/RagdollSoccer.lua is the whole script in one file.
local HttpService = game:GetService("HttpService")
local OWNER, REPO = "scrdsx", "RagdollSoccer"

local sha
pcall(function()
	local body = game:HttpGet(("https://api.github.com/repos/%s/%s/commits/main"):format(OWNER, REPO))
	sha = HttpService:JSONDecode(body).sha
end)

local url = ("https://raw.githubusercontent.com/%s/%s/%s/dist/RagdollSoccer.lua?t=%d"):format(OWNER, REPO, sha or "main", os.time())
local src = game:HttpGet(url)
local fn, err = loadstring(src, "=RagdollSoccer")
assert(fn, "RagdollSoccer: " .. tostring(err))
return fn()

-- VD_Probe.lua | perekam tampilan dan perilaku game (bukan cuma kode)
-- By: @texx-breaker
--
-- Yang direkam ke VD_Probe.txt:
--  * perubahan tampilan di layar (jarum skill check, tombol parry, cooldown, teks, putaran, visible)
--  * tombol dan elemen penting beserta script yang mengurusnya
--  * sentuhan atau tombol yang lo tekan, aksi (ContextAction) yang sedang mengunci input
--  * status karakter: WalkSpeed, PlatformStand, Anchored, controlsEnabled, atribut
--  * remote yang dikirim (GAME = dari game, EXEC = dari script lain) dan event dari server
-- Pakai panel kecil di kanan atas: Tandai (catat momen penting), Rekam ON/OFF, Selesai.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

if env.VD_PROBE_STOP then pcall(env.VD_PROBE_STOP) end

local FILE = "VD_Probe.txt"
local MAX_LINES = 15000
local INTEREST = {"parry", "dagger", "skill", "check", "crouch", "jongkok", "sprint", "vault", "repair", "heal",
	"item", "needle", "pointer", "zone", "perfect", "cooldown", "action", "button", "arrow", "indicator"}
local SPAM = {"pushremote", "updatecharacterlook", "getping", "echovoid", "camlook", "emotehandler"}
local REMOTE_WORDS = {"skill", "parry", "repair", "heal", "vault", "crouch", "dagger", "traversal",
	"changeattribute", "generator", "healing", "items", "window", "fastvault"}

local t0 = os.clock()
local buf, total, recording, alive = {}, 0, true, true
local conns = {}
local function connect(sig, fn)
	local c = sig:Connect(fn)
	conns[#conns + 1] = c
	return c
end

if writefile then pcall(writefile, FILE, "") end

local function log(kind, text)
	if not recording or total >= MAX_LINES then return end
	total = total + 1
	buf[#buf + 1] = string.format("[%.2f][%s] %s", os.clock() - t0, kind, text)
end

local function flush()
	if #buf == 0 or not appendfile then return end
	local chunk = table.concat(buf, "\n") .. "\n"
	buf = {}
	pcall(appendfile, FILE, chunk)
end

local function short(o)
	local ok, n = pcall(function() return o:GetFullName() end)
	if not ok then return tostring(o) end
	n = n:gsub("^Players%.[^.]+%.PlayerGui%.", "PG.")
	return n
end

local function ser(v, d)
	d = d or 0
	local t = typeof(v)
	if t == "string" then return '"' .. v:sub(1, 40) .. '"' end
	if t == "Instance" then return short(v) end
	if t == "table" then
		if d >= 2 then return "{...}" end
		local out, n = {}, 0
		for k, x in pairs(v) do
			n = n + 1
			if n > 10 then out[#out + 1] = "..." break end
			out[#out + 1] = tostring(k) .. "=" .. ser(x, d + 1)
		end
		return "{" .. table.concat(out, ", ") .. "}"
	end
	return tostring(v)
end

local function hasWord(s, words)
	s = s:lower()
	for _, w in ipairs(words) do
		if s:find(w, 1, true) then return true end
	end
	return false
end

local function interesting(d)
	if hasWord(d.Name, INTEREST) then return true end
	local p = d.Parent
	if p and p ~= game and hasWord(p.Name, INTEREST) then return true end
	return false
end

-- ===== siapa yang memegang sebuah sinyal =====
local function owner(fn)
	local ok, e = pcall(getfenv, fn)
	if ok and type(e) == "table" then
		local ok2, s = pcall(function() return e.script end)
		if ok2 and typeof(s) == "Instance" then return short(s) end
	end
	if debug and debug.info then
		local ok3, src = pcall(debug.info, fn, "s")
		if ok3 and src then return tostring(src) end
	end
	return "?"
end

local function owners(sig)
	if not getconnections then return nil end
	local ok, list = pcall(getconnections, sig)
	if not ok or not list then return nil end
	local out = {}
	for _, c in ipairs(list) do
		local fn = nil
		pcall(function() fn = c.Function end)
		out[#out + 1] = fn and owner(fn) or "?"
	end
	return out
end

-- ===== kontrol karakter =====
local function getControls()
	local ps = lp:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if not pm then return nil end
	local ok, mod = pcall(require, pm)
	if not ok or type(mod) ~= "table" or not mod.GetControls then return nil end
	local ok2, ctrl = pcall(mod.GetControls, mod)
	if ok2 then return ctrl end
	return nil
end

-- ===== snapshot isi layar dan pemegang input =====
local function snapshot(tag)
	log("SNAP", tag)
	local pg = lp:FindFirstChild("PlayerGui")
	if pg then
		local n = 0
		for _, d in ipairs(pg:GetDescendants()) do
			if d:IsA("GuiObject") and interesting(d) then
				n = n + 1
				if n > 70 then break end
				local info = string.format("%s %s vis=%s rot=%.1f abs=(%.0f,%.0f %.0fx%.0f)", d.ClassName, short(d),
					tostring(d.Visible), d.Rotation, d.AbsolutePosition.X, d.AbsolutePosition.Y, d.AbsoluteSize.X, d.AbsoluteSize.Y)
				if d:IsA("TextLabel") or d:IsA("TextButton") then info = info .. " text=" .. d.Text:sub(1, 30) end
				if d:IsA("ImageLabel") or d:IsA("ImageButton") then info = info .. " img=" .. d.Image:sub(1, 40) end
				log("GUIOBJ", info)
				if d:IsA("GuiButton") then
					for _, sn in ipairs({"Activated", "MouseButton1Down", "MouseButton1Click", "TouchTap"}) do
						local cs = owners(d[sn])
						if cs and #cs > 0 then log("CONN", short(d) .. "." .. sn .. " -> " .. table.concat(cs, " | ")) end
					end
				end
				local cs = owners(d.InputBegan)
				if cs and #cs > 0 then log("CONN", short(d) .. ".InputBegan -> " .. table.concat(cs, " | ")) end
			end
		end
	end
	for _, sn in ipairs({"InputBegan", "InputEnded", "TouchTap", "TouchStarted"}) do
		local cs = owners(UIS[sn])
		if cs then
			local names = {}
			for _, s in ipairs(cs) do
				if s ~= "?" then names[#names + 1] = s end
			end
			log("UIS", sn .. " " .. #cs .. " koneksi: " .. table.concat(names, " | "):sub(1, 700))
		end
	end
	pcall(function()
		for name, info in pairs(CAS:GetAllBoundActionInfo()) do
			local types = {}
			for _, t in ipairs(info.inputTypes or {}) do types[#types + 1] = tostring(t) end
			log("CAS", name .. " prio=" .. tostring(info.priority) .. " input=" .. table.concat(types, ","))
		end
	end)
	for _, root in ipairs({lp:FindFirstChild("PlayerGui"), lp:FindFirstChild("PlayerScripts"), lp.Character}) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("LocalScript") and hasWord(d.Name, {"skill", "parry", "dagger", "repair", "heal", "crouch", "item"}) then
					log("SCRIPT", short(d) .. " disabled=" .. tostring(d.Disabled))
				end
			end
		end
	end
end

-- ===== perubahan tampilan =====
local tracked = setmetatable({}, {__mode = "k"})
local function propsOf(d)
	local p = {
		vis = d.Visible,
		rot = math.floor(d.Rotation * 2 + 0.5) / 2,
		size = tostring(d.Size),
		pos = tostring(d.Position),
		bt = math.floor(d.BackgroundTransparency * 20 + 0.5) / 20,
	}
	if d:IsA("TextLabel") or d:IsA("TextButton") then p.text = d.Text end
	if d:IsA("ImageLabel") or d:IsA("ImageButton") then
		p.img = d.Image
		p.it = math.floor(d.ImageTransparency * 20 + 0.5) / 20
	end
	return p
end

local function diffGui()
	local pg = lp:FindFirstChild("PlayerGui")
	if not pg then return end
	local lines = 0
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("GuiObject") then
			local cur = propsOf(d)
			local old = tracked[d]
			if not old then
				tracked[d] = {p = cur, n = 0}
			else
				if old.n < 150 and lines < 30 then
					for k, v in pairs(cur) do
						if old.p[k] ~= v then
							lines = lines + 1
							old.n = old.n + 1
							log("GUI", short(d) .. " " .. k .. " " .. tostring(old.p[k]):sub(1, 30) .. " -> " .. tostring(v):sub(1, 30))
						end
					end
				end
				old.p = cur
			end
		end
	end
end

-- ===== status karakter =====
local hstate = {}
local function pollChar()
	local c = lp.Character
	if not c then return end
	local hum = c:FindFirstChildOfClass("Humanoid")
	local root = c:FindFirstChild("HumanoidRootPart")
	local cur = {}
	if hum then
		cur.WalkSpeed = string.format("%.2f", hum.WalkSpeed)
		cur.Jump = hum.UseJumpPower and string.format("%.1f", hum.JumpPower) or string.format("%.1f", hum.JumpHeight)
		cur.PlatformStand = tostring(hum.PlatformStand)
		cur.Sit = tostring(hum.Sit)
		cur.AutoRotate = tostring(hum.AutoRotate)
		cur.Bergerak = hum.MoveDirection.Magnitude > 0.1 and "ya" or "tidak"
		cur.State = tostring(hum:GetState())
	end
	if root then cur.Anchored = tostring(root.Anchored) end
	local ctrl = getControls()
	if ctrl then
		local ok, v = pcall(function() return ctrl.controlsEnabled end)
		if ok then cur.controlsEnabled = tostring(v) end
	end
	for k, v in pairs(cur) do
		if hstate[k] ~= v then
			log("CHAR", k .. "=" .. v)
			hstate[k] = v
		end
	end
end

local boundSeen = {}
local function pollBound()
	local now = {}
	local ok = pcall(function()
		for name, info in pairs(CAS:GetAllBoundActionInfo()) do
			now[name] = tostring(info.priority)
		end
	end)
	if not ok then return end
	for name, pr in pairs(now) do
		if boundSeen[name] == nil then log("CAS+", name .. " prio=" .. pr) end
	end
	for name in pairs(boundSeen) do
		if now[name] == nil then log("CAS-", name) end
	end
	boundSeen = now
end

local function watchChar(c)
	for k, v in pairs(c:GetAttributes()) do log("ATTR", k .. "=" .. tostring(v)) end
	connect(c.AttributeChanged, function(k)
		if k == "CamLook" or k == "chasereward" then return end
		log("ATTR", k .. "=" .. tostring(c:GetAttribute(k)))
	end)
end
if lp.Character then task.spawn(watchChar, lp.Character) end
connect(lp.CharacterAdded, function(c) task.spawn(watchChar, c) end)

-- ===== input =====
connect(UIS.InputBegan, function(i, gpe)
	local k = i.KeyCode and i.KeyCode.Name or "?"
	log("INPUT+", i.UserInputType.Name .. " " .. k .. string.format(" (%.0f,%.0f)", i.Position.X, i.Position.Y) .. (gpe and " gui" or ""))
end)
connect(UIS.InputEnded, function(i, gpe)
	local k = i.KeyCode and i.KeyCode.Name or "?"
	log("INPUT-", i.UserInputType.Name .. " " .. k .. (gpe and " gui" or ""))
end)

-- ===== remote keluar =====
env.VD_PROBE_HANDLER = function(rem, method, src, args)
	local full = short(rem)
	local low = full:lower()
	if hasWord(low, SPAM) or not hasWord(low, REMOTE_WORDS) then return end
	local parts = {}
	for i = 1, args.n do parts[i] = ser(args[i]) end
	log("REMOTE-" .. src, method .. " " .. full .. " (" .. table.concat(parts, ", ") .. ")")
end

if not env.VD_PROBE_HOOKED then
	if hookmetamethod and getnamecallmethod and newcclosure then
		env.VD_PROBE_HOOKED = true
		local old
		old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local m = getnamecallmethod()
			if m == "FireServer" or m == "InvokeServer" then
				local h = env.VD_PROBE_HANDLER
				if h and typeof(self) == "Instance" then
					local src = (checkcaller and checkcaller()) and "EXEC" or "GAME"
					task.spawn(h, self, m, src, table.pack(...))
				end
			end
			return old(self, ...)
		end))
	else
		log("INFO", "hookmetamethod tidak ada: remote keluar tidak terekam")
	end
end

-- ===== event dari server =====
local remotes = RS:FindFirstChild("Remotes")
if remotes then
	local want = {skillcheckevent = true, skillcheckfailevent = true, parryresult = true, skillcheckvalidated = true}
	for _, d in ipairs(remotes:GetDescendants()) do
		local n = d.Name:lower()
		if want[n] then
			local sig = nil
			if d:IsA("RemoteEvent") then
				sig = d.OnClientEvent
			elseif d:IsA("BindableEvent") then
				sig = d.Event
			end
			if sig then
				connect(sig, function(...)
					local a = table.pack(...)
					local parts = {}
					for i = 1, a.n do parts[i] = ser(a[i]) end
					log("SERVER", short(d) .. " (" .. table.concat(parts, ", ") .. ")")
					if n == "skillcheckevent" then
						task.delay(0.25, function() snapshot("skill check muncul") end)
						task.delay(1.0, function() snapshot("skill check +1 detik") end)
					end
				end)
			end
		end
	end
end

-- ===== info awal =====
log("INFO", "PlaceId=" .. game.PlaceId .. " touch=" .. tostring(UIS.TouchEnabled) .. " keyboard=" .. tostring(UIS.KeyboardEnabled))
log("INFO", "getconnections=" .. tostring(getconnections ~= nil) .. " firesignal=" .. tostring(firesignal ~= nil)
	.. " hookmetamethod=" .. tostring(hookmetamethod ~= nil) .. " checkcaller=" .. tostring(checkcaller ~= nil))
local pgInit = lp:FindFirstChild("PlayerGui")
if pgInit then
	for _, g in ipairs(pgInit:GetChildren()) do
		if g:IsA("ScreenGui") then log("INFO", "ScreenGui " .. g.Name .. " enabled=" .. tostring(g.Enabled)) end
	end
end
task.spawn(snapshot, "awal")

-- ===== loop =====
local accGui, accChar, accBound, accFlush = 0, 0, 0, 0
connect(RunService.Heartbeat, function(dt)
	if not alive then return end
	accGui = accGui + dt
	accChar = accChar + dt
	accBound = accBound + dt
	accFlush = accFlush + dt
	if recording then
		if accGui >= 0.15 then
			accGui = 0
			pcall(diffGui)
		end
		if accChar >= 0.1 then
			accChar = 0
			pcall(pollChar)
		end
		if accBound >= 0.25 then
			accBound = 0
			pcall(pollBound)
		end
	end
	if accFlush >= 3 then
		accFlush = 0
		flush()
	end
end)

-- ===== panel kecil =====
local parent = (gethui and gethui()) or CoreGui
local oldGui = parent:FindFirstChild("VDProbe")
if oldGui then oldGui:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "VDProbe"
gui.ResetOnSpawn = false
gui.DisplayOrder = 200
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(210, 118)
frame.Position = UDim2.new(1, -226, 0, 70)
frame.BackgroundColor3 = Color3.fromRGB(10, 13, 11)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
local fs = Instance.new("UIStroke")
fs.Color = Color3.fromRGB(33, 44, 37)
fs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
fs.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 26)
title.Position = UDim2.fromOffset(10, 2)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamMedium
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(224, 232, 226)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "VD Probe | 0 baris"
title.Parent = frame

local function btn(text, x, y, w, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, 30)
	b.Position = UDim2.fromOffset(x, y)
	b.BackgroundColor3 = Color3.fromRGB(26, 34, 29)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 12
	b.TextColor3 = Color3.fromRGB(224, 232, 226)
	b.Text = text
	b.AutoButtonColor = false
	b.Parent = frame
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
	b.MouseButton1Click:Connect(function() cb(b) end)
	return b
end

btn("Tandai", 10, 32, 90, function()
	log("MARK", "tombol Tandai ditekan")
	snapshot("tandai")
end)
btn("Rekam: ON", 110, 32, 90, function(b)
	recording = not recording
	b.Text = recording and "Rekam: ON" or "Rekam: OFF"
	if not recording then flush() end
end)
local function stop()
	if not alive then return end
	alive = false
	log("INFO", "selesai")
	recording = true
	flush()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	env.VD_PROBE_HANDLER = nil
	pcall(function() gui:Destroy() end)
	env.VD_PROBE_STOP = nil
end
btn("Selesai dan simpan", 10, 72, 190, function() stop() end)
env.VD_PROBE_STOP = stop

-- geser panel
do
	local dragging, startPos, startFrame = false, nil, nil
	connect(title.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startPos = i.Position
			startFrame = frame.Position
			connect(i.Changed, function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	connect(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startPos
			frame.Position = UDim2.new(startFrame.X.Scale, startFrame.X.Offset + d.X, startFrame.Y.Scale, startFrame.Y.Offset + d.Y)
		end
	end)
end

task.spawn(function()
	while alive do
		title.Text = "VD Probe | " .. total .. " baris"
		task.wait(0.5)
	end
end)

print("[VD] Probe jalan. Hasil di " .. FILE)

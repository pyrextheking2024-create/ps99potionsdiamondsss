-- ANGELUS + SMALL PETS AUTO FARM  (single file: key screen + farm menu)
--
-- 1. Execute this script.
-- 2. Enter a key. The first device that uses a key gets locked to its HWID.
-- 3. The farm menu opens.
--
-- REMOTES: equip / unequip are ReplicatedStorage:GetChildren()[146] / [147]
-- (FALLBACK_EQUIP_INDEX / FALLBACK_UNEQUIP_INDEX inside StartMenu).
-- If a game update moves them and equipping stops working: SETUP tab ->
-- CALIBRATE REMOTES, equip one pet by hand, then unequip one pet by hand.
-- The two index numbers appear in Output (F9) - put them in the constants.

local KEY_FILE = "angelus_key.txt"
local BIND_FILE = "angelus_bind.json"

local VALID_KEYS = {
    ["king-a7x92-m4q81"] = true,
    ["king-z83kp-92mx5"] = true,
    ["king-4nq72-x8b31"] = true,
    ["king-p9w42-k6d83"] = true,
    ["king-7xm21-q4v95"] = true,
    ["king-b82zn-5kq73"] = true,
    ["king-m4x91-t8p26"] = true,
    ["king-92kfz-7w3n5"] = true,
    ["king-q81v6-m29xp"] = true,
    ["king-5p3x8-n7k42"] = true,
}

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer

-- ===================== FARM MENU =====================

local function StartMenu()
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local UIS = game:GetService("UserInputService")

    local Player = Players.LocalPlayer

    local Library = require(
        RS:WaitForChild("Framework"):WaitForChild("Library")
    )

    repeat task.wait() until Library.Loaded

    local Coins = Library.Things:WaitForChild("Coins")

    -- CONFIG

    local SWITCH_HP = 1200000
    local TARGET_HP = 67500000
    local HP_TOLERANCE = 150000

    -- Small pets: only coins closer than this (studs) are targeted,
    -- unless the coin is a present that Angelus already brought under SWITCH_HP.
    local MAX_DISTANCE = 250
    local STUCK_TIMEOUT = 3          -- small pets: seconds without damage before re-selecting
    local ANGELUS_STUCK_TIMEOUT = 10 -- Angelus: seconds without damage before re-selecting
    local MAX_RESELECTS = 3          -- after this many re-selects, skip the coin
    local DEBUG = false              -- true = print every step in Output

    -- Stats tab: where diamonds / potions are read from (Library.Save.Get())
    local DIAMONDS_KEY = "Diamonds"
    local POTIONS_KEY = nil         -- nil = auto-detect a save key that contains "potion"

    local ANGELUS = "idd236f09e7d8d4f728bdf32b8bc1f367f"

    local SMALL_PETS = {
        "id33a10fe5157345d1ac9ae7b5b73b83d5",
        "id6e5014caa33242c3b4a2a1217c47bec7",
        "id5905137f7e0c4a6f8d4f06a09b4810f9",
        "idb2237bdbbb414aafaa9d6262e874b9df",
        "id62de7109c4114f74a2a49e40302bf2c3",
        "id4d78c3c3b67441fc93bb851717a7abcd",
        "idee0ca07d9f7b40c782507c4f9544d443",
        "idfca4e98c04c3419e90a39548797d801e",
        "id381898ab93e943df998e6816c7e5f96f",
    }

    -- REMOTES (this account: equip = child 146 from Cobalt, unequip = child 147 - check it with Cobalt)
    local FALLBACK_EQUIP_INDEX = 146
    local FALLBACK_UNEQUIP_INDEX = 147

    local EquipRemote
    local UnequipRemote

    do
        local children = RS:GetChildren()
        local e = children[FALLBACK_EQUIP_INDEX]
        local u = children[FALLBACK_UNEQUIP_INDEX]

        if e and e:IsA("RemoteFunction") then EquipRemote = e end
        if u and u:IsA("RemoteFunction") then UnequipRemote = u end

        if not (EquipRemote and UnequipRemote) then
            warn("[AUTO FARM] FALLBACK indexes are not RemoteFunctions (game updated?) - use CALIBRATE REMOTES")
        end
    end

    -- STATE

    local enabled = false
    local running = false

    -- Presents that Angelus already brought below SWITCH_HP
    local presents = {}

    -- GUI

    local TweenService = game:GetService("TweenService")

    local THEME = {
        bg = Color3.fromRGB(14, 16, 24),
        title = Color3.fromRGB(19, 22, 33),
        panel = Color3.fromRGB(24, 28, 41),
        border = Color3.fromRGB(42, 48, 68),
        text = Color3.fromRGB(235, 238, 246),
        muted = Color3.fromRGB(135, 144, 168),
        accent = Color3.fromRGB(86, 128, 255),
        accent2 = Color3.fromRGB(155, 92, 255),
        green = Color3.fromRGB(35, 155, 90),
        red = Color3.fromRGB(180, 55, 65),
        yellow = Color3.fromRGB(255, 200, 100),
        blue = Color3.fromRGB(110, 190, 255),
    }

    local function New(class, props, parent)
        local inst = Instance.new(class)

        for k, v in pairs(props) do
            inst[k] = v
        end

        inst.Parent = parent
        return inst
    end

    local function Round(inst, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius)
        c.Parent = inst
        return c
    end

    local function Stroke(inst, color, thickness)
        local s = Instance.new("UIStroke")
        s.Color = color
        s.Thickness = thickness
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = inst
        return s
    end

    local function Gradient(inst, c1, c2)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(c1, c2)
        g.Parent = inst
        return g
    end

    local function Tween(inst, time, props)
        TweenService:Create(
            inst,
            TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            props
        ):Play()
    end

    local FRAME_W = 520
    local FRAME_H = 440
    local PAGE_Y = 90
    local PAGE_H = FRAME_H - PAGE_Y - 36

    local ui = { tabs = {}, pages = {}, t = {} }

    do
        local old = Player:WaitForChild("PlayerGui"):FindFirstChild("AngelusAutoFarm")

        if old then
            old:Destroy()
        end
    end

    local gui = New("ScreenGui", {
        Name = "AngelusAutoFarm",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, Player:WaitForChild("PlayerGui"))

    local frame = New("Frame", {
        Size = UDim2.fromOffset(FRAME_W, FRAME_H),
        Position = UDim2.new(0.5, -FRAME_W / 2, 0.5, -FRAME_H / 2),
        BackgroundColor3 = THEME.bg,
        BorderSizePixel = 0,
        Active = true,
        ClipsDescendants = true,
    }, gui)

    Round(frame, 14)
    Stroke(frame, THEME.border, 1.5)

    -- title bar

    local titleBar = New("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundColor3 = THEME.title,
        BorderSizePixel = 0,
    }, frame)

    ui.dot = New("Frame", {
        Size = UDim2.fromOffset(10, 10),
        Position = UDim2.fromOffset(16, 18),
        BackgroundColor3 = THEME.muted,
        BorderSizePixel = 0,
    }, titleBar)

    Round(ui.dot, 5)

    local header = New("TextLabel", {
        Size = UDim2.new(1, -90, 1, 0),
        Position = UDim2.fromOffset(36, 0),
        BackgroundTransparency = 1,
        Text = "ANGELUS AUTO FARM",
        TextColor3 = THEME.text,
        Font = Enum.Font.GothamBold,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, titleBar)

    local close = New("TextButton", {
        Size = UDim2.fromOffset(28, 28),
        Position = UDim2.new(1, -40, 0, 9),
        BackgroundColor3 = THEME.red,
        Text = "X",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
    }, titleBar)

    Round(close, 7)

    Gradient(New("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        Position = UDim2.fromOffset(0, 46),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, frame), THEME.accent, THEME.accent2)

    -- tabs

    local tabBar = New("Frame", {
        Position = UDim2.fromOffset(0, 48),
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = THEME.title,
        BorderSizePixel = 0,
    }, frame)

    ui.indicator = New("Frame", {
        Size = UDim2.new(1 / 3, -24, 0, 3),
        Position = UDim2.new(0, 12, 1, -3),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, tabBar)

    Round(ui.indicator, 2)
    Gradient(ui.indicator, THEME.accent, THEME.accent2)

    for i, name in ipairs({ "FARM", "STATS", "SETUP" }) do
        ui.tabs[i] = New("TextButton", {
            Position = UDim2.new((i - 1) / 3, 0, 0, 0),
            Size = UDim2.new(1 / 3, 0, 1, -3),
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = name,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = THEME.muted,
        }, tabBar)

        ui.pages[i] = New("Frame", {
            Position = UDim2.fromOffset(0, PAGE_Y),
            Size = UDim2.new(1, 0, 0, PAGE_H),
            BackgroundTransparency = 1,
            Visible = (i == 1),
        }, frame)
    end

    local function ShowTab(index)
        for i = 1, 3 do
            ui.pages[i].Visible = (i == index)
            ui.tabs[i].TextColor3 = (i == index) and THEME.text or THEME.muted
        end

        Tween(ui.indicator, 0.2, { Position = UDim2.new((index - 1) / 3, 12, 1, -3) })
    end

    for i = 1, 3 do
        ui.tabs[i].MouseButton1Click:Connect(function()
            ShowTab(i)
        end)
    end

    ShowTab(1)

    -- footer (always shows the latest status, whichever tab is open)

    local footerBar = New("Frame", {
        Position = UDim2.fromOffset(0, FRAME_H - 36),
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = THEME.title,
        BorderSizePixel = 0,
    }, frame)

    ui.footer = New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16, 0),
        Size = UDim2.new(1, -32, 1, 0),
        Text = "Ready",
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, footerBar)

    -- widgets

    local function MakeCard(parent, y, color)
        local card = New("Frame", {
            Position = UDim2.fromOffset(12, y),
            Size = UDim2.new(1, -24, 0, 38),
            BackgroundColor3 = THEME.panel,
            BorderSizePixel = 0,
        }, parent)

        Round(card, 9)
        Stroke(card, THEME.border, 1)

        return New("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(14, 0),
            Size = UDim2.new(1, -28, 1, 0),
            Text = "",
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = color,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)
    end

    -- stat tile: 3 per row. Returns the value label.
    local function MakeTile(parent, col, y, caption, color)
        local w = (FRAME_W - 24 - 16) / 3

        local f = New("Frame", {
            Position = UDim2.fromOffset(12 + col * (w + 8), y),
            Size = UDim2.fromOffset(w, 76),
            BackgroundColor3 = THEME.panel,
            BorderSizePixel = 0,
        }, parent)

        Round(f, 10)
        Stroke(f, THEME.border, 1)

        Round(New("Frame", {
            Size = UDim2.new(1, -24, 0, 2),
            Position = UDim2.fromOffset(12, 0),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, f), 1)

        New("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(12, 10),
            Size = UDim2.new(1, -24, 0, 14),
            Text = caption,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = THEME.muted,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, f)

        return New("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(12, 28),
            Size = UDim2.new(1, -24, 0, 38),
            Text = "0",
            Font = Enum.Font.GothamBold,
            TextSize = 22,
            TextColor3 = color,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, f)
    end

    -- FARM page

    local toggle = New("TextButton", {
        Position = UDim2.fromOffset(12, 10),
        Size = UDim2.new(1, -24, 0, 48),
        BackgroundColor3 = THEME.green,
        AutoButtonColor = false,
        Text = "START FARM",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 16,
    }, ui.pages[1])

    Round(toggle, 10)

    local status = MakeCard(ui.pages[1], 68, THEME.text)
    status.Text = "Status: Stopped"

    local petStatus = MakeCard(ui.pages[1], 112, THEME.blue)
    petStatus.Text = "Pets: None"

    local hpStatus = MakeCard(ui.pages[1], 156, THEME.yellow)
    hpStatus.Text = "Present HP: Waiting"

    ui.t.miniPresents = MakeTile(ui.pages[1], 0, 206, "PRESENTS DESTROYED", THEME.green)
    ui.t.miniCycles = MakeTile(ui.pages[1], 1, 206, "CYCLES", THEME.accent)
    ui.t.miniDph = MakeTile(ui.pages[1], 2, 206, "DIAMONDS / HOUR", THEME.blue)

    -- STATS page

    ui.t.presents = MakeTile(ui.pages[2], 0, 10, "PRESENTS DESTROYED", THEME.green)
    ui.t.cycles = MakeTile(ui.pages[2], 1, 10, "CYCLES", THEME.accent)
    ui.t.uptime = MakeTile(ui.pages[2], 2, 10, "FARM TIME", THEME.text)

    ui.t.diamonds = MakeTile(ui.pages[2], 0, 94, "DIAMONDS EARNED", THEME.blue)
    ui.t.dph = MakeTile(ui.pages[2], 1, 94, "DIAMONDS / HOUR", THEME.blue)
    ui.t.dpc = MakeTile(ui.pages[2], 2, 94, "DIAMONDS / CYCLE", THEME.blue)

    ui.t.potions = MakeTile(ui.pages[2], 0, 178, "POTIONS GAINED", THEME.accent2)
    ui.t.ptph = MakeTile(ui.pages[2], 1, 178, "POTIONS / HOUR", THEME.accent2)
    ui.t.pph = MakeTile(ui.pages[2], 2, 178, "PRESENTS / HOUR", THEME.green)

    ui.resetBtn = New("TextButton", {
        Position = UDim2.fromOffset(12, 262),
        Size = UDim2.new(1, -24, 0, 38),
        BackgroundColor3 = THEME.panel,
        AutoButtonColor = false,
        Text = "RESET STATS",
        TextColor3 = THEME.muted,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
    }, ui.pages[2])

    Round(ui.resetBtn, 9)
    Stroke(ui.resetBtn, THEME.border, 1)

    -- SETUP page

    local calibrateBtn = New("TextButton", {
        Position = UDim2.fromOffset(12, 10),
        Size = UDim2.new(1, -24, 0, 40),
        BackgroundColor3 = Color3.fromRGB(60, 90, 150),
        AutoButtonColor = false,
        Text = "CALIBRATE REMOTES",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
    }, ui.pages[3])

    Round(calibrateBtn, 9)

    New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 100),
        Size = UDim2.new(1, -28, 0, 40),
        Text = "Only needed after a game update. Press CALIBRATE, EQUIP a pet by hand, then UNEQUIP a pet by hand (keep one slot free). Output (F9) prints the two index numbers. Or type them above and press APPLY.",
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = THEME.muted,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, ui.pages[3])

    ui.printKeysBtn = New("TextButton", {
        Position = UDim2.fromOffset(12, 150),
        Size = UDim2.new(1, -24, 0, 34),
        BackgroundColor3 = THEME.panel,
        AutoButtonColor = false,
        Text = "PRINT SAVE KEYS (Output) - helps find diamonds / potions",
        TextColor3 = THEME.muted,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
    }, ui.pages[3])

    Round(ui.printKeysBtn, 9)
    Stroke(ui.printKeysBtn, THEME.border, 1)

    ui.trackInfo = New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 194),
        Size = UDim2.new(1, -28, 0, 40),
        Text = "Diamonds: not read yet   |   Potions: not read yet",
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = THEME.muted,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, ui.pages[3])

    ui.listBtn = New("TextButton", {
        Position = UDim2.fromOffset(12, 240),
        Size = UDim2.new(1, -24, 0, 34),
        BackgroundColor3 = THEME.panel,
        AutoButtonColor = false,
        Text = "LIST REMOTE FUNCTIONS (Output, no hook, no lag)",
        TextColor3 = THEME.muted,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
    }, ui.pages[3])

    Round(ui.listBtn, 9)
    Stroke(ui.listBtn, THEME.border, 1)

    local function SetStatus(value)
        status.Text = "Status: " .. value
        ui.footer.Text = value

        local low = string.lower(value)
        local color = THEME.muted

        if string.find(low, "error", 1, true)
            or string.find(low, "fail", 1, true)
            or string.find(low, "missing", 1, true)
            or string.find(low, "not a ", 1, true) then
            color = Color3.fromRGB(235, 87, 87)
        elseif string.find(low, "calibrating", 1, true)
            or string.find(low, "equip found", 1, true)
            or string.find(low, "re-select", 1, true)
            or string.find(low, "skipped", 1, true)
            or string.find(low, "nothing detected", 1, true) then
            color = THEME.yellow
        elseif string.find(low, "destroyed", 1, true)
            or string.find(low, "ready", 1, true)
            or string.find(low, "calibrated", 1, true)
            or string.find(low, "applied", 1, true) then
            color = Color3.fromRGB(46, 204, 113)
        end

        ui.footer.TextColor3 = color

        if DEBUG then
            print("[AUTO FARM] " .. value)
        end
    end

    local function SetPet(value)
        petStatus.Text = "Pets: " .. value
        if DEBUG then print("[AUTO FARM PETS] " .. value) end
    end

    local function Debug(...)
        if DEBUG then
            print("[AUTO FARM DEBUG]", ...)
        end
    end

    -- CALIBRATION (fallback only)
    -- The hook is installed only when you press CALIBRATE. While calibration
    -- is off it is a plain pass-through (no lag). The first pet call it sees
    -- is the EQUIP remote, the second (different remote) is UNEQUIP.

    local calibrating = 0 -- 0 = off, 1 = waiting for equip, 2 = waiting for unequip
    local calibToken = 0
    local prevEquip
    local prevUnequip
    local hookInstalled = false
    local oldNamecall

    local function RemoteIndex(remote)
        return tostring(table.find(RS:GetChildren(), remote))
    end

    local function Learn(remote)
        if calibrating == 0 then return end

        if calibrating == 1 then
            EquipRemote = remote
            calibrating = 2
            print("[CALIBRATE] EQUIP remote index=" .. RemoteIndex(remote))
            SetStatus("Equip found - now UNEQUIP a pet by hand")
        elseif remote ~= EquipRemote then
            UnequipRemote = remote
            calibrating = 0
            print("[CALIBRATE] UNEQUIP remote index=" .. RemoteIndex(remote))
            print("[CALIBRATE] DONE - put the two index numbers in FALLBACK_EQUIP_INDEX / FALLBACK_UNEQUIP_INDEX")
            SetStatus("Calibrated - press START")
        end
    end

    local function InstallHook()
        if hookInstalled then return true end
        if not (hookmetamethod and getnamecallmethod) then return false end

        local wrap = newcclosure or function(f) return f end

        local ok = pcall(function()
            oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
                if calibrating == 0 then
                    return oldNamecall(self, ...)
                end

                local method = getnamecallmethod()

                if method == "InvokeServer"
                    and typeof(self) == "Instance"
                    and self.ClassName == "RemoteFunction" then

                    local first = ...

                    if type(first) == "string" and string.sub(first, 1, 2) == "id" then
                        task.defer(Learn, self)
                    end
                end

                if setnamecallmethod then
                    setnamecallmethod(method)
                end

                return oldNamecall(self, ...)
            end))
        end)

        hookInstalled = ok
        return ok
    end

    local function StartCalibration()
        if enabled then
            SetStatus("Stop the farm before calibrating")
            return
        end

        if not InstallHook() then
            SetStatus("Hook not supported - use the # boxes")
            return
        end

        prevEquip = EquipRemote
        prevUnequip = UnequipRemote
        EquipRemote = nil
        UnequipRemote = nil
        calibrating = 1

        calibToken = calibToken + 1
        local token = calibToken

        SetStatus("Calibrating - EQUIP a pet by hand, then UNEQUIP a pet")

        task.delay(40, function()
            if calibToken == token and calibrating ~= 0 then
                calibrating = 0
                EquipRemote = prevEquip
                UnequipRemote = prevUnequip
                SetStatus("Nothing detected - old remotes kept (or use the # boxes)")
            end
        end)
    end

    calibrateBtn.MouseButton1Click:Connect(function()
        local ok, err = pcall(StartCalibration)

        if not ok then
            calibrating = 0
            EquipRemote = prevEquip
            UnequipRemote = prevUnequip
            warn("[CALIBRATE ERROR]", err)
            SetStatus("ERROR in calibrate: " .. tostring(err))
        end
    end)

    -- Manual fallback: index numbers (ReplicatedStorage:GetChildren()[n])

    local function MakeIdxBox(placeholder, x)
        local f = New("Frame", {
            Size = UDim2.fromOffset(150, 34),
            Position = UDim2.fromOffset(x, 60),
            BackgroundColor3 = Color3.fromRGB(30, 34, 46),
            BorderSizePixel = 0,
        }, ui.pages[3])

        Round(f, 7)

        return New("TextBox", {
            Size = UDim2.new(1, -10, 1, 0),
            Position = UDim2.fromOffset(5, 0),
            BackgroundTransparency = 1,
            Text = "",
            PlaceholderText = placeholder,
            PlaceholderColor3 = Color3.fromRGB(130, 138, 160),
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            ClearTextOnFocus = false,
        }, f)
    end

    local equipIdxBox = MakeIdxBox("Equip #", 12)
    local unequipIdxBox = MakeIdxBox("Unequip #", 170)

    local applyBtn = New("TextButton", {
        Size = UDim2.new(1, -340, 0, 34),
        Position = UDim2.fromOffset(328, 60),
        BackgroundColor3 = Color3.fromRGB(35, 155, 90),
        Text = "APPLY",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
    }, ui.pages[3])

    Round(applyBtn, 7)

    applyBtn.MouseButton1Click:Connect(function()
        if enabled then
            SetStatus("Stop the farm first")
            return
        end

        local e = tonumber(equipIdxBox.Text)
        local u = tonumber(unequipIdxBox.Text)

        if not e or not u then
            SetStatus("Type both index numbers")
            return
        end

        local list = RS:GetChildren()
        local er = list[e]
        local ur = list[u]

        if not (er and er:IsA("RemoteFunction")) then
            SetStatus("#" .. e .. " is not a RemoteFunction")
            return
        end

        if not (ur and ur:IsA("RemoteFunction")) then
            SetStatus("#" .. u .. " is not a RemoteFunction")
            return
        end

        EquipRemote = er
        UnequipRemote = ur
        calibrating = 0
        calibToken = calibToken + 1

        SetStatus("Indexes applied - press START")
    end)

    -- DRAG GUI

    local dragging = false
    local dragStart
    local startPosition

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = frame.Position
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then

            local delta = input.Position - dragStart

            frame.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- STATS + TRACKER

    local stats = {
        presents = 0,
        cycles = 0,
        diamonds = 0,
        potions = 0,
        seconds = 0,          -- time the farm was running
        hasDiamonds = nil,    -- nil = not read yet, false = not found
        hasPotions = nil,
        lastDiamonds = nil,
        lastPotions = nil,
        potionsKey = nil,
    }

    local function FormatNumber(n)
        if n >= 1e9 then
            return string.format("%.2fB", n / 1e9)
        elseif n >= 1e6 then
            return string.format("%.2fM", n / 1e6)
        elseif n >= 1e3 then
            return string.format("%.1fK", n / 1e3)
        elseif n == math.floor(n) then
            return string.format("%d", n)
        end

        return string.format("%.1f", n)
    end

    local function FormatTime(sec)
        sec = math.floor(sec)
        return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
    end

    local function SetText(label, text)
        if label.Text ~= text then
            label.Text = text
        end
    end

    local function RateText(amount, available, decimals)
        if available == false then return "N/A" end
        if stats.seconds < 15 then return "..." end

        local rate = amount / (stats.seconds / 3600)

        if decimals then
            return string.format("%." .. decimals .. "f", rate)
        end

        return FormatNumber(rate)
    end

    local function UpdateStats()
        local t = ui.t

        local diamondsText = (stats.hasDiamonds == false) and "N/A" or FormatNumber(stats.diamonds)
        local potionsText = (stats.hasPotions == false) and "N/A" or FormatNumber(stats.potions)
        local dph = RateText(stats.diamonds, stats.hasDiamonds)

        local perCycle = "-"

        if stats.hasDiamonds == false then
            perCycle = "N/A"
        elseif stats.cycles > 0 then
            perCycle = FormatNumber(stats.diamonds / stats.cycles)
        end

        SetText(t.presents, tostring(stats.presents))
        SetText(t.cycles, tostring(stats.cycles))
        SetText(t.uptime, FormatTime(stats.seconds))
        SetText(t.diamonds, diamondsText)
        SetText(t.dph, dph)
        SetText(t.dpc, perCycle)
        SetText(t.potions, potionsText)
        SetText(t.ptph, RateText(stats.potions, stats.hasPotions))
        SetText(t.pph, RateText(stats.presents, true, 1))

        SetText(t.miniPresents, tostring(stats.presents))
        SetText(t.miniCycles, tostring(stats.cycles))
        SetText(t.miniDph, dph)

        local dInfo = (stats.hasDiamonds == nil) and "not read yet" or (stats.hasDiamonds and "found" or "NOT FOUND")
        local pInfo = (stats.hasPotions == nil) and "not read yet" or (stats.hasPotions and ("found (" .. tostring(stats.potionsKey or POTIONS_KEY) .. ")") or "NOT FOUND")

        SetText(ui.trackInfo, "Diamonds: " .. dInfo .. "   |   Potions: " .. pInfo)
    end

    -- numbers are read from the game's save data, read-only
    local function GetSave()
        local ok, save = pcall(function()
            return Library.Save.Get()
        end)

        if ok and type(save) == "table" then
            return save
        end

        return nil
    end

    local function CountItems(v)
        if type(v) == "number" then
            return v
        end

        if type(v) ~= "table" then
            return nil
        end

        local total = 0

        for _, item in pairs(v) do
            if type(item) == "number" then
                total = total + item
            elseif type(item) == "table" then
                total = total + (tonumber(item._am) or tonumber(item.Amount) or tonumber(item.amount) or tonumber(item.Count) or 1)
            else
                total = total + 1
            end
        end

        return total
    end

    local function ReadDiamonds(save)
        if save and type(save[DIAMONDS_KEY]) == "number" then
            return save[DIAMONDS_KEY]
        end

        -- fallback: a leaderstat with "diamond" in its name
        local ok, value = pcall(function()
            local ls = Player:FindFirstChild("leaderstats")

            if not ls then return nil end

            for _, child in ipairs(ls:GetChildren()) do
                if string.find(string.lower(child.Name), "diamond", 1, true)
                    and type(child.Value) == "number" then
                    return child.Value
                end
            end

            return nil
        end)

        if ok then
            return value
        end

        return nil
    end

    local function ReadPotions(save)
        if not save then return nil end

        local key = POTIONS_KEY or stats.potionsKey

        if not key then
            for k, v in pairs(save) do
                if type(k) == "string"
                    and string.find(string.lower(k), "potion", 1, true)
                    and (type(v) == "table" or type(v) == "number") then

                    key = k
                    stats.potionsKey = k
                    break
                end
            end
        end

        if key then
            return CountItems(save[key])
        end

        return nil
    end

    -- called once per second (only counts while the farm is running)
    local function TrackerTick(dt)
        if not enabled then
            stats.lastDiamonds = nil
            stats.lastPotions = nil
            return
        end

        stats.seconds = stats.seconds + dt

        local save = GetSave()

        local d = ReadDiamonds(save)
        stats.hasDiamonds = (d ~= nil)

        if d then
            if stats.lastDiamonds and d > stats.lastDiamonds then
                stats.diamonds = stats.diamonds + (d - stats.lastDiamonds)
            end

            stats.lastDiamonds = d
        end

        local p = ReadPotions(save)
        stats.hasPotions = (p ~= nil)

        if p then
            if stats.lastPotions and p > stats.lastPotions then
                stats.potions = stats.potions + (p - stats.lastPotions)
            end

            stats.lastPotions = p
        end
    end

    local function Pulse(label, size)
        label.TextSize = size + 6
        Tween(label, 0.3, { TextSize = size })
    end

    local function OnPresentDestroyed()
        stats.presents = stats.presents + 1
        UpdateStats()
        Pulse(ui.t.presents, 22)
        Pulse(ui.t.miniPresents, 22)
    end

    local function OnCycleDone()
        stats.cycles = stats.cycles + 1
        UpdateStats()
        Pulse(ui.t.cycles, 22)
        Pulse(ui.t.miniCycles, 22)
    end

    ui.resetBtn.MouseButton1Click:Connect(function()
        stats.presents = 0
        stats.cycles = 0
        stats.diamonds = 0
        stats.potions = 0
        stats.seconds = 0
        stats.lastDiamonds = nil
        stats.lastPotions = nil

        UpdateStats()
        SetStatus("Stats reset")
    end)

    ui.printKeysBtn.MouseButton1Click:Connect(function()
        local save = GetSave()

        if not save then
            SetStatus("Save data not available (Library.Save.Get)")
            return
        end

        print("[STATS] ---- top-level keys of your save ----")

        for k, v in pairs(save) do
            local info = type(v)

            if type(v) == "table" then
                local n = 0

                for _ in pairs(v) do
                    n = n + 1
                end

                info = "table (" .. n .. " entries)"
            elseif type(v) == "number" then
                info = "number = " .. tostring(v)
            end

            print("[STATS]", tostring(k), info)
        end

        for _, k in ipairs({ "BoostsInventory", "Boosts" }) do
            print("[STATS] ---- " .. k .. " ----")

            if type(save[k]) == "table" then
                for a, b in pairs(save[k]) do
                    local shown = tostring(b)

                    if type(b) == "table" then
                        local parts = {}

                        for kk, vv in pairs(b) do
                            table.insert(parts, tostring(kk) .. "=" .. tostring(vv))
                        end

                        shown = "{" .. table.concat(parts, ", ") .. "}"
                    end

                    print("[STATS]", tostring(a), shown)
                end
            end
        end

        SetStatus("Save keys printed in Output (F9)")
    end)

    ui.listBtn.MouseButton1Click:Connect(function()
        print("[REMOTES] ---- RemoteFunctions in ReplicatedStorage (index = use in # boxes) ----")

        for i, child in ipairs(RS:GetChildren()) do
            if child:IsA("RemoteFunction") then
                print("[REMOTES]", i, child.Name)
            end
        end

        SetStatus("Remotes printed in Output (F9)")
    end)

    task.spawn(function()
        local lastTick = os.clock()

        while gui.Parent do
            task.wait(1)

            local now = os.clock()
            local dt = now - lastTick
            lastTick = now

            pcall(TrackerTick, dt)
            pcall(UpdateStats)
        end
    end)

    UpdateStats()

    -- title-bar dot: green while the farm runs
    task.spawn(function()
        while gui.Parent do
            ui.dot.BackgroundColor3 = enabled and Color3.fromRGB(46, 204, 113) or THEME.muted
            task.wait(0.5)
        end
    end)

    -- PET REMOTES

    -- quiet = true: no warning when the server refuses (e.g. unequipping a pet
    -- that is not equipped). The result is still returned.
    local function InvokeRemote(remote, petId, quiet)
        if not enabled then return false end

        if not remote then
            warn("[AUTO FARM] Remote missing - press CALIBRATE REMOTES")
            return false
        end

        local ok, result = pcall(function()
            return remote:InvokeServer(petId)
        end)

        if not ok then
            if not quiet then
                warn("[AUTO FARM] Remote error:", result)
            end

            return false
        end

        if result == false then
            if not quiet then
                warn("[AUTO FARM] Pet action rejected:", petId)
            end

            return false
        end

        return true
    end

    -- true / false from the save, nil if the save can't be read
    local function IsEquipped(id)
        local save = GetSave()

        if save and type(save.PetsEquipped) == "table" then
            return save.PetsEquipped[id] ~= nil
        end

        return nil
    end

    local function EquipPet(id)
        if not enabled then return false end

        if InvokeRemote(EquipRemote, id) then
            return true
        end

        -- the server errors when the pet is already equipped: that is fine
        return IsEquipped(id) == true
    end

    -- result is ignored by the callers: the pet may simply not be equipped
    local function UnequipPet(id)
        return InvokeRemote(UnequipRemote, id, true)
    end

    local function EquipAllSmallPets()
        local equippedCount = 0

        for i, id in ipairs(SMALL_PETS) do
            if not enabled then return false end

            SetPet("Equipping " .. i .. "/" .. #SMALL_PETS)

            if EquipPet(id) then
                equippedCount = equippedCount + 1
            else
                warn("[AUTO FARM] Could not equip small pet", i, id)
            end

            task.wait(0.15)
        end

        if equippedCount == 0 then
            return false
        end

        -- give the pets time to spawn next to the player before selecting a target
        task.wait(2)
        SetPet(equippedCount .. " small pets equipped")
        return enabled
    end

    local function UnequipAllSmallPets()
        for i, id in ipairs(SMALL_PETS) do
            if not enabled then return false end

            SetPet("Unequipping " .. i .. "/" .. #SMALL_PETS)
            UnequipPet(id)

            task.wait(0.15)
        end

        return true
    end

    -- HELPERS

    local function GetHealth(coin)
        if not coin or not coin.Parent then return nil end

        local hp = coin:GetAttribute("Health")

        if typeof(hp) == "number" then
            return hp
        end

        return nil
    end

    local function GetRoot()
        local char = Player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function GetCoinPosition(coin)
        if not coin or not coin.Parent then return nil end

        if coin:IsA("PVInstance") then
            local ok, pivot = pcall(function()
                return coin:GetPivot()
            end)

            if ok and pivot then
                return pivot.Position
            end
        end

        for _, d in ipairs(coin:GetDescendants()) do
            if d:IsA("BasePart") then
                return d.Position
            end
        end

        return nil
    end

    local function GetDistance(coin)
        local root = GetRoot()
        local pos = GetCoinPosition(coin)

        if root and pos then
            return (root.Position - pos).Magnitude
        end

        return nil
    end

    -- TARGET SELECTION

    local function SelectCoin(coin)
        if not coin or not coin.Parent then return false end

        local ok, err = pcall(function()
            Library.Signal.Fire("Select Coin", coin)
        end)

        if not ok then
            warn("[AUTO FARM] Select error:", err)
            return false
        end

        return true
    end

    local function FindAngelusTarget(processed)
        local best
        local bestDifference = math.huge

        for _, coin in ipairs(Coins:GetChildren()) do
            if not processed[coin] then
                local hp = GetHealth(coin)

                if hp and hp > SWITCH_HP then
                    local difference = math.abs(hp - TARGET_HP)

                    if difference <= HP_TOLERANCE
                        and difference < bestDifference then

                        best = coin
                        bestDifference = difference
                    end
                end
            end
        end

        return best
    end

    -- Presents brought down by Angelus come first, then only coins near the
    -- player, nearest first.
    local function FindSmallPetTarget(processed)
        local best
        local bestScore = math.huge

        for _, coin in ipairs(Coins:GetChildren()) do
            if not processed[coin] then
                local hp = GetHealth(coin)

                if hp and hp > 0 and hp < SWITCH_HP then
                    local isPresent = presents[coin] == true
                    local dist = GetDistance(coin) or 0

                    if isPresent or dist <= MAX_DISTANCE then
                        local score = dist

                        if isPresent then
                            score = score - 1000000
                        end

                        if score < bestScore then
                            best = coin
                            bestScore = score
                        end
                    end
                end
            end
        end

        return best
    end

    -- ANGELUS PHASE

    local function AngelusPhase()
        SetStatus("Preparing Angelus")

        -- remove destroyed presents from the list
        for coin in pairs(presents) do
            if not coin.Parent then
                presents[coin] = nil
            end
        end

        if not UnequipAllSmallPets() then
            return false
        end

        if not enabled then return false end

        SetPet("Angelus")

        if not EquipPet(ANGELUS) then
            SetStatus("Angelus equip failed - game updated? try CALIBRATE")
            return false
        end

        task.wait(0.5)

        local processed = {}

        while enabled do
            local coin = FindAngelusTarget(processed)

            if not coin then
                break
            end

            SetStatus("Angelus attacking " .. coin.Name)

            if not SelectCoin(coin) then
                processed[coin] = true
                task.wait(0.5)
                continue
            end

            local success = false
            local lastHp = nil
            local lastProgress = os.clock()
            local reselects = 0

            while enabled and coin.Parent do
                local hp = GetHealth(coin)

                if hp then
                    hpStatus.Text = "Present HP: " .. string.format("%.0f", hp)

                    if hp <= SWITCH_HP then
                        success = true
                        break
                    end

                    if not lastHp or hp < lastHp then
                        lastHp = hp
                        lastProgress = os.clock()
                        reselects = 0
                    end
                end

                -- no damage for a while: select the coin again, give up after a few tries
                if os.clock() - lastProgress >= ANGELUS_STUCK_TIMEOUT then
                    if reselects >= MAX_RESELECTS then
                        warn("[AUTO FARM] Angelus is not damaging", coin.Name, "- skipping")
                        break
                    end

                    reselects = reselects + 1
                    SetStatus("Re-selecting " .. coin.Name .. " (" .. reselects .. "/" .. MAX_RESELECTS .. ")")
                    SelectCoin(coin)

                    lastProgress = os.clock()
                end

                task.wait(0.25)
            end

            if success then
                presents[coin] = true
                processed[coin] = true
                Debug("Present ready for small pets:", coin.Name)
            else
                -- destroyed, skipped or stopped: never pick the same coin twice
                processed[coin] = true

                if coin.Parent then
                    task.wait(0.5)
                end
            end
        end

        return enabled
    end

    -- SMALL PET PHASE

    local function DestroyWithSmallPets(coin)
        if not coin or not coin.Parent then return true end

        local hp = GetHealth(coin)

        if not hp or hp <= 0 then return true end
        if hp >= SWITCH_HP then return false end

        SetStatus("Small pets targeting " .. coin.Name)
        SetPet(#SMALL_PETS .. " small pets attacking")

        Debug("Target", coin.Name, "HP", hp, "Distance", GetDistance(coin))

        SelectCoin(coin)

        local previousHP = hp
        local lastProgress = os.clock()
        local reselects = 0

        while enabled and coin.Parent do
            task.wait(0.25)

            hp = GetHealth(coin)

            if not hp or hp <= 0 then
                hpStatus.Text = "Present HP: Destroyed"
                return true
            end

            hpStatus.Text = "Present HP: " .. string.format("%.0f", hp)

            if hp < previousHP then
                previousHP = hp
                lastProgress = os.clock()
                reselects = 0
            end

            -- no damage: select the coin again, and give up after a few tries
            if os.clock() - lastProgress >= STUCK_TIMEOUT then
                if reselects >= MAX_RESELECTS then
                    warn("[AUTO FARM] Pets are not damaging", coin.Name, "- skipping")
                    return false
                end

                reselects = reselects + 1
                SetStatus("Re-selecting " .. coin.Name .. " (" .. reselects .. "/" .. MAX_RESELECTS .. ")")
                SelectCoin(coin)

                lastProgress = os.clock()
            end
        end

        return not coin.Parent
    end

    local function SmallPetsPhase()
        SetStatus("Switching to small pets")
        SetPet("Unequipping Angelus")

        UnequipPet(ANGELUS)

        if not enabled then return false end

        if not EquipAllSmallPets() then
            return false
        end

        local processed = {}

        while enabled do
            local coin = FindSmallPetTarget(processed)

            if not coin then
                break
            end

            local destroyed = DestroyWithSmallPets(coin)

            if not enabled then return false end

            -- always mark as processed, so a stuck coin can't block the loop forever
            processed[coin] = true

            if destroyed or not coin.Parent then
                OnPresentDestroyed()
                SetStatus("Present destroyed")
            else
                SetStatus("Skipped " .. coin.Name)
                task.wait(0.5)
            end
        end

        return enabled
    end

    -- MAIN LOOP

    local function MainFarm()
        if running then return end
        running = true

        while enabled do
            SetStatus("Starting Angelus phase")

            if not AngelusPhase() then
                if not enabled then break end
                SetStatus("Angelus phase retry")
                task.wait(1)
                continue
            end

            if not enabled then break end

            if not SmallPetsPhase() then
                if not enabled then break end
                SetStatus("Small pets phase retry")
                task.wait(1)
                continue
            end

            if not enabled then break end

            SetStatus("All presents destroyed")

            UnequipAllSmallPets()

            if not enabled then break end

            OnCycleDone()
            SetStatus("Preparing next Angelus cycle")
            task.wait(0.5)
        end

        running = false
        enabled = false

        toggle.Text = "START FARM"
        toggle.BackgroundColor3 = Color3.fromRGB(35, 155, 90)

        SetStatus("Stopped")
        SetPet("None")
        hpStatus.Text = "Present HP: Waiting"
    end

    -- BUTTONS

    toggle.MouseButton1Click:Connect(function()
        if enabled then
            enabled = false

            toggle.Text = "START FARM"
            toggle.BackgroundColor3 = Color3.fromRGB(35, 155, 90)

            SetStatus("Stopping...")
        else
            if calibrating ~= 0 then
                SetStatus("Finish calibration first")
                return
            end

            if not (EquipRemote and UnequipRemote) then
                SetStatus("Remotes missing - press CALIBRATE")
                return
            end

            enabled = true

            toggle.Text = "STOP FARM"
            toggle.BackgroundColor3 = Color3.fromRGB(180, 55, 65)

            SetStatus("Starting...")
            task.spawn(function()
                local ok, err = pcall(MainFarm)

                if not ok then
                    warn("[AUTO FARM CRASH]", err)
                    enabled = false
                    running = false
                    toggle.Text = "START FARM"
                    toggle.BackgroundColor3 = Color3.fromRGB(35, 155, 90)
                    SetStatus("ERROR - check Output")
                end
            end)
        end
    end)

    close.MouseButton1Click:Connect(function()
        enabled = false
        gui:Destroy()
    end)

    if EquipRemote and UnequipRemote then
        SetStatus("Ready")
    else
        SetStatus("Remotes missing - press CALIBRATE or type the # boxes")
    end
end

-- ===================== KEY SCREEN =====================

-- HWID

local function GetHWID()
    local ok, id = pcall(function()
        if gethwid then
            return gethwid()
        end

        return nil
    end)

    if ok and type(id) == "string" and #id > 0 then
        return id
    end

    local ok2, id2 = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)

    if ok2 and type(id2) == "string" and #id2 > 0 then
        return id2
    end

    return nil
end

local HWID = GetHWID()

-- THEME / HELPERS

local THEME = {
    bg = Color3.fromRGB(14, 16, 24),
    title = Color3.fromRGB(19, 22, 33),
    panel = Color3.fromRGB(24, 28, 41),
    border = Color3.fromRGB(42, 48, 68),
    text = Color3.fromRGB(235, 238, 246),
    muted = Color3.fromRGB(135, 144, 168),
    accent = Color3.fromRGB(86, 128, 255),
    accent2 = Color3.fromRGB(155, 92, 255),
    green = Color3.fromRGB(40, 190, 120),
    red = Color3.fromRGB(226, 78, 90),
    yellow = Color3.fromRGB(255, 196, 90),
}

local function New(class, props, parent)
    local inst = Instance.new(class)

    for k, v in pairs(props) do
        inst[k] = v
    end

    inst.Parent = parent
    return inst
end

local function Round(inst, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = inst
    return c
end

local function Stroke(inst, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

local function Tween(inst, time, props)
    TweenService:Create(
        inst,
        TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        props
    ):Play()
end

local function GetGuiParent()
    local ok, ui = pcall(function()
        return gethui and gethui()
    end)

    if ok and ui then
        return ui
    end

    return Player:WaitForChild("PlayerGui")
end

-- GUI

local guiParent = GetGuiParent()
local old = guiParent:FindFirstChild("AngelusLoader")

if old then
    old:Destroy()
end

local gui = New("ScreenGui", {
    Name = "AngelusLoader",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

local window = New("Frame", {
    Size = UDim2.fromOffset(340, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    Position = UDim2.new(0.5, -170, 0.5, -150),
    BackgroundColor3 = THEME.bg,
    BorderSizePixel = 0,
    Active = true,
    ClipsDescendants = true,
}, gui)

Round(window, 14)
Stroke(window, THEME.border, 1.5)

New("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
}, window)

local titleBar = New("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = THEME.title,
    BorderSizePixel = 0,
    LayoutOrder = 1,
}, window)

New("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(16, 6),
    Size = UDim2.new(1, -70, 0, 20),
    Text = "ANGELUS",
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = THEME.text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

New("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(16, 25),
    Size = UDim2.new(1, -70, 0, 14),
    Text = "License verification",
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = THEME.muted,
    TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

local close = New("TextButton", {
    Size = UDim2.fromOffset(26, 26),
    Position = UDim2.new(1, -36, 0, 10),
    BackgroundColor3 = THEME.red,
    AutoButtonColor = false,
    BorderSizePixel = 0,
    Text = "X",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
}, titleBar)

Round(close, 7)

local accentLine = New("Frame", {
    Size = UDim2.new(1, 0, 0, 2),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    LayoutOrder = 2,
}, window)

do
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(THEME.accent, THEME.accent2)
    g.Parent = accentLine
end

local body = New("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    LayoutOrder = 3,
}, window)

New("UIPadding", {
    PaddingTop = UDim.new(0, 16),
    PaddingBottom = UDim.new(0, 16),
    PaddingLeft = UDim.new(0, 16),
    PaddingRight = UDim.new(0, 16),
}, body)

New("UIListLayout", {
    Padding = UDim.new(0, 10),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, body)

New("TextLabel", {
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundTransparency = 1,
    Text = "Enter your key",
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextColor3 = THEME.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    LayoutOrder = 1,
}, body)

New("TextLabel", {
    Size = UDim2.new(1, 0, 0, 32),
    BackgroundTransparency = 1,
    Text = "Each key works on one device only. The first device that uses a key is locked to it.",
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = THEME.muted,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    LayoutOrder = 2,
}, body)

local keyBoxFrame = New("Frame", {
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = THEME.panel,
    BorderSizePixel = 0,
    LayoutOrder = 3,
}, body)

Round(keyBoxFrame, 9)
local keyStroke = Stroke(keyBoxFrame, THEME.border, 1)

local keyBox = New("TextBox", {
    Size = UDim2.new(1, -24, 1, 0),
    Position = UDim2.fromOffset(12, 0),
    BackgroundTransparency = 1,
    Text = "",
    PlaceholderText = "XXXX-XXXX-XXXX-XXXX",
    PlaceholderColor3 = THEME.muted,
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamMedium,
    TextSize = 14,
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
}, keyBoxFrame)

keyBox.Focused:Connect(function()
    Tween(keyStroke, 0.15, { Color = THEME.accent })
end)

keyBox.FocusLost:Connect(function()
    Tween(keyStroke, 0.15, { Color = THEME.border })
end)

local activate = New("TextButton", {
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundColor3 = THEME.accent,
    AutoButtonColor = false,
    BorderSizePixel = 0,
    Text = "ACTIVATE",
    TextColor3 = THEME.text,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    LayoutOrder = 4,
}, body)

Round(activate, 9)

activate.MouseEnter:Connect(function()
    Tween(activate, 0.12, { BackgroundColor3 = THEME.accent:Lerp(Color3.new(1, 1, 1), 0.12) })
end)

activate.MouseLeave:Connect(function()
    Tween(activate, 0.12, { BackgroundColor3 = THEME.accent })
end)

local statusLabel = New("TextLabel", {
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text = "",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = THEME.muted,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    LayoutOrder = 5,
}, body)

local hwidShort = HWID and (string.sub(HWID, 1, 8) .. "...") or "unavailable"

New("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundTransparency = 1,
    Text = "Device ID: " .. hwidShort .. "  (used to lock your key)",
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = THEME.muted,
    TextXAlignment = Enum.TextXAlignment.Left,
    LayoutOrder = 6,
}, body)

local function SetStatus(text, color)
    statusLabel.Text = text
    statusLabel.TextColor3 = color or THEME.muted
end

local function Shake(inst)
    local base = inst.Position

    for _, dx in ipairs({ -6, 6, -4, 4, 0 }) do
        Tween(inst, 0.04, { Position = base + UDim2.fromOffset(dx, 0) })
        task.wait(0.045)
    end
end

-- DRAG

local dragging = false
local dragStart
local startPosition

local function IsPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

titleBar.InputBegan:Connect(function(input)
    if IsPointer(input) then
        dragging = true
        dragStart = input.Position
        startPosition = window.Position
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging
        and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then

        local delta = input.Position - dragStart

        window.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

UIS.InputEnded:Connect(function(input)
    if IsPointer(input) then
        dragging = false
    end
end)

-- KEY CHECK (offline)

local function LoadBindings()
    local data = {}

    pcall(function()
        if isfile and readfile and isfile(BIND_FILE) then
            local decoded = HttpService:JSONDecode(readfile(BIND_FILE))

            if type(decoded) == "table" then
                data = decoded
            end
        end
    end)

    return data
end

local function SaveBindings(data)
    pcall(function()
        if writefile then
            writefile(BIND_FILE, HttpService:JSONEncode(data))
        end
    end)
end

local function CheckKey(key)
    if not VALID_KEYS[key] then
        return false, "Invalid key"
    end

    if not HWID then
        return false, "Could not read your device ID"
    end

    local bindings = LoadBindings()
    local bound = bindings[key]

    if bound and bound ~= HWID then
        return false, "This key is locked to another device"
    end

    if not bound then
        bindings[key] = HWID
        SaveBindings(bindings)
    end

    return true
end

local busy = false

local function TryActivate()
    if busy then return end

    -- gsub returns 2 values, so keep only the string
    local cleaned = (keyBox.Text or ""):gsub("%s+", "")
    local key = string.lower(cleaned)

    if #key < 8 then
        SetStatus("Enter a valid key", THEME.red)
        Shake(keyBoxFrame)
        return
    end

    busy = true
    activate.Text = "CHECKING..."
    SetStatus("Checking key...", THEME.muted)

    local ok, result = CheckKey(key)

    if not ok then
        busy = false
        activate.Text = "ACTIVATE"
        SetStatus(result, THEME.red)
        Shake(keyBoxFrame)
        return
    end

    pcall(function()
        if writefile then
            writefile(KEY_FILE, key)
        end
    end)

    activate.Text = "UNLOCKED"
    Tween(activate, 0.2, { BackgroundColor3 = THEME.green })
    SetStatus("Key accepted - loading menu...", THEME.green)

    task.wait(0.7)
    gui:Destroy()

    task.spawn(function()
        local okRun, runErr = pcall(StartMenu)

        if not okRun then
            warn("[LOADER] script error:", runErr)
        end
    end)
end

activate.MouseButton1Click:Connect(TryActivate)

keyBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        TryActivate()
    end
end)

close.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

-- prefill the saved key
pcall(function()
    if isfile and readfile and isfile(KEY_FILE) then
        keyBox.Text = readfile(KEY_FILE)
    end
end)

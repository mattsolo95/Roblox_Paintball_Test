--!strict
-- HUDController.luau (Client Module)
-- Builds and manages the entire in-game HUD:
--   • Countdown timer (center-top)
--   • Team scores (left/right of timer)
--   • Game win tallies (outside scores)
--   • Ammo counter (bottom-right)
--   • Health bar (bottom-left)
--   • Kill feed (top-right, fades out)
--   • NMZ zone text (handled by NoManZoneClient but space reserved here)
--   • Respawn countdown overlay

local Players   = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Remotes   = require(game:GetService("ReplicatedStorage"):WaitForChild("Remotes"))

local HUDController = {}
local localPlayer   = Players.LocalPlayer
local playerGui     = localPlayer:WaitForChild("PlayerGui")

local screenGui: ScreenGui
local timerLabel: TextLabel
local scoreA_Label: TextLabel
local scoreB_Label: TextLabel
local winsA_Label: TextLabel
local winsB_Label: TextLabel
local ammoLabel: TextLabel
local healthBar: Frame
local healthLabel: TextLabel
local killFeedFrame: Frame
local respawnOverlay: Frame
local respawnLabel: TextLabel

local KILL_FEED_MAX     = 6
local KILL_FEED_LIFE    = 6     -- seconds each entry stays
local killFeedEntries: {Frame} = {}

-- =====================================================
-- BUILD HUD
-- =====================================================

local function makeLabel(
    name: string, text: string,
    size: UDim2, pos: UDim2,
    anchor: Vector2, font: Enum.Font,
    textSize: number, color: Color3,
    parent: Instance
): TextLabel
    local lbl               = Instance.new("TextLabel")
    lbl.Name                = name
    lbl.Size                = size
    lbl.Position            = pos
    lbl.AnchorPoint         = anchor
    lbl.Text                = text
    lbl.Font                = font
    lbl.TextSize            = textSize
    lbl.TextColor3          = color
    lbl.BackgroundTransparency = 1
    lbl.TextStrokeTransparency = 0.5
    lbl.TextStrokeColor3    = Color3.new(0, 0, 0)
    lbl.Parent              = parent
    return lbl
end

local function makeFrame(
    name: string, size: UDim2, pos: UDim2,
    anchor: Vector2, color: Color3,
    transparency: number, parent: Instance
): Frame
    local f                 = Instance.new("Frame")
    f.Name                  = name
    f.Size                  = size
    f.Position              = pos
    f.AnchorPoint           = anchor
    f.BackgroundColor3      = color
    f.BackgroundTransparency = transparency
    f.BorderSizePixel       = 0
    f.Parent                = parent
    return f
end

function HUDController:Initialize()
    -- Root ScreenGui
    screenGui               = Instance.new("ScreenGui")
    screenGui.Name          = "HUD"
    screenGui.ResetOnSpawn  = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent        = playerGui

    -- ── TIMER (center-top) ─────────────────────────────
    local timerBG = makeFrame("TimerBG",
        UDim2.new(0, 160, 0, 50),
        UDim2.new(0.5, 0, 0, 8),
        Vector2.new(0.5, 0),
        Color3.new(0, 0, 0), 0.45, screenGui)
    Instance.new("UICorner", timerBG).CornerRadius = UDim.new(0, 8)

    timerLabel = makeLabel("Timer", "7:00",
        UDim2.new(1, 0, 1, 0), UDim2.new(0.5, 0, 0.5, 0),
        Vector2.new(0.5, 0.5),
        Enum.Font.GothamBold, 28, Color3.new(1, 1, 1), timerBG)

    -- ── SCORES (flanking timer) ─────────────────────────
    local scoreABG = makeFrame("ScoreABG",
        UDim2.new(0, 120, 0, 50),
        UDim2.new(0.5, -170, 0, 8),
        Vector2.new(1, 0),
        Color3.new(0, 0, 0), 0.45, screenGui)
    Instance.new("UICorner", scoreABG).CornerRadius = UDim.new(0, 8)
    scoreA_Label = makeLabel("ScoreA", "0",
        UDim2.new(1, 0, 1, 0), UDim2.new(0.5, 0, 0.5, 0),
        Vector2.new(0.5, 0.5),
        Enum.Font.GothamBold, 28, Color3.fromRGB(255, 100, 100), scoreABG)

    local scoreBBG = makeFrame("ScoreBBG",
        UDim2.new(0, 120, 0, 50),
        UDim2.new(0.5, 170, 0, 8),
        Vector2.new(0, 0),
        Color3.new(0, 0, 0), 0.45, screenGui)
    Instance.new("UICorner", scoreBBG).CornerRadius = UDim.new(0, 8)
    scoreB_Label = makeLabel("ScoreB", "0",
        UDim2.new(1, 0, 1, 0), UDim2.new(0.5, 0, 0.5, 0),
        Vector2.new(0.5, 0.5),
        Enum.Font.GothamBold, 28, Color3.fromRGB(100, 150, 255), scoreBBG)

    -- ── WINS TALLY (outer) ──────────────────────────────
    winsA_Label = makeLabel("WinsA", "Wins: 0",
        UDim2.new(0, 100, 0, 28),
        UDim2.new(0.5, -300, 0, 18),
        Vector2.new(1, 0),
        Enum.Font.Gotham, 18, Color3.fromRGB(255, 160, 160), screenGui)

    winsB_Label = makeLabel("WinsB", "Wins: 0",
        UDim2.new(0, 100, 0, 28),
        UDim2.new(0.5, 300, 0, 18),
        Vector2.new(0, 0),
        Enum.Font.Gotham, 18, Color3.fromRGB(160, 180, 255), screenGui)

    -- ── HEALTH BAR (bottom-left) ────────────────────────
    local hpBG = makeFrame("HPBG",
        UDim2.new(0, 240, 0, 24),
        UDim2.new(0, 20, 1, -60),
        Vector2.new(0, 1),
        Color3.new(0.1, 0.1, 0.1), 0.3, screenGui)
    Instance.new("UICorner", hpBG).CornerRadius = UDim.new(0, 6)

    healthBar = makeFrame("HealthFill",
        UDim2.new(1, 0, 1, 0),
        UDim2.new(0, 0, 0, 0),
        Vector2.new(0, 0),
        Color3.fromRGB(60, 200, 80), 0, hpBG)
    Instance.new("UICorner", healthBar).CornerRadius = UDim.new(0, 6)

    healthLabel = makeLabel("HPLabel", "100 HP",
        UDim2.new(1, 0, 1, 0), UDim2.new(0.5, 0, 0.5, 0),
        Vector2.new(0.5, 0.5),
        Enum.Font.GothamBold, 14, Color3.new(1, 1, 1), hpBG)

    -- ── AMMO (bottom-right) ─────────────────────────────
    local ammoBG = makeFrame("AmmoBG",
        UDim2.new(0, 160, 0, 50),
        UDim2.new(1, -20, 1, -70),
        Vector2.new(1, 1),
        Color3.new(0, 0, 0), 0.45, screenGui)
    Instance.new("UICorner", ammoBG).CornerRadius = UDim.new(0, 8)

    ammoLabel = makeLabel("AmmoLabel", "12 / 12",
        UDim2.new(1, -10, 1, 0), UDim2.new(0, 8, 0.5, 0),
        Vector2.new(0, 0.5),
        Enum.Font.GothamBold, 22, Color3.new(1, 1, 1), ammoBG)

    -- ── KILL FEED (top-right) ───────────────────────────
    killFeedFrame = makeFrame("KillFeed",
        UDim2.new(0, 300, 0, KILL_FEED_MAX * 28),
        UDim2.new(1, -10, 0, 10),
        Vector2.new(1, 0),
        Color3.new(0, 0, 0), 1, screenGui)

    -- ── RESPAWN OVERLAY ─────────────────────────────────
    respawnOverlay = makeFrame("RespawnOverlay",
        UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0),
        Vector2.new(0, 0),
        Color3.new(0, 0, 0), 0.55, screenGui)
    respawnOverlay.Visible = false
    respawnLabel = makeLabel("RespawnLabel", "Respawning in 5...",
        UDim2.new(0, 400, 0, 60),
        UDim2.new(0.5, 0, 0.5, 0),
        Vector2.new(0.5, 0.5),
        Enum.Font.GothamBold, 32, Color3.new(1, 1, 1), respawnOverlay)

    self:SetVisible(false)
    self:_hookRemotes()
    self:_hookHealthBar()
end

-- =====================================================
-- REMOTE HOOKS
-- =====================================================

function HUDController:_hookRemotes()
    Remotes.OnClient("TimerUpdate", function(seconds: number)
        local mins = math.floor(seconds / 60)
        local secs = seconds % 60
        timerLabel.Text = string.format("%d:%02d", mins, secs)
        -- Flash red in last 30 seconds
        timerLabel.TextColor3 = if seconds <= 30
            then Color3.fromRGB(255, 80, 80)
            else Color3.new(1, 1, 1)
    end)

    Remotes.OnClient("ScoreUpdate", function(aScore: number, bScore: number, aWins: number, bWins: number)
        scoreA_Label.Text = tostring(aScore)
        scoreB_Label.Text = tostring(bScore)
        winsA_Label.Text  = "Wins: " .. aWins
        winsB_Label.Text  = "Wins: " .. bWins
    end)

    -- Update score label colors to match voted team colors
    Remotes.OnClient("TeamVoteResult", function(colorA: any, colorB: any)
        if scoreA_Label and colorA and colorA.rgb then
            scoreA_Label.TextColor3 = colorA.rgb
            winsA_Label.TextColor3  = colorA.rgb
        end
        if scoreB_Label and colorB and colorB.rgb then
            scoreB_Label.TextColor3 = colorB.rgb
            winsB_Label.TextColor3  = colorB.rgb
        end
    end)

    -- Personal points
    Remotes.OnClient("PersonalPointsUpdate", function(points: number)
        -- Find or create personal points label near timer
        local gui   = playerGui:FindFirstChild("HUD")
        if not gui then return end
        local lbl   = gui:FindFirstChild("PersonalPts") :: TextLabel?
        if not lbl then
            lbl             = Instance.new("TextLabel")
            lbl.Name        = "PersonalPts"
            lbl.Size        = UDim2.new(0, 160, 0, 22)
            lbl.Position    = UDim2.new(0.5, 0, 0, 62)
            lbl.AnchorPoint = Vector2.new(0.5, 0)
            lbl.BackgroundTransparency = 1
            lbl.Font        = Enum.Font.Gotham
            lbl.TextSize    = 15
            lbl.TextColor3  = Color3.fromRGB(220, 220, 100)
            lbl.TextStrokeTransparency = 0.4
            lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
            lbl.Parent      = gui
        end
        lbl.Text = "You: " .. points .. " pts"
    end)

    Remotes.OnClient("AmmoUpdate", function(current: number, max: number, reloading: boolean)
        ammoLabel.Text = if reloading
            then "Reloading..."
            else current .. " / " .. max
        ammoLabel.TextColor3 = if current == 0
            then Color3.fromRGB(255, 80, 80)
            else Color3.new(1, 1, 1)
    end)

    Remotes.OnClient("KillFeedUpdate", function(attacker: string, victim: string, weapon: string)
        self:_addKillFeedEntry(attacker, victim, weapon)
    end)

    Remotes.OnClient("PlayerRespawnCountdown", function(seconds: number)
        respawnOverlay.Visible = true
        respawnLabel.Text = "Respawning in " .. seconds .. "..."
        if seconds <= 0 then
            respawnOverlay.Visible = false
        end
    end)
end

-- =====================================================
-- HEALTH BAR (local character)
-- =====================================================

function HUDController:_hookHealthBar()
    local function connectCharacter(char: Model)
        local hum = char:WaitForChild("Humanoid") :: Humanoid
        hum:GetPropertyChangedSignal("Health"):Connect(function()
            local pct = hum.Health / hum.MaxHealth
            healthBar.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
            healthLabel.Text = math.ceil(hum.Health) .. " HP"
            healthBar.BackgroundColor3 = Color3.fromRGB(
                math.floor((1 - pct) * 220 + 60),
                math.floor(pct * 200 + 60),
                60
            )
        end)
    end

    if localPlayer.Character then
        connectCharacter(localPlayer.Character)
    end
    localPlayer.CharacterAdded:Connect(connectCharacter)
end

-- =====================================================
-- KILL FEED
-- =====================================================

function HUDController:_addKillFeedEntry(attacker: string, victim: string, weapon: string)
    local entry                     = Instance.new("Frame")
    entry.Size                      = UDim2.new(1, 0, 0, 24)
    entry.BackgroundColor3          = Color3.new(0, 0, 0)
    entry.BackgroundTransparency    = 0.4
    entry.BorderSizePixel           = 0
    Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 4)
    entry.Parent                    = killFeedFrame

    local txt                       = Instance.new("TextLabel")
    txt.Size                        = UDim2.new(1, -8, 1, 0)
    txt.Position                    = UDim2.new(0, 4, 0, 0)
    txt.BackgroundTransparency      = 1
    txt.Text                        = attacker .. " ⟹ " .. victim .. "  [" .. weapon .. "]"
    txt.TextColor3                  = Color3.new(1, 1, 1)
    txt.Font                        = Enum.Font.Gotham
    txt.TextSize                    = 13
    txt.TextXAlignment              = Enum.TextXAlignment.Right
    txt.Parent                      = entry

    table.insert(killFeedEntries, entry)
    self:_reLayoutKillFeed()

    -- Fade and remove after KILL_FEED_LIFE seconds
    task.delay(KILL_FEED_LIFE, function()
        if entry and entry.Parent then
            TweenService:Create(entry, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
            TweenService:Create(txt, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
            task.wait(0.5)
            local idx = table.find(killFeedEntries, entry)
            if idx then table.remove(killFeedEntries, idx) end
            entry:Destroy()
            self:_reLayoutKillFeed()
        end
    end)

    -- Trim to max entries
    while #killFeedEntries > KILL_FEED_MAX do
        local oldest = table.remove(killFeedEntries, 1)
        oldest:Destroy()
    end
end

function HUDController:_reLayoutKillFeed()
    local y = 0
    for _, entry in ipairs(killFeedEntries) do
        entry.Position = UDim2.new(0, 0, 0, y)
        y += 26
    end
end

-- =====================================================
-- VISIBILITY
-- =====================================================

function HUDController:SetVisible(visible: boolean)
    if screenGui then screenGui.Enabled = visible end
end

return HUDController

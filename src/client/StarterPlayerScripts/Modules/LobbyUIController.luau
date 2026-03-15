--!strict
-- LobbyUIController.luau (Client Module)
-- Manages: lobby screen, team color vote UI, loading screen.

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local Remotes       = require(game:GetService("ReplicatedStorage"):WaitForChild("Remotes"))

local LobbyUIController = {}
local localPlayer       = Players.LocalPlayer
local playerGui         = localPlayer:WaitForChild("PlayerGui")

local lobbyGui:     ScreenGui?  = nil
local voteGui:      ScreenGui?  = nil
local loadingGui:   ScreenGui?  = nil

-- Loading progress tracking
local _loadingBar:  Frame?      = nil
local _loadingLabel: TextLabel? = nil

-- =====================================================
-- BUILD UIs
-- =====================================================

local function makeLabel(text: string, size: UDim2, pos: UDim2,
    anchor: Vector2, fontSize: number, color: Color3,
    font: Enum.Font, parent: Instance): TextLabel
    local lbl               = Instance.new("TextLabel")
    lbl.Text                = text
    lbl.Size                = size
    lbl.Position            = pos
    lbl.AnchorPoint         = anchor
    lbl.Font                = font
    lbl.TextSize            = fontSize
    lbl.TextColor3          = color
    lbl.BackgroundTransparency = 1
    lbl.TextStrokeTransparency = 0.4
    lbl.TextStrokeColor3    = Color3.new(0, 0, 0)
    lbl.Parent              = parent
    return lbl
end

local function makeFrame(size: UDim2, pos: UDim2, anchor: Vector2,
    color: Color3, transparency: number, parent: Instance): Frame
    local f                 = Instance.new("Frame")
    f.Size                  = size
    f.Position              = pos
    f.AnchorPoint           = anchor
    f.BackgroundColor3      = color
    f.BackgroundTransparency = transparency
    f.BorderSizePixel       = 0
    f.Parent                = parent
    return f
end

local function buildLobbyGui()
    local gui               = Instance.new("ScreenGui")
    gui.Name                = "LobbyUI"
    gui.ResetOnSpawn        = false
    gui.ZIndexBehavior      = Enum.ZIndexBehavior.Sibling
    gui.Parent              = playerGui

    -- Title
    makeLabel("Roblox Paintball",
        UDim2.new(0, 600, 0, 70),
        UDim2.new(0.5, 0, 0.08, 0),
        Vector2.new(0.5, 0.5),
        54, Color3.fromRGB(255, 240, 200),
        Enum.Font.GothamBold, gui)

    -- Subtitle
    makeLabel("Waiting for players...",
        UDim2.new(0, 400, 0, 35),
        UDim2.new(0.5, 0, 0.16, 0),
        Vector2.new(0.5, 0.5),
        22, Color3.fromRGB(200, 200, 200),
        Enum.Font.Gotham, gui)

    lobbyGui = gui
end

local function buildVoteGui()
    local gui               = Instance.new("ScreenGui")
    gui.Name                = "VoteUI"
    gui.ResetOnSpawn        = false
    gui.Enabled             = false
    gui.Parent              = playerGui

    local panel             = makeFrame(
        UDim2.new(0, 500, 0, 420),
        UDim2.new(0.5, 0, 0.5, 0),
        Vector2.new(0.5, 0.5),
        Color3.new(0.05, 0.05, 0.1), 0.15, gui)
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

    makeLabel("Vote for Team Colors",
        UDim2.new(1, 0, 0, 50),
        UDim2.new(0.5, 0, 0, 12),
        Vector2.new(0.5, 0),
        26, Color3.new(1, 1, 1),
        Enum.Font.GothamBold, panel)

    -- Color buttons (generated dynamically from GameConfig)
    local grid              = Instance.new("Frame")
    grid.Name               = "ColorGrid"
    grid.Size               = UDim2.new(1, -30, 1, -80)
    grid.Position           = UDim2.new(0, 15, 0, 65)
    grid.BackgroundTransparency = 1
    grid.Parent             = panel

    local layout            = Instance.new("UIGridLayout")
    layout.CellSize         = UDim2.new(0, 100, 0, 80)
    layout.CellPadding      = UDim2.new(0, 10, 0, 10)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent           = grid

    voteGui = gui
end

local function buildLoadingGui()
    local gui               = Instance.new("ScreenGui")
    gui.Name                = "LoadingUI"
    gui.ResetOnSpawn        = false
    gui.Enabled             = false
    gui.Parent              = playerGui

    -- Full black overlay
    local overlay           = makeFrame(
        UDim2.new(1, 0, 1, 0),
        UDim2.new(0, 0, 0, 0),
        Vector2.new(0, 0),
        Color3.new(0, 0, 0), 0, gui)

    makeLabel("Loading Map...",
        UDim2.new(0, 400, 0, 60),
        UDim2.new(0.5, 0, 0.4, 0),
        Vector2.new(0.5, 0.5),
        36, Color3.new(1, 1, 1),
        Enum.Font.GothamBold, overlay)

    local barBG             = makeFrame(
        UDim2.new(0, 500, 0, 20),
        UDim2.new(0.5, 0, 0.55, 0),
        Vector2.new(0.5, 0.5),
        Color3.new(0.15, 0.15, 0.15), 0, overlay)
    Instance.new("UICorner", barBG).CornerRadius = UDim.new(0, 10)

    local barFill           = makeFrame(
        UDim2.new(0, 0, 1, 0),
        UDim2.new(0, 0, 0, 0),
        Vector2.new(0, 0),
        Color3.fromRGB(80, 200, 120), 0, barBG)
    Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 10)
    _loadingBar             = barFill

    _loadingLabel           = makeLabel("0%",
        UDim2.new(0, 200, 0, 28),
        UDim2.new(0.5, 0, 0.62, 0),
        Vector2.new(0.5, 0),
        18, Color3.fromRGB(180, 180, 180),
        Enum.Font.Gotham, overlay)

    loadingGui = gui
end

-- =====================================================
-- TEAM VOTE UI POPULATION
-- =====================================================

function LobbyUIController:_populateVoteButtons(colorOptions: {any})
    if not voteGui then return end

    -- Clear any previously built vote UI and rebuild fresh
    voteGui:ClearAllChildren()

    local panel                 = Instance.new("Frame")
    panel.Name                  = "VotePanel"
    panel.Size                  = UDim2.new(0, 520, 0, 440)
    panel.Position              = UDim2.new(0.5, 0, 0.5, 0)
    panel.AnchorPoint           = Vector2.new(0.5, 0.5)
    panel.BackgroundColor3      = Color3.new(0.05, 0.05, 0.1)
    panel.BackgroundTransparency = 0.12
    panel.BorderSizePixel       = 0
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
    panel.Parent                = voteGui

    local title                 = Instance.new("TextLabel")
    title.Size                  = UDim2.new(1, 0, 0, 50)
    title.Position              = UDim2.new(0, 0, 0, 10)
    title.BackgroundTransparency = 1
    title.Text                  = "Vote for Team Color"
    title.Font                  = Enum.Font.GothamBold
    title.TextSize              = 26
    title.TextColor3            = Color3.new(1, 1, 1)
    title.Parent                = panel

    local grid                  = Instance.new("Frame")
    grid.Name                   = "ColorGrid"
    grid.Size                   = UDim2.new(1, -30, 1, -70)
    grid.Position               = UDim2.new(0, 15, 0, 65)
    grid.BackgroundTransparency = 1
    grid.Parent                 = panel

    local layout                = Instance.new("UIGridLayout")
    layout.CellSize             = UDim2.new(0, 110, 0, 85)
    layout.CellPadding          = UDim2.new(0, 10, 0, 10)
    layout.HorizontalAlignment  = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment    = Enum.VerticalAlignment.Top
    layout.Parent               = grid

    for i, opt in ipairs(colorOptions) do
        local btn               = Instance.new("TextButton")
        btn.Size                = UDim2.new(0, 110, 0, 85)
        btn.BackgroundColor3    = opt.rgb or Color3.new(0.5, 0.5, 0.5)
        btn.Text                = opt.name or ("Color " .. i)
        btn.TextColor3          = Color3.new(1, 1, 1)
        btn.Font                = Enum.Font.GothamBold
        btn.TextSize            = 15
        btn.BorderSizePixel     = 0
        btn.BackgroundTransparency = 0.1
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        btn.Parent              = grid

        local idx = i
        btn.Activated:Connect(function()
            Remotes.FireServer("CastTeamVote", idx)
            for _, other in ipairs(grid:GetChildren()) do
                if other:IsA("TextButton") then
                    other.BackgroundTransparency = 0.5
                    other.Text = other.Text:gsub(" ✓", "")
                end
            end
            btn.BackgroundTransparency = 0
            btn.Text = btn.Text .. " ✓"
        end)
    end
end

-- Map vote UI (Snow vs Grass)
function LobbyUIController:_showMapVote(options: {string})
    local gui               = Instance.new("ScreenGui")
    gui.Name                = "MapVoteUI"
    gui.ResetOnSpawn        = false
    gui.Parent              = playerGui

    local panel             = Instance.new("Frame")
    panel.Size              = UDim2.new(0, 420, 0, 180)
    panel.Position          = UDim2.new(0.5, 0, 0.25, 0)
    panel.AnchorPoint       = Vector2.new(0.5, 0)
    panel.BackgroundColor3  = Color3.new(0, 0, 0)
    panel.BackgroundTransparency = 0.2
    panel.BorderSizePixel   = 0
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
    panel.Parent            = gui

    local title             = Instance.new("TextLabel")
    title.Size              = UDim2.new(1, 0, 0, 44)
    title.Position          = UDim2.new(0, 0, 0, 8)
    title.BackgroundTransparency = 1
    title.Text              = "Vote: Which Map?"
    title.Font              = Enum.Font.GothamBold
    title.TextSize          = 24
    title.TextColor3        = Color3.new(1, 1, 1)
    title.Parent            = panel

    local mapNames  = { snow = "❄  Winter Kingdom", grass = "🌿  Rolling Hills" }
    local mapColors = { snow = Color3.fromRGB(180, 210, 240), grass = Color3.fromRGB(80, 160, 60) }
    local xPos = 0.05
    for _, opt in ipairs(options) do
        local btn               = Instance.new("TextButton")
        btn.Size                = UDim2.new(0.42, 0, 0, 60)
        btn.Position            = UDim2.new(xPos, 0, 0, 60)
        btn.BackgroundColor3    = mapColors[opt] or Color3.new(0.5, 0.5, 0.5)
        btn.BackgroundTransparency = 0.15
        btn.Text                = mapNames[opt] or opt
        btn.TextColor3          = Color3.new(1, 1, 1)
        btn.Font                = Enum.Font.GothamBold
        btn.TextSize            = 18
        btn.BorderSizePixel     = 0
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        btn.Parent              = panel
        xPos += 0.5

        local choice = opt
        btn.Activated:Connect(function()
            Remotes.FireServer("CastMapVote", choice)
            btn.BackgroundTransparency = 0
            btn.Text = btn.Text .. " ✓"
        end)
    end

    -- Auto-dismiss after 14 seconds (slightly longer than server timer)
    task.delay(14, function()
        if gui and gui.Parent then gui:Destroy() end
    end)
end

-- =====================================================
-- LOADING BAR ANIMATION
-- =====================================================

local function animateLoadingBar(mapName: string)
    if not _loadingBar or not _loadingLabel then return end

    _loadingLabel.Text = "Preparing " .. (mapName == "snow" and "Winter Kingdom" or "Rolling Hills") .. "..."

    -- Fake progress from 0 → 100% over MAP_LOAD_DELAY seconds
    for pct = 0, 100, 5 do
        _loadingBar.Size        = UDim2.new(pct / 100, 0, 1, 0)
        _loadingLabel.Text      = pct .. "%"
        task.wait(0.08)
    end
    _loadingBar.Size            = UDim2.new(1, 0, 1, 0)
    _loadingLabel.Text          = "100% — Ready!"
end

-- =====================================================
-- REMOTE HOOKS
-- =====================================================

function LobbyUIController:Initialize()
    buildLobbyGui()
    buildVoteGui()
    buildLoadingGui()

    Remotes.OnClient("MapVote", function(options: {string})
        self:_showMapVote(options)
    end)

    Remotes.OnClient("StartTeamVote", function(colorOptions: {any})
        self:_populateVoteButtons(colorOptions)
        self:ShowVoteUI(true)
    end)

    Remotes.OnClient("TeamVoteResult", function(_colorA: any, _colorB: any)
        self:ShowVoteUI(false)
    end)

    Remotes.OnClient("ShowLoadingScreen", function(mapName: string)
        if loadingGui then loadingGui.Enabled = true end
        task.spawn(animateLoadingBar, mapName)
    end)

    Remotes.OnClient("HideLoadingScreen", function()
        if loadingGui then loadingGui.Enabled = false end
    end)

    Remotes.OnClient("ShowCountdown", function(seconds: number)
        -- Update lobby subtitle to show countdown
        local gui   = playerGui:FindFirstChild("LobbyUI")
        local lbl   = gui and gui:FindFirstChild("TextLabel", true)
        if lbl then
            task.spawn(function()
                for t = seconds, 0, -1 do
                    lbl.Text = "Game starting in " .. t .. " seconds..."
                    task.wait(1)
                end
            end)
        end
    end)

    Remotes.OnClient("ShowVictoryScreen", function(
        teamName: string, teamColor: Color3, isRoundWin: boolean
    )
        self:_showVictoryScreen(teamName, teamColor, isRoundWin)
    end)

    Remotes.OnClient("ShowPodium", function(podiumData: {any})
        self:_showPodium(podiumData)
    end)

    Remotes.OnClient("PlayConfetti", function()
        self:_spawnConfetti()
    end)
end

-- =====================================================
-- VICTORY SCREEN
-- =====================================================

function LobbyUIController:_showVictoryScreen(
    teamName: string, teamColor: Color3, isRoundWin: boolean
)
    local gui               = Instance.new("ScreenGui")
    gui.Name                = "VictoryScreen"
    gui.ResetOnSpawn        = false
    gui.ZIndexBehavior      = Enum.ZIndexBehavior.Sibling
    gui.Parent              = playerGui

    local overlay           = makeFrame(
        UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0),
        Vector2.new(0, 0),
        Color3.new(0, 0, 0), 0.45, gui)

    local title = if isRoundWin then "ROUND WINNER!" else "GAME OVER!"
    makeLabel(title,
        UDim2.new(0, 600, 0, 80),
        UDim2.new(0.5, 0, 0.35, 0),
        Vector2.new(0.5, 0.5),
        if isRoundWin then 64 else 52,
        Color3.new(1, 1, 1),
        Enum.Font.GothamBold, overlay)

    makeLabel(teamName .. " Wins!",
        UDim2.new(0, 600, 0, 60),
        UDim2.new(0.5, 0, 0.5, 0),
        Vector2.new(0.5, 0.5),
        42, teamColor, Enum.Font.GothamBold, overlay)

    -- Auto-dismiss
    local lifetime = if isRoundWin then 15 else 6
    task.delay(lifetime, function()
        if gui and gui.Parent then gui:Destroy() end
    end)
end

-- =====================================================
-- PODIUM
-- =====================================================

function LobbyUIController:_showPodium(podiumData: {any})
    local gui               = Instance.new("ScreenGui")
    gui.Name                = "PodiumScreen"
    gui.ResetOnSpawn        = false
    gui.Parent              = playerGui

    local bg                = makeFrame(
        UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0),
        Vector2.new(0, 0), Color3.new(0, 0, 0), 0.5, gui)

    makeLabel("TOP PLAYERS",
        UDim2.new(0, 400, 0, 60),
        UDim2.new(0.5, 0, 0.12, 0),
        Vector2.new(0.5, 0.5),
        44, Color3.fromRGB(255, 220, 80),
        Enum.Font.GothamBold, bg)

    local rankColors = {
        Color3.fromRGB(255, 215,   0),  -- 1st: Gold
        Color3.fromRGB(192, 192, 192),  -- 2nd: Silver
        Color3.fromRGB(205, 127,  50),  -- 3rd: Bronze
    }

    for i, entry in ipairs(podiumData) do
        local yPos = 0.25 + (i - 1) * 0.18
        makeLabel(
            "#" .. entry.rank .. "  " .. entry.playerName,
            UDim2.new(0, 500, 0, 40),
            UDim2.new(0.5, 0, yPos, 0),
            Vector2.new(0.5, 0),
            28, rankColors[i] or Color3.new(1, 1, 1),
            Enum.Font.GothamBold, bg)
        makeLabel(
            "Score: " .. entry.score
                .. "  |  Takedowns: " .. entry.takedowns
                .. "  |  Flags: " .. entry.flagCaptures,
            UDim2.new(0, 500, 0, 24),
            UDim2.new(0.5, 0, yPos + 0.065, 0),
            Vector2.new(0.5, 0),
            16, Color3.fromRGB(200, 200, 200),
            Enum.Font.Gotham, bg)
    end

    task.delay(12, function()
        if gui and gui.Parent then gui:Destroy() end
    end)
end

-- =====================================================
-- CONFETTI
-- =====================================================

function LobbyUIController:_spawnConfetti()
    local gui               = Instance.new("ScreenGui")
    gui.Name                = "Confetti"
    gui.ResetOnSpawn        = false
    gui.Parent              = playerGui

    local colors = {
        Color3.fromRGB(255, 50, 50),
        Color3.fromRGB(50, 150, 255),
        Color3.fromRGB(255, 220, 50),
        Color3.fromRGB(50, 220, 80),
        Color3.fromRGB(200, 50, 200),
    }

    for _ = 1, 60 do
        local piece             = Instance.new("Frame")
        piece.Size              = UDim2.new(0, math.random(8, 18), 0, math.random(8, 18))
        piece.Position          = UDim2.new(math.random(), 0, -0.05, 0)
        piece.BackgroundColor3  = colors[math.random(1, #colors)]
        piece.BorderSizePixel   = 0
        piece.Rotation          = math.random(0, 360)
        piece.Parent            = gui

        local fallTime  = math.random(2, 5)
        local targetY   = 1.1 + math.random() * 0.1
        TweenService:Create(piece, TweenInfo.new(fallTime, Enum.EasingStyle.Quad),
            { Position = UDim2.new(piece.Position.X.Scale, 0, targetY, 0),
              Rotation = piece.Rotation + math.random(-180, 180) }):Play()
    end

    task.delay(6, function()
        if gui and gui.Parent then gui:Destroy() end
    end)
end

-- =====================================================
-- VISIBILITY
-- =====================================================

function LobbyUIController:SetVisible(visible: boolean)
    if lobbyGui then lobbyGui.Enabled = visible end
end

function LobbyUIController:ShowVoteUI(visible: boolean)
    if voteGui then voteGui.Enabled = visible end
end

return LobbyUIController

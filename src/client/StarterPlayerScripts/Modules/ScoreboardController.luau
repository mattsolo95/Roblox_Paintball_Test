--!strict
-- ScoreboardController.luau (Client Module)
-- Press and hold Tab to show a full scoreboard. Release to hide it.
-- Shows all players with points, takedowns, deaths, assists, flag captures.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Remotes           = require(game:GetService("ReplicatedStorage"):WaitForChild("Remotes"))

local ScoreboardController  = {}
local localPlayer           = Players.LocalPlayer
local playerGui             = localPlayer:WaitForChild("PlayerGui")

local screenGui:    ScreenGui?  = nil
local mainFrame:    Frame?      = nil

-- Latest data received from server
local _lastData: any = nil

-- =====================================================
-- BUILD UI
-- =====================================================

local function makeLabel(
    text: string, size: UDim2, pos: UDim2, anchor: Vector2,
    fontSize: number, color: Color3, font: Enum.Font, parent: Instance
): TextLabel
    local lbl               = Instance.new("TextLabel")
    lbl.Text                = text
    lbl.Size                = size
    lbl.Position            = pos
    lbl.AnchorPoint         = anchor
    lbl.Font                = font
    lbl.TextSize            = fontSize
    lbl.TextColor3          = color
    lbl.BackgroundTransparency = 1
    lbl.TextXAlignment      = Enum.TextXAlignment.Left
    lbl.TextStrokeTransparency = 0.5
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

function ScoreboardController:Initialize()
    screenGui               = Instance.new("ScreenGui")
    screenGui.Name          = "Scoreboard"
    screenGui.ResetOnSpawn  = false
    screenGui.Enabled       = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent        = playerGui

    -- Dark backdrop
    local bg                = makeFrame(
        UDim2.new(0, 700, 0, 500),
        UDim2.new(0.5, 0, 0.5, 0),
        Vector2.new(0.5, 0.5),
        Color3.new(0, 0, 0), 0.25, screenGui)
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 12)
    mainFrame = bg

    -- Header
    makeLabel("SCOREBOARD",
        UDim2.new(1, 0, 0, 36),
        UDim2.new(0.5, 0, 0, 10),
        Vector2.new(0.5, 0),
        28, Color3.fromRGB(255, 230, 100), Enum.Font.GothamBold, bg)

    makeLabel("Press Tab to toggle",
        UDim2.new(1, 0, 0, 20),
        UDim2.new(0.5, 0, 0, 44),
        Vector2.new(0.5, 0),
        13, Color3.fromRGB(160, 160, 160), Enum.Font.Gotham, bg)

    -- Tab key toggle
    UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.Tab then
            self:_show()
        end
    end)
    UserInputService.InputEnded:Connect(function(input: InputObject)
        if input.KeyCode == Enum.KeyCode.Tab then
            self:_hide()
        end
    end)

    -- Listen for scoreboard data from server
    Remotes.OnClient("ScoreboardUpdate", function(data: any)
        _lastData = data
        if screenGui and screenGui.Enabled then
            self:_populate(data)
        end
    end)
end

-- =====================================================
-- SHOW / HIDE
-- =====================================================

function ScoreboardController:_show()
    if not screenGui then return end
    screenGui.Enabled = true
    if _lastData then self:_populate(_lastData) end
end

function ScoreboardController:_hide()
    if not screenGui then return end
    screenGui.Enabled = false
end

-- =====================================================
-- POPULATE TABLE
-- =====================================================

function ScoreboardController:_populate(data: any)
    if not mainFrame then return end

    -- Clear old rows
    for _, child in ipairs(mainFrame:GetChildren()) do
        if child.Name == "Row" or child.Name == "TeamHeader" or child.Name == "ColHeader" then
            child:Destroy()
        end
    end

    local colHeaders = {"Player", "Points", "Takedowns", "Deaths", "Assists", "Flags"}
    local colW = {200, 80, 90, 70, 70, 60}
    local startY = 70
    local rowH = 26

    local function makeRow(yOffset: number, values: {string}, rowColor: Color3, transparency: number)
        local row   = makeFrame(
            UDim2.new(0, 660, 0, rowH),
            UDim2.new(0.5, 0, 0, yOffset),
            Vector2.new(0.5, 0),
            rowColor, transparency, mainFrame)
        row.Name    = "Row"
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local xCursor = 8
        for i, val in ipairs(values) do
            local lbl           = Instance.new("TextLabel")
            lbl.Size            = UDim2.new(0, colW[i] - 4, 1, 0)
            lbl.Position        = UDim2.new(0, xCursor, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text            = val
            lbl.Font            = Enum.Font.Gotham
            lbl.TextSize        = 14
            lbl.TextColor3      = Color3.new(1, 1, 1)
            lbl.TextXAlignment  = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
            lbl.Parent          = row
            xCursor             += colW[i]
        end
        return row
    end

    -- Column headers
    local headerRow = makeRow(startY, colHeaders, Color3.fromRGB(40, 40, 40), 0.3)
    headerRow.Name  = "ColHeader"
    for _, lbl in ipairs(headerRow:GetChildren()) do
        if lbl:IsA("TextLabel") then
            lbl.TextColor3  = Color3.fromRGB(220, 200, 100)
            lbl.Font        = Enum.Font.GothamBold
        end
    end
    startY += rowH + 4

    if not data then return end

    -- Team A section
    local teamAColor = (data.teamAColor and Color3.fromRGB(
        data.teamAColor.R * 255, data.teamAColor.G * 255, data.teamAColor.B * 255))
        or Color3.fromRGB(200, 50, 50)

    local teamAHeader = makeFrame(
        UDim2.new(0, 660, 0, 22),
        UDim2.new(0.5, 0, 0, startY),
        Vector2.new(0.5, 0),
        teamAColor, 0.25, mainFrame)
    teamAHeader.Name = "TeamHeader"
    Instance.new("UICorner", teamAHeader).CornerRadius = UDim.new(0, 4)
    local taLbl = Instance.new("TextLabel", teamAHeader)
    taLbl.Size = UDim2.new(1, -8, 1, 0); taLbl.Position = UDim2.new(0, 8, 0, 0)
    taLbl.BackgroundTransparency = 1
    taLbl.Text = (data.teamAName or "Team Alpha") .. "  —  " .. (data.teamAScore or 0) .. " pts"
    taLbl.Font = Enum.Font.GothamBold; taLbl.TextSize = 14
    taLbl.TextColor3 = Color3.new(1, 1, 1)
    startY += 26

    if data.teamAPlayers then
        for _, p in ipairs(data.teamAPlayers) do
            local highlight = p.name == localPlayer.Name
            makeRow(startY, {
                p.name, tostring(p.points), tostring(p.takedowns),
                tostring(p.deaths), tostring(p.assists), tostring(p.flags)
            }, if highlight then Color3.fromRGB(80, 80, 20) else Color3.fromRGB(20, 20, 20),
               if highlight then 0.2 else 0.5)
            startY += rowH + 2
        end
    end

    startY += 6

    -- Team B section
    local teamBColor = (data.teamBColor and Color3.fromRGB(
        data.teamBColor.R * 255, data.teamBColor.G * 255, data.teamBColor.B * 255))
        or Color3.fromRGB(50, 80, 220)

    local teamBHeader = makeFrame(
        UDim2.new(0, 660, 0, 22),
        UDim2.new(0.5, 0, 0, startY),
        Vector2.new(0.5, 0),
        teamBColor, 0.25, mainFrame)
    teamBHeader.Name = "TeamHeader"
    Instance.new("UICorner", teamBHeader).CornerRadius = UDim.new(0, 4)
    local tbLbl = Instance.new("TextLabel", teamBHeader)
    tbLbl.Size = UDim2.new(1, -8, 1, 0); tbLbl.Position = UDim2.new(0, 8, 0, 0)
    tbLbl.BackgroundTransparency = 1
    tbLbl.Text = (data.teamBName or "Team Bravo") .. "  —  " .. (data.teamBScore or 0) .. " pts"
    tbLbl.Font = Enum.Font.GothamBold; tbLbl.TextSize = 14
    tbLbl.TextColor3 = Color3.new(1, 1, 1)
    startY += 26

    if data.teamBPlayers then
        for _, p in ipairs(data.teamBPlayers) do
            local highlight = p.name == localPlayer.Name
            makeRow(startY, {
                p.name, tostring(p.points), tostring(p.takedowns),
                tostring(p.deaths), tostring(p.assists), tostring(p.flags)
            }, if highlight then Color3.fromRGB(20, 40, 80) else Color3.fromRGB(20, 20, 20),
               if highlight then 0.2 else 0.5)
            startY += rowH + 2
        end
    end

    -- Resize frame to content
    if mainFrame then
        mainFrame.Size = UDim2.new(0, 700, 0, math.max(startY + 20, 200))
    end
end

return ScoreboardController

--!strict
-- NoManZoneClient.luau (Client Module)
-- Detects when the local player is in the No Man's Zone.
-- Shows a red screen tint + "You have entered the No Man's Zone" message.
-- Uses NMZBound trigger parts placed by MapManager.

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")
local Lighting      = game:GetService("Lighting")

local Remotes       = require(game:GetService("ReplicatedStorage"):WaitForChild("Remotes"))

local NoManZoneClient   = {}
local localPlayer       = Players.LocalPlayer

local _inNMZ            = false
local _nmzColorCorrect: ColorCorrectionEffect?  = nil
local _nmzLabel: TextLabel?                     = nil
local _screenGui: ScreenGui?                    = nil
local _checkConn: RBXScriptConnection?          = nil

-- =====================================================
-- INITIALIZE
-- =====================================================

function NoManZoneClient:Initialize()
    -- Red ColorCorrection for the tint
    local cc                = Instance.new("ColorCorrectionEffect")
    cc.Name                 = "NMZ_Tint"
    cc.TintColor            = Color3.fromRGB(255, 180, 180)
    cc.Saturation           = 0.3
    cc.Brightness           = -0.05
    cc.Enabled              = false
    cc.Parent               = Lighting
    _nmzColorCorrect        = cc

    -- Screen label
    local gui               = Instance.new("ScreenGui")
    gui.Name                = "NMZOverlay"
    gui.ResetOnSpawn        = false
    gui.ZIndexBehavior      = Enum.ZIndexBehavior.Sibling
    gui.Parent              = localPlayer:WaitForChild("PlayerGui")
    _screenGui              = gui

    local lbl               = Instance.new("TextLabel")
    lbl.Name                = "NMZText"
    lbl.Size                = UDim2.new(0.8, 0, 0, 60)
    lbl.Position            = UDim2.new(0.5, 0, 0, 80)
    lbl.AnchorPoint         = Vector2.new(0.5, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                = "You have entered the No Man's Zone  •  Kills here are worth DOUBLE!"
    lbl.Font                = Enum.Font.GothamBold
    lbl.TextSize            = 22
    lbl.TextColor3          = Color3.fromRGB(255, 80, 80)
    lbl.TextStrokeTransparency = 0.3
    lbl.TextStrokeColor3    = Color3.new(0, 0, 0)
    lbl.TextWrapped         = true
    lbl.Visible             = false
    lbl.Parent              = gui
    _nmzLabel               = lbl

    -- Poll character position against NMZ bounds every half-second
    _checkConn = RunService.Heartbeat:Connect(function()
        self:_checkNMZ()
    end)

    -- Also react to server-sent events (belt and suspenders)
    Remotes.OnClient("NoManZoneEntered", function()
        self:_enter()
    end)
    Remotes.OnClient("NoManZoneExited", function()
        self:_exit()
    end)
end

-- =====================================================
-- POSITION-BASED NMZ DETECTION (client side, immediate)
-- =====================================================

function NoManZoneClient:_checkNMZ()
    local char  = localPlayer.Character
    local hrp   = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end

    local nmzFolder = workspace:FindFirstChild("NMZBounds")
    if not nmzFolder then return end

    local boundA = nmzFolder:FindFirstChild("NMZBound_A") :: BasePart?
    local boundB = nmzFolder:FindFirstChild("NMZBound_B") :: BasePart?
    if not boundA or not boundB then return end

    -- NMZ is between the two bounds on the Z axis
    local zA    = boundA.Position.Z
    local zB    = boundB.Position.Z
    local zMin  = math.min(zA, zB)
    local zMax  = math.max(zA, zB)
    local playerZ = hrp.Position.Z

    local nowInNMZ = (playerZ > zMin and playerZ < zMax)

    if nowInNMZ and not _inNMZ then
        self:_enter()
        Remotes.FireServer("NoManZoneEntered")  -- notify server for score multiplier
    elseif not nowInNMZ and _inNMZ then
        self:_exit()
        Remotes.FireServer("NoManZoneExited")
    end
end

-- =====================================================
-- VISUAL EFFECTS
-- =====================================================

function NoManZoneClient:_enter()
    if _inNMZ then return end
    _inNMZ = true

    if _nmzColorCorrect then
        _nmzColorCorrect.Enabled = true
    end
    if _nmzLabel then
        _nmzLabel.Visible       = true
        _nmzLabel.TextTransparency = 0
        -- Pulse it once
        TweenService:Create(_nmzLabel, TweenInfo.new(0.2, Enum.EasingStyle.Bounce),
            { TextSize = 26 }):Play()
        task.delay(0.25, function()
            if _nmzLabel then
                TweenService:Create(_nmzLabel, TweenInfo.new(0.2), { TextSize = 22 }):Play()
            end
        end)
        -- Fade out label after 3 seconds (tint stays)
        task.delay(3, function()
            if _inNMZ and _nmzLabel then
                TweenService:Create(_nmzLabel, TweenInfo.new(1),
                    { TextTransparency = 1 }):Play()
            end
        end)
    end
end

function NoManZoneClient:_exit()
    if not _inNMZ then return end
    _inNMZ = false

    if _nmzColorCorrect then
        _nmzColorCorrect.Enabled = false
    end
    if _nmzLabel then
        _nmzLabel.Visible       = false
        _nmzLabel.TextTransparency = 0
    end
end

return NoManZoneClient

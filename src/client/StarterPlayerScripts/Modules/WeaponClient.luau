--!strict
-- WeaponClient.luau (Client Module)
-- Detects when the player equips a Tool, sends fire requests to the server,
-- plays shoot sound, shows hit markers, and renders paint splat effects.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig    = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes       = require(ReplicatedStorage:WaitForChild("Remotes"))

local WeaponClient  = {}
local localPlayer   = Players.LocalPlayer
local camera        = workspace.CurrentCamera

local currentTool:      Tool?               = nil
local currentWeapon:    string              = GameConfig.DEFAULT_WEAPON
local lastFireTime:     number              = 0

-- UI elements
local hitMarker:    Frame?      = nil
local crosshairParts: {Frame}   = {}
local screenGui:    ScreenGui?  = nil

-- =====================================================
-- INITIALIZE
-- =====================================================

function WeaponClient:Initialize()
    self:_buildUI()
    self:_hookRemotes()
    self:_watchCharacter()
end

-- =====================================================
-- UI — CROSSHAIR + HIT MARKER
-- =====================================================

function WeaponClient:_buildUI()
    screenGui               = Instance.new("ScreenGui")
    screenGui.Name          = "WeaponUI"
    screenGui.ResetOnSpawn  = false
    screenGui.Parent        = localPlayer:WaitForChild("PlayerGui")

    -- Crosshair (4 lines: top, bottom, left, right)
    local function makeLine(size: UDim2, pos: UDim2): Frame
        local f                 = Instance.new("Frame")
        f.Size                  = size
        f.Position              = pos
        f.AnchorPoint           = Vector2.new(0.5, 0.5)
        f.BackgroundColor3      = Color3.new(1, 1, 1)
        f.BackgroundTransparency = 0.1
        f.BorderSizePixel       = 0
        f.Visible               = false     -- hidden until tool equipped
        f.Parent                = screenGui
        table.insert(crosshairParts, f)
        return f
    end

    makeLine(UDim2.new(0, 2, 0, 12), UDim2.new(0.5, 0, 0.5, -10))  -- top
    makeLine(UDim2.new(0, 2, 0, 12), UDim2.new(0.5, 0, 0.5,  10))  -- bottom
    makeLine(UDim2.new(0, 12, 0, 2), UDim2.new(0.5,-10, 0.5,   0)) -- left
    makeLine(UDim2.new(0, 12, 0, 2), UDim2.new(0.5, 10, 0.5,   0)) -- right

    -- Hit marker (X shape, flashes on hit)
    local hm                = Instance.new("Frame")
    hm.Name                 = "HitMarker"
    hm.Size                 = UDim2.new(0, 28, 0, 28)
    hm.AnchorPoint          = Vector2.new(0.5, 0.5)
    hm.Position             = UDim2.new(0.5, 0, 0.5, 0)
    hm.BackgroundTransparency = 1
    hm.Visible              = false
    hm.Parent               = screenGui

    local function makeHMLine(rot: number)
        local l             = Instance.new("Frame")
        l.Size              = UDim2.new(0, 22, 0, 2)
        l.AnchorPoint       = Vector2.new(0.5, 0.5)
        l.Position          = UDim2.new(0.5, 0, 0.5, 0)
        l.Rotation          = rot
        l.BackgroundColor3  = Color3.fromRGB(255, 50, 50)
        l.BorderSizePixel   = 0
        l.Parent            = hm
    end
    makeHMLine(45)
    makeHMLine(-45)
    hitMarker = hm
end

function WeaponClient:_setCrosshairVisible(visible: boolean)
    for _, line in ipairs(crosshairParts) do
        line.Visible = visible
    end
end

-- =====================================================
-- WATCH CHARACTER FOR TOOL EQUIP/UNEQUIP
-- =====================================================

function WeaponClient:_watchCharacter()
    local function connectCharacter(char: Model)
        -- Catch tools equipped after character spawns
        char.ChildAdded:Connect(function(child: Instance)
            if child:IsA("Tool") then
                self:_onToolEquipped(child :: Tool)
            end
        end)
        char.ChildRemoved:Connect(function(child: Instance)
            if child:IsA("Tool") and child == currentTool then
                self:_onToolUnequipped()
            end
        end)
        -- If a tool is already in hand on spawn
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                self:_onToolEquipped(child :: Tool)
            end
        end
    end

    if localPlayer.Character then
        connectCharacter(localPlayer.Character)
    end
    localPlayer.CharacterAdded:Connect(connectCharacter)
end

-- =====================================================
-- TOOL EQUIP / UNEQUIP
-- =====================================================

function WeaponClient:_onToolEquipped(tool: Tool)
    currentTool     = tool
    currentWeapon   = tool.Name
    self:_setCrosshairVisible(true)

    -- Connect firing to Tool.Activated (fires on left-click while equipped)
    tool.Activated:Connect(function()
        self:_tryFire()
    end)
end

function WeaponClient:_onToolUnequipped()
    currentTool = nil
    self:_setCrosshairVisible(false)
end

-- =====================================================
-- FIRE
-- =====================================================

function WeaponClient:_tryFire()
    local weaponCfg = GameConfig.WEAPONS[currentWeapon]
    if not weaponCfg then return end

    local now = os.clock()
    if now - lastFireTime < weaponCfg.fireRate then return end
    lastFireTime = now

    local char  = localPlayer.Character
    local hrp   = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end

    -- Direction from center of screen
    local unitRay   = camera:ScreenPointToRay(
        camera.ViewportSize.X / 2,
        camera.ViewportSize.Y / 2
    )
    local origin    = hrp.Position + Vector3.new(0, 1.5, 0)
    local direction = unitRay.Direction

    Remotes.FireServer("WeaponFired", currentWeapon, origin, direction)

    -- Play shoot sound on the tool handle
    if currentTool then
        local handle = currentTool:FindFirstChild("Handle") :: BasePart?
        if handle then
            local sound = handle:FindFirstChild("ShootSound") :: Sound?
            if sound and sound.SoundId ~= "" then sound:Play() end
        end
    end

    -- Crosshair bloom (spread out slightly on fire)
    local offsets = {
        UDim2.new(0.5, 0, 0.5, -16),
        UDim2.new(0.5, 0, 0.5,  16),
        UDim2.new(0.5,-16, 0.5,   0),
        UDim2.new(0.5, 16, 0.5,   0),
    }
    local restPositions = {
        UDim2.new(0.5, 0, 0.5, -10),
        UDim2.new(0.5, 0, 0.5,  10),
        UDim2.new(0.5,-10, 0.5,   0),
        UDim2.new(0.5, 10, 0.5,   0),
    }
    for i, line in ipairs(crosshairParts) do
        TweenService:Create(line, TweenInfo.new(0.05), { Position = offsets[i] }):Play()
        task.delay(0.12, function()
            TweenService:Create(line, TweenInfo.new(0.15), { Position = restPositions[i] }):Play()
        end)
    end
end

-- =====================================================
-- SERVER EVENT HOOKS
-- =====================================================

function WeaponClient:_hookRemotes()
    -- Flash hit marker when we get a takedown
    Remotes.OnClient("TakedownEvent", function(attackerName: string, _v, _p, _z)
        if attackerName == localPlayer.Name then
            self:_flashHitMarker(Color3.fromRGB(255, 210, 50))  -- gold for kill
        end
    end)

    -- Flash red on a damage hit (from HitEffect, check if near a player we shot)
    Remotes.OnClient("HitEffect", function(pos: Vector3, normal: Vector3, color: Color3)
        self:_spawnPaintSplat(pos, normal, color)
    end)
end

-- =====================================================
-- HIT MARKER
-- =====================================================

function WeaponClient:_flashHitMarker(color: Color3)
    if not hitMarker then return end
    for _, line in ipairs(hitMarker:GetChildren()) do
        if line:IsA("Frame") then line.BackgroundColor3 = color end
    end
    hitMarker.Visible = true
    task.delay(0.2, function()
        if hitMarker then hitMarker.Visible = false end
    end)
end

-- =====================================================
-- PAINT SPLAT (client-side visual)
-- =====================================================

function WeaponClient:_spawnPaintSplat(pos: Vector3, normal: Vector3, color: Color3)
    local part              = Instance.new("Part")
    part.Size               = Vector3.new(0.1, 0.1, 0.1)
    part.Anchored           = true
    part.CanCollide         = false
    part.Transparency       = 1
    part.CFrame             = CFrame.new(pos, pos + normal)
    part.Parent             = workspace

    local decal             = Instance.new("Decal")
    decal.Texture           = "rbxassetid://7546611"
    decal.Color3            = color
    decal.Face              = Enum.NormalId.Front
    decal.Parent            = part

    local emitter           = Instance.new("ParticleEmitter")
    emitter.Color           = ColorSequence.new(color)
    emitter.LightEmission   = 0.5
    emitter.Size            = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.35),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Lifetime        = NumberRange.new(0.3, 0.7)
    emitter.Speed           = NumberRange.new(6, 18)
    emitter.SpreadAngle     = Vector2.new(50, 50)
    emitter.Rate            = 0
    emitter.Parent          = part
    emitter:Emit(10)

    task.delay(15, function()
        if part and part.Parent then
            TweenService:Create(decal, TweenInfo.new(2), { Transparency = 1 }):Play()
            task.delay(2, function() if part then part:Destroy() end end)
        end
    end)
end

return WeaponClient

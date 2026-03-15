--!strict
-- WeaponClient.luau (Client Module)
-- Handles weapon input, muzzle flash, hit markers, and reload feedback.
-- Sends fire requests to the server (server does actual hit detection).

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig        = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes           = require(ReplicatedStorage:WaitForChild("Remotes"))

local WeaponClient  = {}
local localPlayer   = Players.LocalPlayer
local camera        = workspace.CurrentCamera

-- Current weapon state
local currentWeapon     = GameConfig.DEFAULT_WEAPON
local currentAmmo       = 0
local maxAmmo           = 0
local isReloading       = false
local lastFireTime      = 0

-- UI references
local hitMarker: Frame?         = nil
local crosshair: Frame?         = nil
local screenGui: ScreenGui?     = nil

-- =====================================================
-- INITIALIZE
-- =====================================================

function WeaponClient:Initialize()
    local weaponCfg = GameConfig.WEAPONS[currentWeapon]
    currentAmmo     = weaponCfg.ammo
    maxAmmo         = weaponCfg.ammo

    self:_buildCrosshairUI()
    self:_hookInput()
    self:_hookRemotes()
end

-- =====================================================
-- UI
-- =====================================================

function WeaponClient:_buildCrosshairUI()
    screenGui               = Instance.new("ScreenGui")
    screenGui.Name          = "WeaponUI"
    screenGui.ResetOnSpawn  = false
    screenGui.Parent        = localPlayer:WaitForChild("PlayerGui")

    -- Crosshair (4 lines)
    local cx = Instance.new("Frame")
    cx.Name                 = "Crosshair"
    cx.Size                 = UDim2.new(0, 2, 0, 16)
    cx.AnchorPoint          = Vector2.new(0.5, 0.5)
    cx.Position             = UDim2.new(0.5, 0, 0.5, -10)
    cx.BackgroundColor3     = Color3.new(1, 1, 1)
    cx.BorderSizePixel      = 0
    cx.Parent               = screenGui
    crosshair               = cx

    local cx2               = cx:Clone()
    cx2.Position            = UDim2.new(0.5, 0, 0.5, 10)
    cx2.Parent              = screenGui

    local cx3               = cx:Clone()
    cx3.Size                = UDim2.new(0, 16, 0, 2)
    cx3.Position            = UDim2.new(0.5, -10, 0.5, 0)
    cx3.Parent              = screenGui

    local cx4               = cx:Clone()
    cx4.Size                = UDim2.new(0, 16, 0, 2)
    cx4.Position            = UDim2.new(0.5, 10, 0.5, 0)
    cx4.Parent              = screenGui

    -- Hit marker (flash on hit confirmation)
    local hm                = Instance.new("Frame")
    hm.Name                 = "HitMarker"
    hm.Size                 = UDim2.new(0, 24, 0, 24)
    hm.AnchorPoint          = Vector2.new(0.5, 0.5)
    hm.Position             = UDim2.new(0.5, 0, 0.5, 0)
    hm.BackgroundTransparency = 1
    hm.BorderSizePixel      = 0
    hm.Visible              = false
    hm.Parent               = screenGui

    -- X lines for hit marker
    local function makeHMLine(rot: number)
        local line          = Instance.new("Frame")
        line.Size           = UDim2.new(0, 20, 0, 2)
        line.AnchorPoint    = Vector2.new(0.5, 0.5)
        line.Position       = UDim2.new(0.5, 0, 0.5, 0)
        line.Rotation       = rot
        line.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
        line.BorderSizePixel = 0
        line.Parent         = hm
    end
    makeHMLine(45)
    makeHMLine(-45)
    hitMarker               = hm
end

-- =====================================================
-- INPUT
-- =====================================================

function WeaponClient:_hookInput()
    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed then return end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:_tryFire()
        elseif input.KeyCode == Enum.KeyCode.R then
            self:_reload()
        end
    end)

    -- Auto-fire while holding mouse (for full-auto feel on standard gun)
    RunService.Heartbeat:Connect(function()
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            local weaponCfg = GameConfig.WEAPONS[currentWeapon]
            if weaponCfg and not weaponCfg.isHitscan then
                -- Only auto-fire for non-hitscan (sniper is always semi)
                self:_tryFire()
            end
        end
    end)
end

function WeaponClient:_tryFire()
    if isReloading then return end
    if currentAmmo <= 0 then
        self:_reload()
        return
    end

    local weaponCfg = GameConfig.WEAPONS[currentWeapon]
    if not weaponCfg then return end

    local now = os.clock()
    if now - lastFireTime < weaponCfg.fireRate then return end
    lastFireTime = now

    -- Build fire direction from camera
    local char  = localPlayer.Character
    local hrp   = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end

    local unitRay   = camera:ScreenPointToRay(
        camera.ViewportSize.X / 2,
        camera.ViewportSize.Y / 2
    )
    local origin    = hrp.Position + Vector3.new(0, 1.5, 0)
    local direction = unitRay.Direction

    -- Apply client-side spread for visual feedback
    local spread = weaponCfg.spread
    if spread > 0 then
        direction = (direction + Vector3.new(
            (math.random() - 0.5) * spread,
            (math.random() - 0.5) * spread,
            (math.random() - 0.5) * spread
        )).Unit
    end

    Remotes.FireServer("WeaponFired", currentWeapon, origin, direction)

    currentAmmo -= 1
    Remotes.FireClient and nil  -- ammo update will come from server

    -- Local ammo display feedback (optimistic)
    Remotes.FireServer and nil
    -- Directly update HUD client-side for responsiveness
    local ammoUpdateRemote = game:GetService("ReplicatedStorage")
        :FindFirstChild("GameRemotes")
    if ammoUpdateRemote then
        -- We'll rely on AmmoUpdate events from server, but also visually expand crosshair
    end

    -- Crosshair spread feedback
    if crosshair then
        TweenService:Create(crosshair, TweenInfo.new(0.05),
            { Position = UDim2.new(0.5, 0, 0.5, -16) }):Play()
        task.delay(0.12, function()
            if crosshair then
                TweenService:Create(crosshair, TweenInfo.new(0.15),
                    { Position = UDim2.new(0.5, 0, 0.5, -10) }):Play()
            end
        end)
    end

    if currentAmmo <= 0 then
        task.delay(0.1, function() self:_reload() end)
    end
end

function WeaponClient:_reload()
    if isReloading or currentAmmo == maxAmmo then return end
    isReloading = true

    -- Visual feedback: will show "Reloading..." via AmmoUpdate from server
    local weaponCfg = GameConfig.WEAPONS[currentWeapon]
    if not weaponCfg then isReloading = false; return end

    task.delay(weaponCfg.reloadTime, function()
        currentAmmo = maxAmmo
        isReloading = false
    end)
end

-- =====================================================
-- SERVER REMOTES
-- =====================================================

function WeaponClient:_hookRemotes()
    Remotes.OnClient("AmmoUpdate", function(current: number, max: number, _reloading: boolean)
        currentAmmo = current
        maxAmmo     = max
        -- HUDController listens to this same event for display
    end)

    -- Show hit marker when server confirms our shot hit someone
    Remotes.OnClient("TakedownEvent", function(_attacker: string, _victim: string, _points: number, _inNMZ: boolean)
        -- Only flash if we're the attacker (checked by name)
        if _attacker == localPlayer.Name then
            self:_flashHitMarker(true)
        end
    end)

    Remotes.OnClient("HitEffect", function(pos: Vector3, normal: Vector3, color: Color3)
        self:_spawnHitEffect(pos, normal, color)
    end)
end

-- =====================================================
-- HIT MARKER FLASH
-- =====================================================

function WeaponClient:_flashHitMarker(isElimination: boolean)
    if not hitMarker then return end
    hitMarker.Visible = true

    local flashColor = if isElimination
        then Color3.fromRGB(255, 200, 50)   -- gold for elimination
        else Color3.fromRGB(255, 50, 50)    -- red for hit

    for _, line in ipairs(hitMarker:GetChildren()) do
        if line:IsA("Frame") then
            line.BackgroundColor3 = flashColor
        end
    end

    task.delay(0.18, function()
        if hitMarker then hitMarker.Visible = false end
    end)
end

-- =====================================================
-- PAINT SPLAT EFFECT (client-side visual)
-- =====================================================

function WeaponClient:_spawnHitEffect(pos: Vector3, normal: Vector3, color: Color3)
    -- Paint splat decal on the surface
    local splatPart             = Instance.new("Part")
    splatPart.Size              = Vector3.new(0.1, 0.1, 0.1)
    splatPart.Anchored          = true
    splatPart.CanCollide        = false
    splatPart.Transparency      = 1
    splatPart.CFrame            = CFrame.new(pos, pos + normal)
    splatPart.Parent            = workspace

    local decal                 = Instance.new("Decal")
    decal.Texture               = "rbxassetid://7546611"   -- paint blob texture
    decal.Color3                = color
    decal.Face                  = Enum.NormalId.Front
    decal.Parent                = splatPart

    -- Particle burst
    local emitter               = Instance.new("ParticleEmitter")
    emitter.Color               = ColorSequence.new(color)
    emitter.LightEmission       = 0.4
    emitter.Size                = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Lifetime            = NumberRange.new(0.4, 0.8)
    emitter.Speed               = NumberRange.new(8, 20)
    emitter.SpreadAngle         = Vector2.new(45, 45)
    emitter.RotSpeed            = NumberRange.new(-180, 180)
    emitter.Rate                = 0
    emitter.Parent              = splatPart
    emitter:Emit(12)

    -- Fade decal over 15 seconds, then clean up
    task.delay(15, function()
        if splatPart and splatPart.Parent then
            TweenService:Create(decal, TweenInfo.new(2), { Transparency = 1 }):Play()
            task.delay(2, function()
                if splatPart then splatPart:Destroy() end
            end)
        end
    end)
end

return WeaponClient

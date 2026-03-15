--!strict
-- PowerUpManager.luau (Server Module)
-- Manages the center health power-up block.
-- First player to touch it gains 2.5x max health and full heal.
-- Respawns every 90 seconds.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes    = require(ReplicatedStorage:WaitForChild("Remotes"))

local PowerUpManager = {}

local _block:       BasePart?               = nil
local _touchConn:   RBXScriptConnection?    = nil
local _pulseConn:   RBXScriptConnection?    = nil
local _respawnThread: thread?               = nil
local _active       = false

-- =====================================================
-- BLOCK CREATION / INITIALIZATION
-- =====================================================

function PowerUpManager:Initialize()
    self:Cleanup()

    -- Look for pre-placed block (MapManager names it "CenterPowerUp")
    local existing = workspace:FindFirstChild("CenterPowerUp")
    if existing and existing:IsA("BasePart") then
        _block = existing :: BasePart
    else
        -- Create one at world center if missing
        local part          = Instance.new("Part")
        part.Name           = "CenterPowerUp"
        part.Anchored       = true
        part.Size           = Vector3.new(5, 5, 5)
        part.CFrame         = CFrame.new(0, 5, 0)
        part.Material       = Enum.Material.Neon
        part.Color          = Color3.fromRGB(255, 220, 50)
        part.CastShadow     = false
        part.Parent         = workspace
        _block              = part
    end

    self:_makeActive()
end

function PowerUpManager:_makeActive()
    if not _block then return end
    _active             = true
    _block.Transparency = 0
    _block.CanTouch     = true

    -- Glowing point light
    local light = _block:FindFirstChildOfClass("PointLight")
        or Instance.new("PointLight", _block)
    light.Brightness    = 5
    light.Range         = 20
    light.Color         = Color3.fromRGB(255, 220, 50)

    -- Pulsing scale effect (rotates for visual appeal)
    local RunService = game:GetService("RunService")
    _pulseConn = RunService.Heartbeat:Connect(function()
        if _block and _block.Parent then
            _block.CFrame = _block.CFrame * CFrame.Angles(0, 0.015, 0)
        end
    end)

    -- Touch detection
    _touchConn = _block.Touched:Connect(function(hit: BasePart)
        if not _active then return end

        local char = hit.Parent
        if not char then return end
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end

        local humanoid = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid or humanoid.Health <= 0 then return end

        self:_applyPowerUp(player, humanoid)
    end)
end

-- =====================================================
-- POWER-UP EFFECT
-- =====================================================

function PowerUpManager:_applyPowerUp(player: Player, humanoid: Humanoid)
    _active = false    -- only one player can collect it

    local newMaxHealth  = GameConfig.DEFAULT_MAX_HEALTH * GameConfig.POWERUP_HEALTH_MULT
    humanoid.MaxHealth  = newMaxHealth
    humanoid.Health     = newMaxHealth   -- full heal

    Remotes.FireAll("PowerUpCollected", player.Name)
    print("[PowerUpManager]", player.Name, "collected power-up →", newMaxHealth, "HP")

    -- Hide the block
    if _block then
        _block.Transparency = 1
        _block.CanTouch     = false
    end
    if _touchConn then _touchConn:Disconnect(); _touchConn = nil end
    if _pulseConn then _pulseConn:Disconnect(); _pulseConn = nil end

    -- Respawn after 90 seconds
    _respawnThread = task.delay(GameConfig.POWERUP_RESPAWN_TIME, function()
        self:_makeActive()
        Remotes.FireAll("PowerUpRespawned")
        print("[PowerUpManager] Power-up respawned.")
    end)

    -- Restore player's max health after their next death (so 2.5x doesn't persist forever)
    local diedConn: RBXScriptConnection
    diedConn = humanoid.Died:Connect(function()
        humanoid.MaxHealth = GameConfig.DEFAULT_MAX_HEALTH
        diedConn:Disconnect()
    end)
end

-- =====================================================
-- CLEANUP
-- =====================================================

function PowerUpManager:Cleanup()
    _active = false
    if _touchConn then _touchConn:Disconnect(); _touchConn = nil end
    if _pulseConn then _pulseConn:Disconnect(); _pulseConn = nil end
    if _respawnThread then task.cancel(_respawnThread); _respawnThread = nil end
    if _block then _block:Destroy(); _block = nil end
end

return PowerUpManager

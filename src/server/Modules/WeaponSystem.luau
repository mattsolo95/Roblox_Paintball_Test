--!strict
-- WeaponSystem.luau (Server Module)
-- Validates weapon fire requests from clients, performs hit detection,
-- applies damage, and triggers paint-splat effects.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local GameConfig    = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes       = require(ReplicatedStorage:WaitForChild("Remotes"))

local WeaponSystem  = {}

-- Injected by GameStateManager after module load
local _scoringManager: any  = nil
local _teamManager: any     = nil

-- Per-player fire-rate throttle
local lastFireTime: {[Player]: number}  = {}
-- Per-player active weapon
local playerWeapon: {[Player]: string}  = {}

-- Active projectile parts (for cleanup)
local activeProjectiles: {BasePart}     = {}

-- Anti-cheat: max stud distance a player can be from fire origin
local MAX_ORIGIN_DISTANCE = 20

-- =====================================================
-- PUBLIC API
-- =====================================================

function WeaponSystem:SetDependencies(scoringMgr: any, teamMgr: any)
    _scoringManager = scoringMgr
    _teamManager    = teamMgr
end

function WeaponSystem:Initialize()
    lastFireTime    = {}
    playerWeapon    = {}
    -- Give all players their default weapon
    for _, player in ipairs(Players:GetPlayers()) do
        playerWeapon[player] = GameConfig.DEFAULT_WEAPON
    end
end

function WeaponSystem:Cleanup()
    for _, proj in ipairs(activeProjectiles) do
        if proj and proj.Parent then proj:Destroy() end
    end
    activeProjectiles = {}
end

function WeaponSystem:GiveWeapon(player: Player, weaponName: string)
    if GameConfig.WEAPONS[weaponName] then
        playerWeapon[player] = weaponName
        -- Notify client so HUD updates
        Remotes.FireClient("AmmoUpdate", player,
            GameConfig.WEAPONS[weaponName].ammo,
            GameConfig.WEAPONS[weaponName].ammo,
            false)
    end
end

-- =====================================================
-- FIRE REQUEST (from client)
-- =====================================================

Remotes.OnServer("WeaponFired", function(
    player: Player,
    weaponName: string,
    origin: Vector3,
    direction: Vector3
)
    -- Basic validation
    if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
    if typeof(weaponName) ~= "string" then return end

    local weaponCfg = GameConfig.WEAPONS[weaponName]
    if not weaponCfg then return end

    -- Rate limiting
    local now = os.clock()
    if lastFireTime[player] and (now - lastFireTime[player]) < weaponCfg.fireRate then
        return
    end
    lastFireTime[player] = now

    -- Origin distance check (anti-cheat)
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end
    if (hrp.Position - origin).Magnitude > MAX_ORIGIN_DISTANCE then return end

    -- Normalize direction (clients should send unit vectors, but sanitize)
    local dir = direction.Unit

    if weaponCfg.isHitscan then
        WeaponSystem:_fireHitscan(player, weaponCfg, origin, dir)
    else
        local pellets = (weaponCfg :: any).pellets or 1
        for _ = 1, pellets do
            local spread = weaponCfg.spread
            local randDir = (dir + Vector3.new(
                (math.random() - 0.5) * spread,
                (math.random() - 0.5) * spread,
                (math.random() - 0.5) * spread
            )).Unit
            task.spawn(WeaponSystem._fireProjectile, WeaponSystem, player, weaponCfg, origin, randDir)
        end
    end
end)

-- =====================================================
-- HITSCAN
-- =====================================================

function WeaponSystem:_fireHitscan(
    player: Player,
    weaponCfg: any,
    origin: Vector3,
    direction: Vector3
)
    local params            = RaycastParams.new()
    params.FilterType       = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character :: Instance }

    local result = workspace:Raycast(origin, direction * 1500, params)

    if result then
        self:_processHit(player, weaponCfg, result.Instance, result.Position, result.Normal)
    end
end

-- =====================================================
-- PROJECTILE
-- =====================================================

function WeaponSystem:_fireProjectile(
    player: Player,
    weaponCfg: any,
    origin: Vector3,
    direction: Vector3
)
    local proj          = Instance.new("Part")
    proj.Name           = "Paintball"
    proj.Shape          = Enum.PartType.Ball
    proj.Size           = Vector3.new(0.4, 0.4, 0.4)
    proj.Color          = weaponCfg.paintColor
    proj.Material       = Enum.Material.Neon
    proj.CastShadow     = false
    proj.CanCollide     = false
    proj.Anchored       = false
    proj.CFrame         = CFrame.new(origin)
    proj.Parent         = workspace

    -- Neon trail
    local trail             = Instance.new("Trail")
    trail.Attachment0       = Instance.new("Attachment", proj)
    trail.Attachment1       = Instance.new("Attachment", proj)
    trail.Attachment1.Position = Vector3.new(0, 0, 0.2)
    trail.Color             = ColorSequence.new(weaponCfg.paintColor)
    trail.LightEmission     = 0.8
    trail.Transparency      = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Lifetime          = 0.12
    trail.Parent            = proj

    table.insert(activeProjectiles, proj)

    local velocity  = direction * weaponCfg.speed
    local startTime = os.clock()
    local lifetime  = 4   -- seconds before despawn

    local params            = RaycastParams.new()
    params.FilterType       = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character :: Instance }

    local prevPos = origin
    local conn: RBXScriptConnection

    conn = RunService.Heartbeat:Connect(function(dt: number)
        if not proj or not proj.Parent then conn:Disconnect() return end
        if os.clock() - startTime > lifetime then
            proj:Destroy()
            conn:Disconnect()
            return
        end

        local newPos = proj.Position + velocity * dt
        velocity     = velocity + Vector3.new(0, -workspace.Gravity * dt, 0)
        proj.CFrame  = CFrame.lookAt(newPos, newPos + velocity)

        local result = workspace:Raycast(prevPos, (newPos - prevPos), params)
        if result then
            self:_processHit(player, weaponCfg, result.Instance, result.Position, result.Normal)
            proj:Destroy()
            conn:Disconnect()
        end

        prevPos = newPos
    end)
end

-- =====================================================
-- HIT PROCESSING
-- =====================================================

function WeaponSystem:_processHit(
    shooter: Player,
    weaponCfg: any,
    hitInstance: BasePart,
    hitPos: Vector3,
    hitNormal: Vector3
)
    -- Fire visual effect for all clients
    Remotes.FireAll("HitEffect", hitPos, hitNormal, weaponCfg.paintColor)

    -- Check if we hit a character
    local hitChar = hitInstance.Parent
    if not hitChar then return end

    local humanoid = hitChar:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not humanoid or humanoid.Health <= 0 then return end

    local victim = Players:GetPlayerFromCharacter(hitChar)
    if not victim or victim == shooter then return end

    -- Only allow hitting enemies
    if _teamManager and not _teamManager:IsEnemy(shooter, victim) then return end

    -- Record damage for potential assist
    if _scoringManager then
        _scoringManager:RecordDamage(shooter, victim)
    end

    local dmg = weaponCfg.damage
    local prevHealth = humanoid.Health
    humanoid:TakeDamage(dmg)

    -- If this damage eliminates them
    if prevHealth > 0 and humanoid.Health <= 0 then
        if _scoringManager then
            _scoringManager:RegisterTakedown(shooter, victim, weaponCfg.displayName or "Unknown")
        end
        -- Start respawn
        task.spawn(function()
            for i = GameConfig.RESPAWN_DELAY, 1, -1 do
                Remotes.FireClient("PlayerRespawnCountdown", victim, i)
                task.wait(1)
            end
            victim:LoadCharacter()
        end)
    end
end

-- =====================================================
-- PLAYER LIFECYCLE
-- =====================================================

Players.PlayerAdded:Connect(function(player: Player)
    playerWeapon[player] = GameConfig.DEFAULT_WEAPON
end)
Players.PlayerRemoving:Connect(function(player: Player)
    lastFireTime[player] = nil
    playerWeapon[player] = nil
end)

return WeaponSystem

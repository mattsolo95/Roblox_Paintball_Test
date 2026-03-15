--!strict
-- WeaponSystem.luau (Server Module)
-- Creates physical Tool objects for each weapon, gives them to players,
-- validates fire requests, performs hit detection, and applies damage.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local GameConfig    = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes       = require(ReplicatedStorage:WaitForChild("Remotes"))

local WeaponSystem  = {}

local _scoringManager: any  = nil
local _teamManager: any     = nil

local lastFireTime: {[Player]: number}  = {}
local activeProjectiles: {BasePart}     = {}
local _toolFolder: Folder?              = nil

local MAX_ORIGIN_DISTANCE = 20

-- =====================================================
-- TOOL VISUAL BUILDER
-- =====================================================

local function buildToolTemplate(weaponName: string, cfg: any): Tool
    local tool              = Instance.new("Tool")
    tool.Name               = weaponName
    tool.RequiresHandle     = true
    tool.CanBeDropped       = false
    tool.ToolTip            = cfg.displayName
    -- Grip: slides the hold-point back so barrel extends forward
    tool.GripPos            = Vector3.new(0, 0, -0.8)
    tool.GripForward        = Vector3.new(0, 0, 1)
    tool.GripRight          = Vector3.new(-1, 0, 0)
    tool.GripUp             = Vector3.new(0, 1, 0)

    -- HANDLE (the grip — Roblox welds this to the right hand)
    local handle            = Instance.new("Part")
    handle.Name             = "Handle"
    handle.Size             = Vector3.new(0.45, 1.0, 0.35)
    handle.Material         = Enum.Material.SmoothPlastic
    handle.Color            = Color3.fromRGB(25, 25, 25)
    handle.CanCollide       = false
    handle.Parent           = tool

    local function weldTo(part: BasePart, offset: CFrame)
        part.CFrame         = offset
        part.CanCollide     = false
        part.Anchored       = false
        local wc            = Instance.new("WeldConstraint")
        wc.Part0            = handle
        wc.Part1            = part
        wc.Parent           = part
        part.Parent         = tool
    end

    -- GUN BODY (main rectangular block above handle)
    local body              = Instance.new("Part")
    body.Size               = Vector3.new(0.45, 0.45, 2.4)
    body.Material           = Enum.Material.SmoothPlastic
    body.Color              = Color3.fromRGB(40, 40, 40)
    weldTo(body, CFrame.new(0, 0.65, -0.9))

    -- BARREL (thin cylinder extending forward)
    local barrel            = Instance.new("Part")
    barrel.Shape            = Enum.PartType.Cylinder
    barrel.Size             = Vector3.new(2.0, 0.18, 0.18)
    barrel.Material         = Enum.Material.Metal
    barrel.Color            = Color3.fromRGB(65, 65, 65)
    -- Cylinder axis is X, rotate 90° so it points along Z
    weldTo(barrel, CFrame.new(0, 0.65, -2.7) * CFrame.Angles(0, 0, math.rad(90)))

    -- PAINT TANK (neon, shows the paint color)
    local tank              = Instance.new("Part")
    tank.Shape              = Enum.PartType.Cylinder
    tank.Size               = Vector3.new(0.9, 0.32, 0.32)
    tank.Material           = Enum.Material.Neon
    tank.Color              = cfg.paintColor
    weldTo(tank, CFrame.new(0, 0.1, -0.5) * CFrame.Angles(0, 0, math.rad(90)))

    -- STOCK (back of gun)
    local stock             = Instance.new("Part")
    stock.Size              = Vector3.new(0.35, 0.35, 0.9)
    stock.Material          = Enum.Material.SmoothPlastic
    stock.Color             = Color3.fromRGB(55, 35, 20)
    weldTo(stock, CFrame.new(0, 0.55, 0.6))

    -- SIGHT (small nub on top)
    local sight             = Instance.new("Part")
    sight.Size              = Vector3.new(0.12, 0.22, 0.12)
    sight.Material          = Enum.Material.SmoothPlastic
    sight.Color             = Color3.fromRGB(60, 60, 60)
    weldTo(sight, CFrame.new(0, 0.95, -0.6))

    -- SHOOT SOUND (attached to handle — plays client-side when fired)
    local sound             = Instance.new("Sound")
    sound.Name              = "ShootSound"
    sound.SoundId           = ""    -- TODO: add a paintball "pop" sound ID from Roblox library
    sound.Volume            = 0.7
    sound.RollOffMaxDistance = 100
    sound.Parent            = handle

    -- MUZZLE POINT (invisible, marks where projectile spawns)
    local muzzle            = Instance.new("Part")
    muzzle.Name             = "MuzzlePoint"
    muzzle.Size             = Vector3.new(0.1, 0.1, 0.1)
    muzzle.Transparency     = 1
    weldTo(muzzle, CFrame.new(0, 0.65, -3.8))

    return tool
end

-- =====================================================
-- INITIALIZE — build tool templates, wire up players
-- =====================================================

function WeaponSystem:Initialize()
    lastFireTime    = {}
    activeProjectiles = {}

    -- Build / rebuild weapon templates in ReplicatedStorage
    local existing = ReplicatedStorage:FindFirstChild("Weapons")
    if existing then existing:Destroy() end

    _toolFolder         = Instance.new("Folder")
    _toolFolder.Name    = "Weapons"
    _toolFolder.Parent  = ReplicatedStorage

    for name, cfg in pairs(GameConfig.WEAPONS) do
        local tool = buildToolTemplate(name, cfg)
        tool.Parent = _toolFolder
    end

    -- Give default weapon to every currently connected player
    for _, player in ipairs(Players:GetPlayers()) do
        self:_giveWeapon(player, GameConfig.DEFAULT_WEAPON)
    end
end

function WeaponSystem:SetDependencies(scoringMgr: any, teamMgr: any)
    _scoringManager = scoringMgr
    _teamManager    = teamMgr
end

function WeaponSystem:_giveWeapon(player: Player, weaponName: string)
    if not _toolFolder then return end
    local template = _toolFolder:FindFirstChild(weaponName) :: Tool?
    if not template then return end

    -- Remove any existing weapons from backpack and character
    for _, item in ipairs(player.Backpack:GetChildren()) do
        if item:IsA("Tool") then item:Destroy() end
    end
    if player.Character then
        for _, item in ipairs(player.Character:GetChildren()) do
            if item:IsA("Tool") then item:Destroy() end
        end
    end

    template:Clone().Parent = player.Backpack
end

function WeaponSystem:GiveWeapon(player: Player, weaponName: string)
    self:_giveWeapon(player, weaponName)
end

function WeaponSystem:Cleanup()
    for _, proj in ipairs(activeProjectiles) do
        if proj and proj.Parent then proj:Destroy() end
    end
    activeProjectiles = {}
end

-- =====================================================
-- FIRE REQUEST HANDLER
-- =====================================================

Remotes.OnServer("WeaponFired", function(
    player: Player,
    weaponName: string,
    origin: Vector3,
    direction: Vector3
)
    if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
    if typeof(weaponName) ~= "string" then return end

    local weaponCfg = GameConfig.WEAPONS[weaponName]
    if not weaponCfg then return end

    local now = os.clock()
    if lastFireTime[player] and (now - lastFireTime[player]) < weaponCfg.fireRate then return end
    lastFireTime[player] = now

    local char  = player.Character
    local hrp   = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end
    if (hrp.Position - origin).Magnitude > MAX_ORIGIN_DISTANCE then return end

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

function WeaponSystem:_fireHitscan(player, weaponCfg, origin, direction)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character :: Instance }

    local result = workspace:Raycast(origin, direction * 1500, params)
    if result then
        self:_processHit(player, weaponCfg, result.Instance, result.Position, result.Normal)
    end
end

-- =====================================================
-- PROJECTILE
-- =====================================================

function WeaponSystem:_fireProjectile(player, weaponCfg, origin, direction)
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
    table.insert(activeProjectiles, proj)

    -- Trail
    local a0            = Instance.new("Attachment", proj)
    local a1            = Instance.new("Attachment", proj)
    a1.Position         = Vector3.new(0, 0, 0.2)
    local trail         = Instance.new("Trail", proj)
    trail.Attachment0   = a0
    trail.Attachment1   = a1
    trail.Color         = ColorSequence.new(weaponCfg.paintColor)
    trail.LightEmission = 0.8
    trail.Lifetime      = 0.1
    trail.Transparency  = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })

    local velocity  = direction * weaponCfg.speed
    local startTime = os.clock()
    local prevPos   = origin
    local params    = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character :: Instance }

    local conn: RBXScriptConnection
    conn = RunService.Heartbeat:Connect(function(dt)
        if not proj or not proj.Parent then conn:Disconnect(); return end
        if os.clock() - startTime > 4 then proj:Destroy(); conn:Disconnect(); return end

        local newPos    = proj.Position + velocity * dt
        velocity        = velocity + Vector3.new(0, -workspace.Gravity * dt, 0)
        proj.CFrame     = CFrame.lookAt(newPos, newPos + velocity)

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

function WeaponSystem:_processHit(shooter, weaponCfg, hitInstance, hitPos, hitNormal)
    Remotes.FireAll("HitEffect", hitPos, hitNormal, weaponCfg.paintColor)

    local hitChar   = hitInstance.Parent
    if not hitChar then return end
    local humanoid  = hitChar:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not humanoid or humanoid.Health <= 0 then return end

    local victim    = Players:GetPlayerFromCharacter(hitChar)
    if not victim or victim == shooter then return end
    if _teamManager and not _teamManager:IsEnemy(shooter, victim) then return end

    if _scoringManager then _scoringManager:RecordDamage(shooter, victim) end

    local prevHealth = humanoid.Health
    humanoid:TakeDamage(weaponCfg.damage)

    if prevHealth > 0 and humanoid.Health <= 0 then
        if _scoringManager then
            _scoringManager:RegisterTakedown(shooter, victim, weaponCfg.displayName or "Gun")
        end
        task.spawn(function()
            for i = GameConfig.RESPAWN_DELAY, 1, -1 do
                Remotes.FireClient("PlayerRespawnCountdown", victim, i)
                task.wait(1)
            end
            victim:LoadCharacter()
            -- Re-give weapon after respawn
            victim.CharacterAdded:Wait()
            task.wait(0.5)
            WeaponSystem:_giveWeapon(victim, GameConfig.DEFAULT_WEAPON)
        end)
    end
end

-- =====================================================
-- PLAYER LIFECYCLE
-- =====================================================

Players.PlayerAdded:Connect(function(player)
    lastFireTime[player] = 0
    -- Give weapon when character spawns
    player.CharacterAdded:Connect(function()
        task.wait(0.5)  -- brief wait for character to fully initialize
        WeaponSystem:_giveWeapon(player, GameConfig.DEFAULT_WEAPON)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    lastFireTime[player] = nil
end)

return WeaponSystem

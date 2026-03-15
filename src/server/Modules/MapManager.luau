--!strict
-- MapManager.luau (Server Module)
-- Procedurally generates both maps (snow / grass) scaled to player count.
-- Builds terrain, castles, cover objects, NMZ boundaries, trees, flags, power-up.
--
-- Coordinate system (Z-axis is the "battle axis"):
--   Team A castle: negative Z
--   Team B castle: positive Z
--   No Man's Zone: central 20% of total map length

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig        = require(ReplicatedStorage:WaitForChild("GameConfig"))

local MapManager = {}

local MAP_FOLDER_NAME   = "GeneratedMap"
local NMZ_FOLDER_NAME   = "NMZBounds"
local SPAWN_FOLDER_NAME = "SpawnPoints"
local FLAG_FOLDER_NAME  = "Flags"

-- =====================================================
-- SIZE RESOLUTION
-- =====================================================

local function resolveMapSize(playerCount: number): number
    for _, entry in ipairs(GameConfig.MAP_SIZES) do
        if playerCount < entry.threshold then
            return entry.size
        end
    end
    return 1000
end

-- =====================================================
-- UTILITY HELPERS
-- =====================================================

local function makeFolder(name: string, parent: Instance): Folder
    local f     = Instance.new("Folder")
    f.Name      = name
    f.Parent    = parent
    return f
end

local function makePart(
    name: string,
    size: Vector3,
    cf: CFrame,
    color: Color3,
    material: Enum.Material,
    anchored: boolean,
    parent: Instance
): Part
    local p         = Instance.new("Part")
    p.Name          = name
    p.Size          = size
    p.CFrame        = cf
    p.Color         = color
    p.Material      = material
    p.Anchored      = anchored
    p.TopSurface    = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent        = parent
    return p
end

local function makeSpawnPart(pos: Vector3, parent: Instance, index: number)
    local p         = Instance.new("SpawnLocation")
    p.Name          = "Spawn" .. index
    p.Size          = Vector3.new(4, 1, 4)
    p.CFrame        = CFrame.new(pos)
    p.Anchored      = true
    p.Neutral       = false
    p.Duration      = 0
    p.Parent        = parent
end

-- =====================================================
-- TERRAIN GENERATION
-- =====================================================

local function fillTerrain(mapSize: number, isSnow: boolean)
    local terrain   = workspace.Terrain
    terrain:Clear()

    local halfSize  = mapSize / 2
    local groundMat = if isSnow then Enum.Material.Snow else Enum.Material.Grass

    -- Flat base ground
    terrain:FillBlock(
        CFrame.new(0, -10, 0),
        Vector3.new(mapSize + 200, 20, mapSize + 200),
        groundMat
    )

    -- Rolling hills / snow mounds
    local rng = Random.new()
    local hillCount = if mapSize >= 700 then 30 else 15
    for _ = 1, hillCount do
        local x = rng:NextNumber(-halfSize * 0.8, halfSize * 0.8)
        local z = rng:NextNumber(-halfSize * 0.8, halfSize * 0.8)
        local r = rng:NextNumber(15, 40)
        terrain:FillBall(Vector3.new(x, -5 + r * 0.4, z), r, groundMat)
    end

    -- Ice patches (snow map only)
    if isSnow then
        for _ = 1, 12 do
            local x = rng:NextNumber(-halfSize * 0.7, halfSize * 0.7)
            local z = rng:NextNumber(-halfSize * 0.7, halfSize * 0.7)
            terrain:FillBlock(
                CFrame.new(x, 0.1, z),
                Vector3.new(
                    rng:NextNumber(20, 60),
                    0.5,
                    rng:NextNumber(20, 60)
                ),
                Enum.Material.Ice
            )
        end
    end
end

-- =====================================================
-- CASTLE BUILDER
-- =====================================================

local STONE = Enum.Material.SmoothPlastic
local STONE_COLOR = Color3.fromRGB(120, 110, 100)

local function buildCastle(
    folder: Instance,
    centerX: number,
    centerZ: number,
    facingPositiveZ: boolean,   -- true = Team B (faces toward negative Z)
    teamColor: Color3,
    mapSize: number
): ()
    local scale     = mapSize / 400    -- relative to small map
    local W         = 80  * scale      -- castle width
    local D         = 40  * scale      -- castle depth
    local H         = 24  * scale      -- wall height
    local thick     = 4   * scale      -- wall thickness
    local towerR    = 10  * scale      -- tower radius
    local towerH    = H + 8 * scale    -- towers slightly taller

    -- Back wall
    makePart("BackWall", Vector3.new(W, H, thick),
        CFrame.new(centerX, H/2, centerZ + (if facingPositiveZ then -D/2 else D/2)),
        STONE_COLOR, STONE, true, folder)

    -- Front wall (with gate gap)
    local gateW = 14 * scale
    local sideW = (W - gateW) / 2
    makePart("FrontWallL", Vector3.new(sideW, H, thick),
        CFrame.new(centerX - gateW/2 - sideW/2, H/2, centerZ + (if facingPositiveZ then D/2 else -D/2)),
        STONE_COLOR, STONE, true, folder)
    makePart("FrontWallR", Vector3.new(sideW, H, thick),
        CFrame.new(centerX + gateW/2 + sideW/2, H/2, centerZ + (if facingPositiveZ then D/2 else -D/2)),
        STONE_COLOR, STONE, true, folder)
    -- Gate arch top
    makePart("GateTop", Vector3.new(gateW, 6 * scale, thick),
        CFrame.new(centerX, H - 3 * scale, centerZ + (if facingPositiveZ then D/2 else -D/2)),
        STONE_COLOR, STONE, true, folder)

    -- Side walls
    makePart("LeftWall", Vector3.new(thick, H, D),
        CFrame.new(centerX - W/2, H/2, centerZ),
        STONE_COLOR, STONE, true, folder)
    makePart("RightWall", Vector3.new(thick, H, D),
        CFrame.new(centerX + W/2, H/2, centerZ),
        STONE_COLOR, STONE, true, folder)

    -- Floor / courtyard
    makePart("Floor", Vector3.new(W, 2, D),
        CFrame.new(centerX, 1, centerZ),
        Color3.fromRGB(80, 70, 60), Enum.Material.Cobblestone, true, folder)

    -- Corner towers
    for _, sx in ipairs({-1, 1}) do
        for _, sz in ipairs({-1, 1}) do
            local tx = centerX + sx * (W/2 - towerR/2)
            local tz = centerZ + sz * (D/2 - towerR/2)
            makePart("Tower_" .. sx .. "_" .. sz,
                Vector3.new(towerR, towerH, towerR),
                CFrame.new(tx, towerH/2, tz),
                STONE_COLOR, STONE, true, folder)
            -- Battlement
            makePart("Battlement_" .. sx .. "_" .. sz,
                Vector3.new(towerR + 2, 3 * scale, towerR + 2),
                CFrame.new(tx, towerH + 1.5 * scale, tz),
                STONE_COLOR, Enum.Material.Cobblestone, true, folder)
        end
    end

    -- Flag tower (center back, taller)
    local flagTowerH = towerH + 10 * scale
    local flagTower = makePart("FlagTower",
        Vector3.new(towerR, flagTowerH, towerR),
        CFrame.new(centerX, flagTowerH/2, centerZ + (if facingPositiveZ then -D/2 + towerR/2 else D/2 - towerR/2)),
        STONE_COLOR, STONE, true, folder)
    _ = flagTower

    -- Team banner color strip
    makePart("Banner", Vector3.new(W, 3 * scale, thick * 0.5),
        CFrame.new(centerX, H + 1.5 * scale, centerZ + (if facingPositiveZ then -D/2 else D/2) - thick * 0.25),
        teamColor, Enum.Material.SmoothPlastic, true, folder)
end

-- =====================================================
-- COVER OBJECTS
-- =====================================================

local function buildCover(folder: Instance, halfMap: number, isSnow: boolean, scale: number)
    -- Cover zone: 20% to 50% from each end (in Z)
    -- Team A side: negative Z;  Team B side: positive Z
    local rng           = Random.new(12345)  -- fixed seed → deterministic layout
    local coverStart    = halfMap * GameConfig.CASTLE_DEPTH_FRAC
    local coverEnd      = halfMap * GameConfig.COVER_DEPTH_FRAC

    local coverTypes = { "TrenchWall", "Bunker", "SnowPile", "SlitWall", "Barricade" }
    local coverCount = if scale >= 2 then 24 else if scale >= 1.5 then 14 else 8

    for side = -1, 1, 2 do   -- -1 = Team A, 1 = Team B
        for i = 1, coverCount do
            local x     = rng:NextNumber(-halfMap * 0.7, halfMap * 0.7)
            local zFrac = rng:NextNumber(coverStart, coverEnd)
            local z     = side * zFrac
            local cType = coverTypes[rng:NextInteger(1, #coverTypes)]
            local color = if isSnow
                then Color3.fromRGB(200, 210, 220)
                else Color3.fromRGB(100, 80, 50)
            local mat   = if isSnow
                then Enum.Material.Snow
                else Enum.Material.SmoothPlastic

            if cType == "TrenchWall" then
                makePart("Cover_Trench_" .. i,
                    Vector3.new(rng:NextNumber(8, 18) * scale, 4 * scale, 3 * scale),
                    CFrame.new(x, 2 * scale, z),
                    color, mat, true, folder)

            elseif cType == "Bunker" then
                -- Box with gap
                local bW = rng:NextNumber(10, 20) * scale
                local bH = 5 * scale
                makePart("Cover_BunkerBack_" .. i,
                    Vector3.new(bW, bH, 3 * scale),
                    CFrame.new(x, bH/2, z),
                    color, mat, true, folder)
                makePart("Cover_BunkerL_" .. i,
                    Vector3.new(3 * scale, bH, 8 * scale),
                    CFrame.new(x - bW/2, bH/2, z + 4 * scale),
                    color, mat, true, folder)
                makePart("Cover_BunkerR_" .. i,
                    Vector3.new(3 * scale, bH, 8 * scale),
                    CFrame.new(x + bW/2, bH/2, z + 4 * scale),
                    color, mat, true, folder)

            elseif cType == "SlitWall" then
                -- Wall with shooting slit
                local wH = 6 * scale
                makePart("Cover_SlitTop_" .. i,
                    Vector3.new(12 * scale, wH * 0.5, 2 * scale),
                    CFrame.new(x, wH * 0.75, z),
                    color, mat, true, folder)
                makePart("Cover_SlitBot_" .. i,
                    Vector3.new(12 * scale, wH * 0.3, 2 * scale),
                    CFrame.new(x, wH * 0.15, z),
                    color, mat, true, folder)
                makePart("Cover_SlitSideL_" .. i,
                    Vector3.new(2 * scale, wH, 2 * scale),
                    CFrame.new(x - 7 * scale, wH/2, z),
                    color, mat, true, folder)
                makePart("Cover_SlitSideR_" .. i,
                    Vector3.new(2 * scale, wH, 2 * scale),
                    CFrame.new(x + 7 * scale, wH/2, z),
                    color, mat, true, folder)

            else
                -- Generic mound / barricade
                makePart("Cover_Mound_" .. i,
                    Vector3.new(
                        rng:NextNumber(6, 14) * scale,
                        rng:NextNumber(3, 7)  * scale,
                        rng:NextNumber(6, 14) * scale
                    ),
                    CFrame.new(x, 2 * scale, z),
                    color, mat, true, folder)
            end
        end
    end
end

-- =====================================================
-- TREE BUILDER
-- =====================================================

local function buildTrees(folder: Instance, halfMap: number, isSnow: boolean, scale: number)
    local rng       = Random.new(99999)
    local treeCount = if scale >= 2 then 60 else if scale >= 1.5 then 35 else 20

    for i = 1, treeCount do
        local x = rng:NextNumber(-halfMap * 0.85, halfMap * 0.85)
        local z = rng:NextNumber(-halfMap * 0.85, halfMap * 0.85)
        -- Avoid center NMZ (don't plant trees in the middle 15% of map)
        if math.abs(z) < halfMap * 0.15 then continue end

        local trunkH    = rng:NextNumber(8, 16) * scale
        local trunkW    = 1.5 * scale

        if isSnow then
            -- Pine tree: stacked cones
            makePart("Tree_Trunk_" .. i,
                Vector3.new(trunkW, trunkH, trunkW),
                CFrame.new(x, trunkH/2, z),
                Color3.fromRGB(90, 60, 30), Enum.Material.Wood, true, folder)
            for layer = 0, 2 do
                local layerScale    = 1 - layer * 0.25
                local layerH        = 5 * scale * layerScale
                local layerY        = trunkH + layer * layerH * 0.6
                makePart("Tree_Cone_" .. i .. "_" .. layer,
                    Vector3.new(10 * scale * layerScale, layerH, 10 * scale * layerScale),
                    CFrame.new(x, layerY + layerH/2, z),
                    Color3.fromRGB(30, 80, 40), Enum.Material.Grass, true, folder)
            end
        else
            -- Oak tree: cylinder trunk + sphere canopy
            makePart("Tree_Trunk_" .. i,
                Vector3.new(trunkW, trunkH, trunkW),
                CFrame.new(x, trunkH/2, z),
                Color3.fromRGB(90, 60, 30), Enum.Material.Wood, true, folder)
            local canopySize = rng:NextNumber(12, 20) * scale
            makePart("Tree_Canopy_" .. i,
                Vector3.new(canopySize, canopySize * 0.75, canopySize),
                CFrame.new(x, trunkH + canopySize * 0.3, z),
                Color3.fromRGB(30, 110, 30), Enum.Material.Grass, true, folder)
        end
    end
end

-- =====================================================
-- NMZ BOUNDARY MARKERS (invisible trigger parts)
-- =====================================================

local function buildNMZBounds(folder: Instance, halfMap: number, scale: number)
    -- The NMZ covers the central 20% of the total map length.
    -- That means from -nmzHalf to +nmzHalf on the Z axis.
    local nmzHalf   = halfMap * (1 - GameConfig.COVER_DEPTH_FRAC * 2) * 0.5 + halfMap * 0.1

    -- Two invisible trigger walls (one on each side of the NMZ)
    for side = -1, 1, 2 do
        local wall  = Instance.new("Part")
        wall.Name   = "NMZBound_" .. (if side == -1 then "A" else "B")
        wall.Size   = Vector3.new(halfMap * 2 + 40, 200, 2)
        wall.CFrame = CFrame.new(0, 100, side * nmzHalf)
        wall.Anchored       = true
        wall.CanCollide     = false
        wall.Transparency   = 1
        wall.Parent         = folder

        -- Tag so client and server can detect NMZ entry
        local tag           = Instance.new("StringValue")
        tag.Name            = "NMZTrigger"
        tag.Value           = if side == -1 then "EnterFromA" else "EnterFromB"
        tag.Parent          = wall
    end

    -- Also place a visible NMZ floor indicator (red-tinted, transparent)
    local indicator         = Instance.new("Part")
    indicator.Name          = "NMZFloor"
    indicator.Size          = Vector3.new(halfMap * 2, 0.5, nmzHalf * 2)
    indicator.CFrame        = CFrame.new(0, 0.3, 0)
    indicator.Anchored      = true
    indicator.CanCollide    = false
    indicator.Transparency  = 0.85
    indicator.Color         = Color3.fromRGB(200, 0, 0)
    indicator.Material      = Enum.Material.Neon
    indicator.Parent        = folder

    return nmzHalf
end

-- =====================================================
-- SPAWN POINTS
-- =====================================================

local function buildSpawnPoints(folder: Instance, halfMap: number, spawnCount: number)
    local spawnA = Instance.new("Folder")
    spawnA.Name  = "TeamA"
    spawnA.Parent = folder

    local spawnB = Instance.new("Folder")
    spawnB.Name  = "TeamB"
    spawnB.Parent = folder

    local spread = math.min(60, halfMap * 0.3)
    for i = 1, spawnCount do
        local xOffset = (i - (spawnCount / 2)) * (spread / spawnCount)
        makeSpawnPart(Vector3.new(xOffset, 5, -halfMap * 0.85), spawnA, i)
        makeSpawnPart(Vector3.new(xOffset, 5,  halfMap * 0.85), spawnB, i)
    end
end

-- =====================================================
-- FLAG PLACEMENT
-- =====================================================

local function placeFlags(folder: Instance, halfMap: number, scale: number)
    local flagTowerZ = halfMap * 0.82   -- near the back of each castle
    local flagY      = 40 * scale       -- top of flag tower

    local function makeFlag(name: string, z: number, color: Color3)
        local pole  = makePart(name .. "Pole",
            Vector3.new(0.5, 8 * scale, 0.5),
            CFrame.new(0, flagY + 4 * scale, z),
            Color3.fromRGB(180, 140, 80), Enum.Material.Metal, true, folder)
        _ = pole

        local flag  = makePart(name,
            Vector3.new(6 * scale, 4 * scale, 0.5),
            CFrame.new(3 * scale, flagY + 7 * scale, z),
            color, Enum.Material.SmoothPlastic, true, folder)
        return flag
    end

    -- Placeholder colors (will match team colors after vote)
    makeFlag("FlagA", -flagTowerZ, Color3.fromRGB(200, 50, 50))
    makeFlag("FlagB",  flagTowerZ, Color3.fromRGB(50, 50, 200))
end

-- =====================================================
-- CENTER POWER-UP BLOCK
-- =====================================================

local function placePowerUp()
    local part              = Instance.new("Part")
    part.Name               = "CenterPowerUp"
    part.Anchored           = true
    part.Size               = Vector3.new(5, 5, 5)
    part.CFrame             = CFrame.new(0, 5, 0)
    part.Material           = Enum.Material.Neon
    part.Color              = Color3.fromRGB(255, 220, 50)
    part.CastShadow         = false
    part.Parent             = workspace

    local light             = Instance.new("PointLight", part)
    light.Brightness        = 5
    light.Range             = 22
    light.Color             = Color3.fromRGB(255, 220, 50)
end

-- =====================================================
-- PUBLIC API
-- =====================================================

function MapManager:GenerateMap(mapName: string, playerCount: number)
    local mapSize   = resolveMapSize(playerCount)
    local halfMap   = mapSize / 2
    local scale     = mapSize / 400
    local isSnow    = mapName == "snow"

    print("[MapManager] Generating", mapName, "map |", mapSize, "studs |", playerCount, "players")

    -- Root folder for all generated objects
    local root          = makeFolder(MAP_FOLDER_NAME, workspace)
    local coverFolder   = makeFolder("Cover",   root)
    local treeFolder    = makeFolder("Trees",   root)
    local castleFolder  = makeFolder("Castles", root)
    local nmzFolder     = makeFolder(NMZ_FOLDER_NAME, workspace)
    local spawnFolder   = makeFolder(SPAWN_FOLDER_NAME, workspace)
    local flagFolder    = makeFolder(FLAG_FOLDER_NAME, workspace)

    -- Terrain
    fillTerrain(mapSize, isSnow)

    -- Castles (placeholder team colors; FlagManager/TeamManager update them)
    buildCastle(castleFolder, 0, -halfMap * 0.88, false,
        Color3.fromRGB(200, 50, 50), mapSize)   -- Team A
    buildCastle(castleFolder, 0,  halfMap * 0.88, true,
        Color3.fromRGB(50, 50, 200), mapSize)   -- Team B

    -- Cover
    buildCover(coverFolder, halfMap, isSnow, scale)

    -- Trees
    buildTrees(treeFolder, halfMap, isSnow, scale)

    -- NMZ boundaries
    buildNMZBounds(nmzFolder, halfMap, scale)

    -- Spawn points
    buildSpawnPoints(spawnFolder, halfMap, math.max(playerCount, 4))

    -- Flags
    placeFlags(flagFolder, halfMap, scale)

    -- Center power-up
    placePowerUp()

    -- Lighting preset
    self:_applyLighting(isSnow)

    print("[MapManager] Map generated.")
end

function MapManager:ClearMap()
    local function destroyIfExists(name: string)
        local obj = workspace:FindFirstChild(name)
        if obj then obj:Destroy() end
    end
    destroyIfExists(MAP_FOLDER_NAME)
    destroyIfExists(NMZ_FOLDER_NAME)
    destroyIfExists(SPAWN_FOLDER_NAME)
    destroyIfExists(FLAG_FOLDER_NAME)
    destroyIfExists("CenterPowerUp")
    workspace.Terrain:Clear()
end

function MapManager:_applyLighting(isSnow: boolean)
    local Lighting = game:GetService("Lighting")
    if isSnow then
        Lighting.Ambient            = Color3.fromRGB(160, 180, 210)
        Lighting.OutdoorAmbient     = Color3.fromRGB(180, 200, 230)
        Lighting.TimeOfDay          = "14:00:00"
        Lighting.Brightness         = 2
        Lighting.FogColor           = Color3.fromRGB(200, 210, 230)
        Lighting.FogEnd             = 800
        Lighting.FogStart           = 300
    else
        Lighting.Ambient            = Color3.fromRGB(120, 130, 100)
        Lighting.OutdoorAmbient     = Color3.fromRGB(140, 160, 110)
        Lighting.TimeOfDay          = "11:30:00"
        Lighting.Brightness         = 2.5
        Lighting.FogEnd             = 1200
        Lighting.FogStart           = 600
    end
end

return MapManager

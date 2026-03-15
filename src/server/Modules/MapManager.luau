--!strict
-- MapManager.luau (Server Module)
-- Generates snow or grass maps scaled to player count.
-- Features: proper enclosed castles with stairs/flag towers,
-- sparse cover, visible NMZ, and manageable terrain.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig        = require(ReplicatedStorage:WaitForChild("GameConfig"))

local MapManager = {}

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
-- PART FACTORY
-- =====================================================

local function part(
    name: string, size: Vector3, cf: CFrame,
    color: Color3, mat: Enum.Material,
    parent: Instance, transparency: number?
): Part
    local p             = Instance.new("Part")
    p.Name              = name
    p.Size              = size
    p.CFrame            = cf
    p.Color             = color
    p.Material          = mat
    p.Anchored          = true
    p.CanCollide        = true
    p.TopSurface        = Enum.SurfaceType.Smooth
    p.BottomSurface     = Enum.SurfaceType.Smooth
    p.Transparency      = transparency or 0
    p.CastShadow        = true
    p.Parent            = parent
    return p
end

local function wedge(
    name: string, size: Vector3, cf: CFrame,
    color: Color3, mat: Enum.Material, parent: Instance
): WedgePart
    local w             = Instance.new("WedgePart")
    w.Name              = name
    w.Size              = size
    w.CFrame            = cf
    w.Color             = color
    w.Material          = mat
    w.Anchored          = true
    w.TopSurface        = Enum.SurfaceType.Smooth
    w.BottomSurface     = Enum.SurfaceType.Smooth
    w.Parent            = parent
    return w
end

-- =====================================================
-- TERRAIN
-- =====================================================

local function buildTerrain(mapSize: number, isSnow: boolean)
    local terrain   = workspace.Terrain
    terrain:Clear()
    local half      = mapSize / 2
    local ground    = if isSnow then Enum.Material.Snow else Enum.Material.Grass

    -- Flat base
    terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(mapSize + 200, 16, mapSize + 200), ground)

    -- A FEW gentle hills (much fewer than before)
    local rng       = Random.new(42)
    local hillCount = if mapSize >= 700 then 8 else 4
    for _ = 1, hillCount do
        local x = rng:NextNumber(-half * 0.6, half * 0.6)
        local z = rng:NextNumber(-half * 0.35, half * 0.35)  -- avoid castle areas
        local r = rng:NextNumber(20, 40)
        terrain:FillBall(Vector3.new(x, -5 + r * 0.3, z), r, ground)
    end

    -- Ice patches (snow map only) — just a handful
    if isSnow then
        for _ = 1, 5 do
            local x = rng:NextNumber(-half * 0.5, half * 0.5)
            local z = rng:NextNumber(-half * 0.35, half * 0.35)
            terrain:FillBlock(
                CFrame.new(x, 0.1, z),
                Vector3.new(rng:NextNumber(25, 50), 0.5, rng:NextNumber(25, 50)),
                Enum.Material.Ice
            )
        end
    end
end

-- =====================================================
-- CASTLE BUILDER — enclosed, multi-level, proper stairs
-- =====================================================

local STONE         = Color3.fromRGB(115, 105, 95)
local STONE_DARK    = Color3.fromRGB(85, 78, 70)
local STONE_MAT     = Enum.Material.SmoothPlastic
local COBBLE_MAT    = Enum.Material.Cobblestone
local WOOD_COLOR    = Color3.fromRGB(90, 60, 30)

local function buildCastle(
    folder: Instance,
    cx: number,         -- center X
    cz: number,         -- center Z (negative = Team A, positive = Team B)
    teamColor: Color3,
    mapSize: number
)
    local s         = mapSize / 400             -- scale factor
    local gateDir   = if cz < 0 then 1 else -1  -- gate faces toward center (Z=0)

    -- Dimensions
    local W     = 110 * s   -- castle width (X)
    local D     = 90  * s   -- castle depth (Z)
    local FY    = 1         -- floor Y (slightly above terrain)
    local WH    = 18  * s   -- main wall height
    local WT    = 4   * s   -- wall thickness
    local TW    = 14  * s   -- tower width
    local TH    = WH + 10 * s  -- corner tower height
    local FTW   = 10  * s   -- flag tower width
    local FTH   = TH + 20 * s -- flag tower height (tallest)

    -- Helper: Z of front/back walls
    local frontZ = cz + gateDir * (D / 2)   -- toward enemy
    local backZ  = cz - gateDir * (D / 2)   -- behind

    -- ── FLOOR ─────────────────────────────────────────
    part("Floor", Vector3.new(W, 2, D),
        CFrame.new(cx, FY, cz),
        Color3.fromRGB(100, 92, 80), COBBLE_MAT, folder)

    -- ── WALLS ─────────────────────────────────────────
    -- Back wall (solid)
    part("BackWall", Vector3.new(W, WH, WT),
        CFrame.new(cx, FY + WH/2, backZ),
        STONE, STONE_MAT, folder)

    -- Front wall: two halves with gate gap (12 * s wide)
    local gateW = 14 * s
    local sideW = (W - gateW) / 2
    part("FrontL", Vector3.new(sideW, WH, WT),
        CFrame.new(cx - gateW/2 - sideW/2, FY + WH/2, frontZ),
        STONE, STONE_MAT, folder)
    part("FrontR", Vector3.new(sideW, WH, WT),
        CFrame.new(cx + gateW/2 + sideW/2, FY + WH/2, frontZ),
        STONE, STONE_MAT, folder)
    -- Gate lintel
    part("GateLint", Vector3.new(gateW, 5 * s, WT),
        CFrame.new(cx, FY + WH - 2.5 * s, frontZ),
        STONE_DARK, STONE_MAT, folder)

    -- Side walls
    part("LeftWall",  Vector3.new(WT, WH, D),
        CFrame.new(cx - W/2, FY + WH/2, cz),
        STONE, STONE_MAT, folder)
    part("RightWall", Vector3.new(WT, WH, D),
        CFrame.new(cx + W/2, FY + WH/2, cz),
        STONE, STONE_MAT, folder)

    -- ── BATTLEMENTS (alternating merlons on top of walls) ──
    local merW  = 5 * s
    local merH  = 5 * s
    local merT  = WT + 0.5
    local merY  = FY + WH + merH / 2
    -- Back wall merlons
    local merlonCount = math.floor(W / (merW * 2)) - 1
    for i = 0, merlonCount do
        local mx = cx - W/2 + merW + i * merW * 2
        part("Merlon_B" .. i, Vector3.new(merW, merH, merT),
            CFrame.new(mx, merY, backZ), STONE_DARK, STONE_MAT, folder)
    end
    -- Front wall merlons (left side)
    local sideMerlons = math.floor(sideW / (merW * 2))
    for i = 0, sideMerlons do
        local mx = cx - W/2 + merW + i * merW * 2
        if mx < cx - gateW/2 then
            part("Merlon_FL" .. i, Vector3.new(merW, merH, merT),
                CFrame.new(mx, merY, frontZ), STONE_DARK, STONE_MAT, folder)
        end
        local mx2 = cx + gateW/2 + merW + i * merW * 2
        if mx2 < cx + W/2 then
            part("Merlon_FR" .. i, Vector3.new(merW, merH, merT),
                CFrame.new(mx2, merY, frontZ), STONE_DARK, STONE_MAT, folder)
        end
    end
    -- Side wall merlons
    local sideDMerlons = math.floor(D / (merW * 2)) - 1
    for i = 0, sideDMerlons do
        local mz = cz - D/2 + merW + i * merW * 2
        part("Merlon_L" .. i, Vector3.new(merT, merH, merW),
            CFrame.new(cx - W/2, merY, mz), STONE_DARK, STONE_MAT, folder)
        part("Merlon_R" .. i, Vector3.new(merT, merH, merW),
            CFrame.new(cx + W/2, merY, mz), STONE_DARK, STONE_MAT, folder)
    end

    -- ── WALL WALKWAY (on top of walls, you can walk up there) ──
    part("WalkwayBack", Vector3.new(W, 2, WT + 4),
        CFrame.new(cx, FY + WH + 1, backZ), STONE_DARK, COBBLE_MAT, folder)
    part("WalkwayFrontL", Vector3.new(sideW, 2, WT + 4),
        CFrame.new(cx - gateW/2 - sideW/2, FY + WH + 1, frontZ), STONE_DARK, COBBLE_MAT, folder)
    part("WalkwayFrontR", Vector3.new(sideW, 2, WT + 4),
        CFrame.new(cx + gateW/2 + sideW/2, FY + WH + 1, frontZ), STONE_DARK, COBBLE_MAT, folder)
    part("WalkwayLeft", Vector3.new(WT + 4, 2, D),
        CFrame.new(cx - W/2, FY + WH + 1, cz), STONE_DARK, COBBLE_MAT, folder)
    part("WalkwayRight", Vector3.new(WT + 4, 2, D),
        CFrame.new(cx + W/2, FY + WH + 1, cz), STONE_DARK, COBBLE_MAT, folder)

    -- ── CORNER TOWERS ─────────────────────────────────
    for _, sx in ipairs({-1, 1}) do
        for _, sz in ipairs({-1, 1}) do
            local tx = cx + sx * (W/2)
            local tz = cz + sz * (D/2)
            part("Tower_" .. sx .. sz, Vector3.new(TW, TH, TW),
                CFrame.new(tx, FY + TH/2, tz), STONE, STONE_MAT, folder)
            -- Tower top platform
            part("TowerTop_" .. sx .. sz, Vector3.new(TW + 2, 2, TW + 2),
                CFrame.new(tx, FY + TH + 1, tz), STONE_DARK, COBBLE_MAT, folder)
        end
    end

    -- ── FLAG TOWER (tallest, at center-back) ───────────
    local ftZ = backZ + gateDir * (-FTW / 2 - 2)  -- just inside the back wall
    part("FlagTower", Vector3.new(FTW, FTH, FTW),
        CFrame.new(cx, FY + FTH/2, ftZ), STONE, STONE_MAT, folder)
    -- Flag tower top platform
    part("FlagTowerTop", Vector3.new(FTW + 4, 3, FTW + 4),
        CFrame.new(cx, FY + FTH + 1, ftZ), STONE_DARK, COBBLE_MAT, folder)
    -- Battlements on flag tower
    for i = 0, 3 do
        local angle = i * math.pi / 2
        local bx = cx + math.cos(angle) * (FTW/2)
        local bz = ftZ + math.sin(angle) * (FTW/2)
        part("FT_Merlon_" .. i, Vector3.new(4*s, 5*s, 4*s),
            CFrame.new(bx, FY + FTH + merH/2 + 2, bz), STONE_DARK, STONE_MAT, folder)
    end

    -- ── STAIRS TO FLAG TOWER (ramp up the side of tower) ──
    -- Each step: a small WedgePart or stair part
    local stairSteps = 8
    local stairTotalH = FTH - 2
    local stairTotalZ = FTW + 10 * s
    local stepH = stairTotalH / stairSteps
    local stepD = stairTotalZ / stairSteps

    for i = 0, stairSteps - 1 do
        local stepY = FY + 2 + i * stepH + stepH / 2
        local stepZ = ftZ - gateDir * (FTW/2 + i * stepD + stepD/2)
        local stepWidth = 8 * s

        part("Stair_" .. i, Vector3.new(stepWidth, stepH, stepD),
            CFrame.new(cx, stepY, stepZ), STONE_DARK, COBBLE_MAT, folder)
    end
    -- Stair landing connecting stairs to tower top
    part("StairLanding", Vector3.new(8 * s, 2, 8 * s),
        CFrame.new(cx, FY + FTH + 1, ftZ - gateDir * (FTW/2 + 4)),
        STONE_DARK, COBBLE_MAT, folder)

    -- ── STAIRS TO WALL WALKWAY (from courtyard floor up to wall top) ──
    -- Left side
    local wallRampH = WH
    local wallRampD = WH * 1.5
    wedge("WallRamp_L", Vector3.new(6 * s, wallRampH, wallRampD),
        CFrame.new(cx - W/2 + 3*s + wallRampD/2, FY + wallRampH/2, cz - D/4)
            * CFrame.Angles(0, if gateDir == 1 then 0 else math.pi, 0),
        STONE_DARK, COBBLE_MAT, folder)
    -- Right side
    wedge("WallRamp_R", Vector3.new(6 * s, wallRampH, wallRampD),
        CFrame.new(cx + W/2 - 3*s - wallRampD/2, FY + wallRampH/2, cz - D/4)
            * CFrame.Angles(0, if gateDir == 1 then math.pi else 0, 0),
        STONE_DARK, COBBLE_MAT, folder)

    -- ── INTERIOR COVER OBJECTS ─────────────────────────
    -- A few barrels and crates for defenders to hide behind
    local coverColor = Color3.fromRGB(100, 80, 50)
    part("Barrel1", Vector3.new(3, 4, 3),
        CFrame.new(cx - 15*s, FY + 3, cz + gateDir * 10*s),
        coverColor, Enum.Material.Wood, folder)
    part("Barrel2", Vector3.new(3, 4, 3),
        CFrame.new(cx + 15*s, FY + 3, cz + gateDir * 10*s),
        coverColor, Enum.Material.Wood, folder)
    part("Crate1", Vector3.new(5, 5, 5),
        CFrame.new(cx - 25*s, FY + 3.5, cz - gateDir * 5*s),
        WOOD_COLOR, Enum.Material.Wood, folder)
    part("Crate2", Vector3.new(5, 5, 5),
        CFrame.new(cx + 25*s, FY + 3.5, cz - gateDir * 5*s),
        WOOD_COLOR, Enum.Material.Wood, folder)

    -- ── TEAM COLOR BANNER ─────────────────────────────
    part("Banner", Vector3.new(W * 0.6, 4 * s, WT * 0.3),
        CFrame.new(cx, FY + WH - 2*s, backZ + gateDir * 0.5),
        teamColor, Enum.Material.SmoothPlastic, folder)
end

-- =====================================================
-- COVER (sparse — only 4–6 objects per side)
-- =====================================================

local function buildCover(folder: Instance, halfMap: number, isSnow: boolean, s: number)
    local rng       = Random.new(7777)
    local coverStart = halfMap * 0.22   -- start of cover zone
    local coverEnd   = halfMap * 0.48   -- end of cover zone (before NMZ)

    local coverColor = if isSnow
        then Color3.fromRGB(200, 212, 220)
        else Color3.fromRGB(110, 90, 65)
    local mat = Enum.Material.SmoothPlastic

    -- Small map: 4 per side, medium: 6, large: 8
    local count = if s >= 2 then 8 else if s >= 1.5 then 6 else 4

    for side = -1, 1, 2 do
        for i = 1, count do
            local x     = rng:NextNumber(-halfMap * 0.55, halfMap * 0.55)
            local z     = side * rng:NextNumber(coverStart, coverEnd)
            local choice = rng:NextInteger(1, 3)

            if choice == 1 then
                -- Simple low wall
                part("Cover_Wall_" .. side .. i,
                    Vector3.new(rng:NextNumber(8, 16) * s, 4 * s, 3 * s),
                    CFrame.new(x, 2*s, z), coverColor, mat, folder)

            elseif choice == 2 then
                -- L-shaped bunker (two walls)
                part("Cover_BunkA_" .. side .. i,
                    Vector3.new(12 * s, 5 * s, 3 * s),
                    CFrame.new(x, 2.5*s, z), coverColor, mat, folder)
                part("Cover_BunkB_" .. side .. i,
                    Vector3.new(3 * s, 5 * s, 8 * s),
                    CFrame.new(x + 7.5*s, 2.5*s, z + 5.5*s), coverColor, mat, folder)

            else
                -- Tall slit wall
                part("Cover_Slit_" .. side .. i,
                    Vector3.new(10 * s, 7 * s, 2.5 * s),
                    CFrame.new(x, 3.5*s, z), coverColor, mat, folder)
                -- Slit gap (no part — just leave the gap between the two halves)
                part("Cover_SlitT_" .. side .. i,
                    Vector3.new(10 * s, 3 * s, 2.5 * s),
                    CFrame.new(x, 8*s, z), coverColor, mat, folder)
            end
        end
    end
end

-- =====================================================
-- TREES (sparse, not in NMZ)
-- =====================================================

local function buildTrees(folder: Instance, halfMap: number, isSnow: boolean, s: number)
    local rng       = Random.new(55555)
    local count     = if s >= 2 then 20 else if s >= 1.5 then 12 else 7
    local nmzHalf   = halfMap * 0.18   -- keep trees out of NMZ

    for i = 1, count do
        local x = rng:NextNumber(-halfMap * 0.7, halfMap * 0.7)
        local z = rng:NextNumber(-halfMap * 0.7, halfMap * 0.7)
        -- Skip if in castle area or NMZ
        if math.abs(z) > halfMap * 0.78 then continue end
        if math.abs(z) < nmzHalf then continue end

        local trunkH = rng:NextNumber(10, 20) * s

        if isSnow then
            -- Pine tree
            part("Trunk_" .. i, Vector3.new(1.5, trunkH, 1.5),
                CFrame.new(x, trunkH/2, z), Color3.fromRGB(80, 55, 25), Enum.Material.Wood, folder)
            for layer = 0, 2 do
                local ls = 1 - layer * 0.28
                local lh = 5 * s * ls
                part("Pine_" .. i .. "_" .. layer,
                    Vector3.new(10 * s * ls, lh, 10 * s * ls),
                    CFrame.new(x, trunkH + layer * lh * 0.55 + lh/2, z),
                    Color3.fromRGB(25, 75, 35), Enum.Material.Grass, folder)
            end
        else
            -- Oak tree
            part("Trunk_" .. i, Vector3.new(1.5, trunkH, 1.5),
                CFrame.new(x, trunkH/2, z), Color3.fromRGB(80, 55, 25), Enum.Material.Wood, folder)
            local canopy = rng:NextNumber(14, 22) * s
            part("Canopy_" .. i, Vector3.new(canopy, canopy * 0.7, canopy),
                CFrame.new(x, trunkH + canopy * 0.25, z),
                Color3.fromRGB(25, 105, 25), Enum.Material.Grass, folder)
        end
    end
end

-- =====================================================
-- NMZ BOUNDS + VISIBLE FLOOR
-- =====================================================

local function buildNMZ(folder: Instance, halfMap: number): number
    local nmzHalf = halfMap * 0.20   -- NMZ = central 40% of map

    -- Invisible trigger walls
    for _, side in ipairs({-1, 1}) do
        local wall          = Instance.new("Part")
        wall.Name           = "NMZBound_" .. (if side == -1 then "A" else "B")
        wall.Size           = Vector3.new(halfMap * 2 + 40, 200, 2)
        wall.CFrame         = CFrame.new(0, 100, side * nmzHalf)
        wall.Anchored       = true
        wall.CanCollide     = false
        wall.Transparency   = 1
        wall.Parent         = folder
        local tag           = Instance.new("StringValue", wall)
        tag.Name            = "NMZTrigger"
        tag.Value           = if side == -1 then "EnterFromA" else "EnterFromB"
    end

    -- Visible NMZ floor stripe (more opaque than before, clearly visible)
    local indicator         = Instance.new("Part")
    indicator.Name          = "NMZFloor"
    indicator.Size          = Vector3.new(halfMap * 2, 0.3, nmzHalf * 2)
    indicator.CFrame        = CFrame.new(0, 0.5, 0)
    indicator.Anchored      = true
    indicator.CanCollide    = false
    indicator.Transparency  = 0.55
    indicator.Color         = Color3.fromRGB(220, 30, 30)
    indicator.Material      = Enum.Material.Neon
    indicator.CastShadow    = false
    indicator.Parent        = folder

    -- Glowing NMZ boundary lines (thin strips on each edge)
    for _, side in ipairs({-1, 1}) do
        local line          = Instance.new("Part")
        line.Name           = "NMZLine_" .. side
        line.Size           = Vector3.new(halfMap * 2, 3, 1)
        line.CFrame         = CFrame.new(0, 1.5, side * nmzHalf)
        line.Anchored       = true
        line.CanCollide     = false
        line.Transparency   = 0.1
        line.Color          = Color3.fromRGB(255, 50, 50)
        line.Material       = Enum.Material.Neon
        line.CastShadow     = false
        line.Parent         = folder
    end

    return nmzHalf
end

-- =====================================================
-- SPAWN POINTS
-- =====================================================

local function buildSpawnPoints(folder: Instance, halfMap: number, playerCount: number)
    local spawnA = Instance.new("Folder"); spawnA.Name = "TeamA"; spawnA.Parent = folder
    local spawnB = Instance.new("Folder"); spawnB.Name = "TeamB"; spawnB.Parent = folder

    local count     = math.max(playerCount, 4)
    local spread    = math.min(50, halfMap * 0.25)

    for i = 1, count do
        local xOffset = (i - (count + 1) / 2) * (spread / count) * 2

        local sA    = Instance.new("SpawnLocation")
        sA.Name     = "SpawnA" .. i
        sA.Size     = Vector3.new(4, 1, 4)
        sA.CFrame   = CFrame.new(xOffset, 4, -halfMap * 0.82)
        sA.Anchored = true
        sA.Neutral  = false
        sA.Duration = 0
        sA.Parent   = spawnA

        local sB    = Instance.new("SpawnLocation")
        sB.Name     = "SpawnB" .. i
        sB.Size     = Vector3.new(4, 1, 4)
        sB.CFrame   = CFrame.new(xOffset, 4,  halfMap * 0.82)
        sB.Anchored = true
        sB.Neutral  = false
        sB.Duration = 0
        sB.Parent   = spawnB
    end
end

-- =====================================================
-- FLAGS
-- =====================================================

local function placeFlags(folder: Instance, halfMap: number, s: number)
    local function makeFlag(name: string, cz: number, color: Color3)
        -- Pole
        part(name .. "Pole", Vector3.new(0.6, 10 * s, 0.6),
            CFrame.new(0, (halfMap * 0.82 > 0 and 1 or 1) + 5*s, cz),
            Color3.fromRGB(180, 150, 80), Enum.Material.Metal, folder)
        -- Flag cloth
        local f = part(name, Vector3.new(7 * s, 4 * s, 0.5),
            CFrame.new(3.5 * s, 1 + 9*s, cz), color, Enum.Material.SmoothPlastic, folder)
        return f
    end

    -- Flags sit at castle back, on top of the flag tower
    -- The flag tower top is at FY + FTH + 2 ≈ scale-dependent
    -- We keep it simple and place at Y=1 (MapManager stacks on terrain height)
    -- FlagManager references them by name "FlagA" and "FlagB"
    makeFlag("FlagA", -halfMap * 0.82, Color3.fromRGB(220, 50, 50))
    makeFlag("FlagB",  halfMap * 0.82, Color3.fromRGB(50, 80, 220))
end

-- =====================================================
-- CENTER POWER-UP
-- =====================================================

local function placePowerUp()
    local p             = Instance.new("Part")
    p.Name              = "CenterPowerUp"
    p.Anchored          = true
    p.Size              = Vector3.new(6, 6, 6)
    p.CFrame            = CFrame.new(0, 8, 0)   -- elevated above terrain
    p.Material          = Enum.Material.Neon
    p.Color             = Color3.fromRGB(255, 220, 50)
    p.CastShadow        = false
    p.Parent            = workspace

    local light         = Instance.new("PointLight", p)
    light.Brightness    = 6
    light.Range         = 30
    light.Color         = Color3.fromRGB(255, 220, 50)

    -- Label above the block
    local billboard     = Instance.new("BillboardGui", p)
    billboard.Size      = UDim2.new(0, 200, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 5, 0)
    billboard.AlwaysOnTop = false
    local lbl           = Instance.new("TextLabel", billboard)
    lbl.Size            = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text            = "⚡ 2.5x HEALTH"
    lbl.TextColor3      = Color3.fromRGB(255, 230, 80)
    lbl.Font            = Enum.Font.GothamBold
    lbl.TextSize        = 18
    lbl.TextStrokeTransparency = 0.3
end

-- =====================================================
-- LIGHTING
-- =====================================================

function MapManager:_applyLighting(isSnow: boolean)
    local L = game:GetService("Lighting")
    if isSnow then
        L.Ambient       = Color3.fromRGB(155, 175, 205)
        L.OutdoorAmbient = Color3.fromRGB(175, 195, 225)
        L.TimeOfDay     = "14:00:00"
        L.Brightness    = 2
        L.FogColor      = Color3.fromRGB(200, 210, 230)
        L.FogEnd        = 900
        L.FogStart      = 400
    else
        L.Ambient       = Color3.fromRGB(120, 130, 100)
        L.OutdoorAmbient = Color3.fromRGB(140, 160, 110)
        L.TimeOfDay     = "12:00:00"
        L.Brightness    = 2.5
        L.FogEnd        = 1400
        L.FogStart      = 700
    end
end

-- =====================================================
-- PUBLIC API
-- =====================================================

function MapManager:GenerateMap(mapName: string, playerCount: number)
    local mapSize   = resolveMapSize(playerCount)
    local halfMap   = mapSize / 2
    local s         = mapSize / 400
    local isSnow    = mapName == "snow"

    print("[MapManager] Generating", mapName, "map |", mapSize, "studs | scale:", s)

    local root          = Instance.new("Folder")
    root.Name           = "GeneratedMap"
    root.Parent         = workspace

    local nmzFolder     = Instance.new("Folder")
    nmzFolder.Name      = "NMZBounds"
    nmzFolder.Parent    = workspace

    local spawnFolder   = Instance.new("Folder")
    spawnFolder.Name    = "SpawnPoints"
    spawnFolder.Parent  = workspace

    local flagFolder    = Instance.new("Folder")
    flagFolder.Name     = "Flags"
    flagFolder.Parent   = workspace

    buildTerrain(mapSize, isSnow)

    -- Castles (Team A: -Z side, Team B: +Z side)
    local castleFolder  = Instance.new("Folder", root)
    castleFolder.Name   = "Castles"
    buildCastle(castleFolder, 0, -halfMap * 0.85, Color3.fromRGB(200, 50, 50), mapSize)
    buildCastle(castleFolder, 0,  halfMap * 0.85, Color3.fromRGB(50, 80, 220), mapSize)

    local coverFolder   = Instance.new("Folder", root)
    coverFolder.Name    = "Cover"
    buildCover(coverFolder, halfMap, isSnow, s)

    local treeFolder    = Instance.new("Folder", root)
    treeFolder.Name     = "Trees"
    buildTrees(treeFolder, halfMap, isSnow, s)

    buildNMZ(nmzFolder, halfMap)
    buildSpawnPoints(spawnFolder, halfMap, playerCount)
    placeFlags(flagFolder, halfMap, s)
    placePowerUp()
    self:_applyLighting(isSnow)

    print("[MapManager] Done.")
end

function MapManager:ClearMap()
    local function remove(name: string)
        local obj = workspace:FindFirstChild(name)
        if obj then obj:Destroy() end
    end
    remove("GeneratedMap")
    remove("NMZBounds")
    remove("SpawnPoints")
    remove("Flags")
    remove("CenterPowerUp")
    workspace.Terrain:Clear()
end

return MapManager

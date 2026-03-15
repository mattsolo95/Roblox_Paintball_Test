--!strict
-- LobbyManager.luau (Server Module)
-- Builds the Monte Carlo-style lobby and manages player positions within it.
-- Floors: Ground (main lobby), 2nd (cafe + binoculars), 3rd (lounge + binoculars), Rooftop.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes    = require(ReplicatedStorage:WaitForChild("Remotes"))

local LobbyManager = {}

local LOBBY_FOLDER  = "Lobby"
local GLASS_COLOR   = Color3.fromRGB(180, 210, 240)
local MARBLE_COLOR  = Color3.fromRGB(230, 225, 215)
local ACCENT_COLOR  = Color3.fromRGB(180, 150, 80)   -- gold trim

-- Lobby center position (keep well clear of the map area)
local LOBBY_CENTER  = Vector3.new(0, 0, 2000)

local function makePart(
    name: string, size: Vector3, cf: CFrame,
    color: Color3, material: Enum.Material,
    transparency: number, parent: Instance
): Part
    local p             = Instance.new("Part")
    p.Name              = name
    p.Size              = size
    p.CFrame            = cf
    p.Color             = color
    p.Material          = material
    p.Transparency      = transparency
    p.Anchored          = true
    p.TopSurface        = Enum.SurfaceType.Smooth
    p.BottomSurface     = Enum.SurfaceType.Smooth
    p.CastShadow        = false
    p.Parent            = parent
    return p
end

-- =====================================================
-- LOBBY CONSTRUCTION
-- =====================================================

local function buildLobby(root: Folder)
    local c = LOBBY_CENTER

    -- Floor heights
    local y0 = c.Y          -- Ground floor (Y=0 of lobby)
    local y1 = c.Y + 18     -- 2nd floor (cafe)
    local y2 = c.Y + 36     -- 3rd floor (lounge)
    local y3 = c.Y + 54     -- Rooftop

    local W = 80    -- lobby width (X)
    local D = 60    -- lobby depth (Z)

    -- Ground floor
    makePart("Floor0",  Vector3.new(W, 2, D),   CFrame.new(c.X, y0,   c.Z), MARBLE_COLOR, Enum.Material.Marble,       0,   root)
    makePart("Floor1",  Vector3.new(W, 2, D),   CFrame.new(c.X, y1,   c.Z), MARBLE_COLOR, Enum.Material.Marble,       0,   root)
    makePart("Floor2",  Vector3.new(W, 2, D),   CFrame.new(c.X, y2,   c.Z), MARBLE_COLOR, Enum.Material.Marble,       0,   root)
    makePart("Rooftop", Vector3.new(W + 4, 2, D + 4), CFrame.new(c.X, y3, c.Z), Color3.fromRGB(60, 60, 60), Enum.Material.SmoothPlastic, 0, root)

    -- Panoramic glass walls (all 4 sides, all floors)
    local wallH = 16
    for _, floorY in ipairs({y0, y1, y2}) do
        -- Front/back walls (glass)
        makePart("GlassFront_" .. floorY, Vector3.new(W, wallH, 1),
            CFrame.new(c.X, floorY + wallH/2 + 1, c.Z + D/2),
            GLASS_COLOR, Enum.Material.Glass, 0.3, root)
        makePart("GlassBack_"  .. floorY, Vector3.new(W, wallH, 1),
            CFrame.new(c.X, floorY + wallH/2 + 1, c.Z - D/2),
            GLASS_COLOR, Enum.Material.Glass, 0.3, root)
        -- Side walls (glass)
        makePart("GlassLeft_"  .. floorY, Vector3.new(1, wallH, D),
            CFrame.new(c.X - W/2, floorY + wallH/2 + 1, c.Z),
            GLASS_COLOR, Enum.Material.Glass, 0.3, root)
        makePart("GlassRight_" .. floorY, Vector3.new(1, wallH, D),
            CFrame.new(c.X + W/2, floorY + wallH/2 + 1, c.Z),
            GLASS_COLOR, Enum.Material.Glass, 0.3, root)
    end

    -- Rooftop railings
    for _, side in ipairs({-1, 1}) do
        makePart("Railing_X_" .. side,
            Vector3.new(W + 4, 4, 1),
            CFrame.new(c.X, y3 + 3, c.Z + side * (D/2 + 2)),
            ACCENT_COLOR, Enum.Material.Metal, 0, root)
        makePart("Railing_Z_" .. side,
            Vector3.new(1, 4, D + 4),
            CFrame.new(c.X + side * (W/2 + 2), y3 + 3, c.Z),
            ACCENT_COLOR, Enum.Material.Metal, 0, root)
    end

    -- Staircases (simple angled ramps connecting floors)
    local rampColor = Color3.fromRGB(210, 200, 185)
    for i, floorY in ipairs({y0, y1, y2}) do
        local nextY = floorY + 18
        local angle = math.atan2(nextY - floorY, 12)
        local ramp  = makePart("Ramp_" .. i,
            Vector3.new(8, 1, 14),
            CFrame.new(c.X + W/2 - 10, (floorY + nextY) / 2, c.Z - 15)
                * CFrame.Angles(-angle, 0, 0),
            rampColor, Enum.Material.Marble, 0, root)
        _ = ramp
    end

    -- Binocular stands (2nd and 3rd floor + rooftop)
    for _, floorY in ipairs({y1, y2, y3}) do
        for _, xPos in ipairs({c.X - 25, c.X + 25}) do
            local stand = makePart("BinocularStand",
                Vector3.new(2, 4, 2),
                CFrame.new(xPos, floorY + 4, c.Z + D/2 - 3),
                Color3.fromRGB(60, 60, 80), Enum.Material.Metal, 0, root)
            _ = stand

            -- ProximityPrompt so players can interact
            local prompt            = Instance.new("ProximityPrompt")
            prompt.ActionText       = "Use Binoculars"
            prompt.ObjectText       = "Binoculars"
            prompt.MaxActivationDistance = 8
            prompt.HoldDuration     = 0
            prompt.Parent           = stand
        end
    end

    -- Ocean backdrop (large plane simulating water surface)
    makePart("OceanPlane",
        Vector3.new(2000, 1, 2000),
        CFrame.new(c.X, c.Y - 5, c.Z + 800),
        Color3.fromRGB(30, 100, 180), Enum.Material.Water, 0.2, root)

    -- Distant mountain silhouettes (large wedge parts)
    for i = 1, 5 do
        local mx = c.X + (i - 3) * 300
        local wedge = Instance.new("WedgePart")
        wedge.Name          = "Mountain_" .. i
        wedge.Size          = Vector3.new(200, 150 + i * 40, 100)
        wedge.CFrame        = CFrame.new(mx, c.Y + 75 + i * 20, c.Z - 400)
        wedge.Anchored      = true
        wedge.Color         = Color3.fromRGB(120, 110, 100)
        wedge.Material      = Enum.Material.Rock
        wedge.CastShadow    = false
        wedge.Parent        = root
    end

    -- Lobby ambient sound (ocean + seagulls feel — use SoundId from Roblox catalog)
    local ambientSound          = Instance.new("Sound")
    ambientSound.Name           = "LobbyAmbience"
    ambientSound.SoundId        = "rbxassetid://1839919157"   -- ocean waves
    ambientSound.Volume         = 0.4
    ambientSound.Looped         = true
    ambientSound.RollOffMaxDistance = 200
    ambientSound.Parent         = root
    ambientSound:Play()
end

-- =====================================================
-- PLAYER POSITIONING
-- =====================================================

function LobbyManager:MovePlayersToLobby()
    local y     = LOBBY_CENTER.Y + 2
    local all   = Players:GetPlayers()
    for i, player in ipairs(all) do
        local char = player.Character or player.CharacterAdded:Wait()
        local hrp  = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if hrp then
            local xOffset = (i - (#all / 2)) * 6
            hrp.CFrame = CFrame.new(
                LOBBY_CENTER.X + xOffset,
                y + 3,
                LOBBY_CENTER.Z
            )
        end
    end
end

function LobbyManager:MovePlayersToRooftop()
    local rooftopY  = LOBBY_CENTER.Y + 56   -- just above rooftop floor
    local all       = Players:GetPlayers()
    for i, player in ipairs(all) do
        local char = player.Character or player.CharacterAdded:Wait()
        local hrp  = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if hrp then
            local xOffset = (i - (#all / 2)) * 5
            hrp.CFrame = CFrame.new(
                LOBBY_CENTER.X + xOffset,
                rooftopY,
                LOBBY_CENTER.Z - 20   -- lined up on the edge looking at the ocean
            )
        end
    end
end

-- =====================================================
-- BINOCULARS
-- =====================================================

Remotes.OnServer("BinocularsToggle", function(player: Player)
    -- Tell the client to toggle zoom; the CameraController handles it
    Remotes.FireClient("BinocularsToggle", player)
end)

-- =====================================================
-- INITIALIZE
-- =====================================================

function LobbyManager:Initialize()
    -- Remove old lobby if any
    local old = workspace:FindFirstChild(LOBBY_FOLDER)
    if old then old:Destroy() end

    local root      = Instance.new("Folder")
    root.Name       = LOBBY_FOLDER
    root.Parent     = workspace

    buildLobby(root)
    print("[LobbyManager] Lobby built.")
end

return LobbyManager

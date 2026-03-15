--!strict
-- CameraController.luau (Client Module)
-- Controls camera behavior per game state:
--   LOBBY    → cinematic, slowly panning the ocean/mountain view
--   GAMEPLAY → Roblox default (scriptable follows character)
--   SPECTATOR → follows a random alive ally after death
--   TIEBREAKER → cinematic following the duelists
--   PODIUM   → orbits the podium area

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local Remotes           = require(game:GetService("ReplicatedStorage"):WaitForChild("Remotes"))

local CameraController  = {}
local localPlayer       = Players.LocalPlayer
local camera            = workspace.CurrentCamera

local _mode         = "LOBBY"
local _heartbeat:   RBXScriptConnection?    = nil
local _panAngle     = 0     -- for lobby cinematic pan

-- Binoculars zoom
local _binocularsActive = false
local DEFAULT_FOV       = 70
local BINOCULARS_FOV    = 15

-- =====================================================
-- INITIALIZE
-- =====================================================

function CameraController:Initialize()
    camera.CameraType = Enum.CameraType.Scriptable

    _heartbeat = RunService.RenderStepped:Connect(function(dt: number)
        self:_update(dt)
    end)

    Remotes.OnClient("BinocularsToggle", function()
        self:_toggleBinoculars()
    end)

    Remotes.OnClient("TiebreakerStart", function()
        self:SetMode("TIEBREAKER")
    end)
end

-- =====================================================
-- MODE SETTING
-- =====================================================

function CameraController:SetMode(mode: string)
    _mode = mode

    if mode == "GAMEPLAY" then
        camera.CameraType = Enum.CameraType.Custom
    else
        camera.CameraType = Enum.CameraType.Scriptable
    end

    if mode == "PODIUM" then
        self:_startPodiumCamera()
    end
end

-- =====================================================
-- PER-FRAME UPDATE
-- =====================================================

function CameraController:_update(dt: number)
    if _mode == "LOBBY" or _mode == "COUNTDOWN" then
        self:_updateLobbyCamera(dt)

    elseif _mode == "SPECTATOR" then
        self:_updateSpectatorCamera()

    elseif _mode == "TIEBREAKER" then
        self:_updateTiebreakerCamera(dt)
    end
end

-- =====================================================
-- LOBBY / COUNTDOWN CAMERA
-- Slowly pans looking at the ocean from the rooftop.
-- =====================================================

function CameraController:_updateLobbyCamera(dt: number)
    local lobby = workspace:FindFirstChild("Lobby")
    if not lobby then return end

    -- Lobby is built at Z=2000; rooftop is at Y=54
    -- Slowly pan camera looking out over the ocean (positive Z direction)
    _panAngle += dt * 0.06

    local lobbyZ    = 2000
    local rooftopY  = 56
    local radius    = 50

    local camPos = Vector3.new(
        radius * math.cos(_panAngle),
        rooftopY,
        lobbyZ - 25 + radius * math.sin(_panAngle) * 0.4
    )
    local lookAt = Vector3.new(0, rooftopY - 5, lobbyZ + 300)  -- look out at the ocean

    camera.CFrame       = CFrame.new(camPos, lookAt)
    camera.FieldOfView  = 55
end

-- =====================================================
-- SPECTATOR CAMERA (after death)
-- Follows a random alive ally.
-- =====================================================

local _spectatorTarget: Player? = nil

function CameraController:_updateSpectatorCamera()
    -- Find a valid target
    if not _spectatorTarget
       or not _spectatorTarget.Character
       or not _spectatorTarget.Character:FindFirstChildOfClass("Humanoid")
       or (_spectatorTarget.Character:FindFirstChildOfClass("Humanoid") :: Humanoid).Health <= 0
    then
        -- Pick any alive player
        local candidates = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer then
                local char = p.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
                if hum and hum.Health > 0 then
                    table.insert(candidates, p)
                end
            end
        end
        _spectatorTarget = if #candidates > 0
            then candidates[math.random(1, #candidates)]
            else nil
    end

    if _spectatorTarget then
        local char  = _spectatorTarget.Character
        local hrp   = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if hrp then
            local offset = hrp.CFrame:VectorToWorldSpace(Vector3.new(0, 8, 18))
            camera.CFrame = CFrame.new(hrp.Position + offset, hrp.Position)
        end
    end
end

-- =====================================================
-- TIEBREAKER CAMERA
-- Tries to frame both duelists.
-- =====================================================

function CameraController:_updateTiebreakerCamera(dt: number)
    _panAngle += dt * 0.12

    -- Look toward center of NMZ
    local centerPos = Vector3.new(0, 10, 0)
    local radius    = 60

    local camPos = Vector3.new(
        centerPos.X + radius * math.cos(_panAngle),
        centerPos.Y + 20,
        centerPos.Z + radius * math.sin(_panAngle)
    )
    camera.CFrame       = CFrame.new(camPos, centerPos)
    camera.FieldOfView  = 65
end

-- =====================================================
-- PODIUM CAMERA
-- Slowly orbits around x=0, z=0 at ground level.
-- =====================================================

function CameraController:_startPodiumCamera()
    _panAngle = 0
    -- Tween FOV to cinematic
    TweenService:Create(camera, TweenInfo.new(1.5), { FieldOfView = 45 }):Play()
end

-- =====================================================
-- BINOCULARS
-- =====================================================

function CameraController:_toggleBinoculars()
    _binocularsActive = not _binocularsActive
    local targetFOV = if _binocularsActive then BINOCULARS_FOV else DEFAULT_FOV
    TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quart),
        { FieldOfView = targetFOV }):Play()
end

-- =====================================================
-- REACT TO DEATH (switch to spectator)
-- =====================================================

local function onCharacterAdded(char: Model)
    -- When character re-spawns, return to gameplay camera
    if _mode == "SPECTATOR" then
        CameraController:SetMode("GAMEPLAY")
    end

    local hum = char:WaitForChild("Humanoid") :: Humanoid
    hum.Died:Connect(function()
        if _mode == "GAMEPLAY" then
            CameraController:SetMode("SPECTATOR")
        end
    end)
end

if localPlayer.Character then
    onCharacterAdded(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(onCharacterAdded)

return CameraController

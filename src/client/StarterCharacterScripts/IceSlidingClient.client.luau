--!strict
-- IceSlidingClient.client.luau  (StarterCharacterScripts)
-- Runs fresh every time the player's character spawns.
-- Detects ice terrain underfoot via raycast, applies sliding physics,
-- and plays surface-appropriate footstep sounds.

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig    = require(ReplicatedStorage:WaitForChild("GameConfig"))

local localPlayer   = Players.LocalPlayer
local character     = script.Parent              -- the character model
local humanoid      = character:WaitForChild("Humanoid") :: Humanoid
local hrp           = character:WaitForChild("HumanoidRootPart") :: BasePart

-- =====================================================
-- SOUNDS
-- =====================================================

local function makeSound(id: string, parent: Instance): Sound
    local s         = Instance.new("Sound")
    s.SoundId       = id
    s.Volume        = 0.4
    s.RollOffMaxDistance = 40
    s.Parent        = parent
    return s
end

-- Sound IDs (Roblox catalog — replace with custom sounds later)
local snowStepSound = makeSound("rbxassetid://5798865159", hrp)  -- crunchy snow
local grassStepSound = makeSound("rbxassetid://6333702987", hrp) -- grass footstep
local iceSlideSound  = makeSound("rbxassetid://4612395429", hrp) -- ice slide hiss

iceSlideSound.Looped = true

-- =====================================================
-- STATE
-- =====================================================

local isOnIce       = false
local wasMoving     = false
local stepTimer     = 0
local STEP_INTERVAL = 0.38    -- seconds between footstep sounds

-- =====================================================
-- SURFACE DETECTION
-- =====================================================

local function getSurfaceMaterial(): Enum.Material?
    local params            = RaycastParams.new()
    params.FilterType       = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }

    local result = workspace:Raycast(
        hrp.Position,
        Vector3.new(0, -5, 0),
        params
    )
    if result then
        return result.Material
    end
    return nil
end

-- =====================================================
-- ICE PHYSICS
-- =====================================================

local originalWalkSpeed: number = humanoid.WalkSpeed
local originalFriction: number  = 0.3   -- Roblox default physical friction

local function applyIcePhysics()
    humanoid.WalkSpeed  = GameConfig.ICE_SLIDE_SPEED

    -- Reduce physical material friction by changing HRP's CustomPhysicalProperties
    local props = PhysicalProperties.new(
        0.7,                            -- density
        GameConfig.ICE_FRICTION,        -- friction
        0.0,                            -- elasticity
        0.0,                            -- frictionWeight
        0.0                             -- elasticityWeight
    )
    hrp.CustomPhysicalProperties = props

    if not iceSlideSound.IsPlaying then
        iceSlideSound:Play()
    end
end

local function removeIcePhysics()
    humanoid.WalkSpeed = originalWalkSpeed

    local props = PhysicalProperties.new(
        0.7,
        GameConfig.NORMAL_FRICTION,
        0.0, 0.0, 0.0
    )
    hrp.CustomPhysicalProperties = props

    if iceSlideSound.IsPlaying then
        iceSlideSound:Stop()
    end
end

-- =====================================================
-- FOOTSTEP SOUNDS
-- =====================================================

local function playFootstep(material: Enum.Material?)
    if material == Enum.Material.Snow then
        snowStepSound:Play()
    elseif material == Enum.Material.Grass then
        grassStepSound:Play()
    end
    -- Ice has its own looping slide sound, no step needed
end

-- =====================================================
-- MAIN LOOP
-- =====================================================

RunService.Heartbeat:Connect(function(dt: number)
    if humanoid.Health <= 0 then return end

    local material = getSurfaceMaterial()
    local onIceNow = (material == Enum.Material.Ice)

    -- Transition in/out of ice
    if onIceNow and not isOnIce then
        isOnIce = true
        applyIcePhysics()
    elseif not onIceNow and isOnIce then
        isOnIce = false
        removeIcePhysics()
    end

    -- Footstep timing (play when moving and grounded)
    local speed = hrp.AssemblyLinearVelocity.Magnitude
    local isMoving = speed > 1.5

    if isMoving and not isOnIce then
        stepTimer -= dt
        if stepTimer <= 0 then
            stepTimer = STEP_INTERVAL
            playFootstep(material)
        end
    else
        stepTimer = 0
    end

    wasMoving = isMoving
end)

-- Clean up on character removal
character.AncestryChanged:Connect(function()
    if not character.Parent then
        iceSlideSound:Stop()
    end
end)

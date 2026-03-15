--!strict
-- FlagManager.luau (Server Module)
-- Manages flag pickup, carrying, capture, drop, and auto-return.
-- Flags live at the top of each castle. Opposing team must bring it to their base.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig    = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes       = require(ReplicatedStorage:WaitForChild("Remotes"))

local FlagManager = {}

type FlagState = "AT_BASE" | "CARRIED" | "DROPPED"

type Flag = {
    part:           BasePart,
    teamId:         string,       -- which team owns this flag ("A" = Alpha's flag)
    homePosition:   CFrame,
    state:          FlagState,
    carrier:        Player?,
    dropTime:       number?,
    returnThread:   thread?,
    touchConn:      RBXScriptConnection?,
    carrierDiedConn: RBXScriptConnection?,
}

local _scoringManager: any  = nil
local _teamManager: any     = nil
local flags: {Flag}         = {}
local connections: {RBXScriptConnection} = {}

-- =====================================================
-- SETUP
-- =====================================================

function FlagManager:SetDependencies(scoringMgr: any, teamMgr: any)
    _scoringManager = scoringMgr
    _teamManager    = teamMgr
end

function FlagManager:Initialize()
    flags       = {}
    connections = {}

    -- Flags are placed by MapManager as Parts named "FlagA" and "FlagB"
    -- under a Folder called "Flags" in Workspace.
    local flagFolder = workspace:FindFirstChild("Flags")
    if not flagFolder then
        warn("[FlagManager] No 'Flags' folder found in Workspace.")
        return
    end

    for _, part in ipairs(flagFolder:GetChildren()) do
        if not part:IsA("BasePart") then continue end

        local teamId = if part.Name == "FlagA" then "A" else "B"
        local flag: Flag = {
            part            = part :: BasePart,
            teamId          = teamId,
            homePosition    = part.CFrame,
            state           = "AT_BASE",
            carrier         = nil,
            dropTime        = nil,
            returnThread    = nil,
            touchConn       = nil,
            carrierDiedConn = nil,
        }
        table.insert(flags, flag)
        FlagManager:_attachTouchDetection(flag)
    end
end

-- =====================================================
-- TOUCH DETECTION
-- =====================================================

function FlagManager:_attachTouchDetection(flag: Flag)
    flag.touchConn = flag.part.Touched:Connect(function(hit: BasePart)
        if flag.state == "CARRIED" then return end

        local char = hit.Parent
        if not char then return end
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end

        local playerTeam = _teamManager and _teamManager:GetTeamId(player)
        if not playerTeam then return end

        if flag.state == "AT_BASE" or flag.state == "DROPPED" then
            if playerTeam ~= flag.teamId then
                -- Enemy picks up flag
                FlagManager:_pickup(flag, player)
            elseif flag.state == "DROPPED" then
                -- Same team returns dropped flag
                FlagManager:_returnToBase(flag)
            else
                -- Same team touches own flag while at base — check if they're carrying enemy flag
                FlagManager:_checkCapture(player)
            end
        end
    end)
end

-- =====================================================
-- PICKUP
-- =====================================================

function FlagManager:_pickup(flag: Flag, carrier: Player)
    flag.state    = "CARRIED"
    flag.carrier  = carrier

    -- Cancel any pending auto-return
    if flag.returnThread then task.cancel(flag.returnThread) end
    flag.returnThread = nil

    -- Attach flag to carrier's head visually
    local char = carrier.Character
    local head = char and char:FindFirstChild("Head") :: BasePart?
    if head then
        flag.part.Anchored = false
        local weld          = Instance.new("WeldConstraint")
        weld.Part0          = flag.part
        weld.Part1          = head
        weld.Parent         = flag.part
        flag.part.CFrame    = head.CFrame * CFrame.new(0, 2, 0)
    end

    -- If carrier dies, drop the flag
    local humanoid = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if humanoid then
        flag.carrierDiedConn = humanoid.Died:Connect(function()
            FlagManager:_drop(flag)
        end)
    end

    Remotes.FireAll("FlagPickedUp", carrier.Name, flag.teamId)
    print("[FlagManager] Flag", flag.teamId, "picked up by", carrier.Name)
end

-- =====================================================
-- DROP
-- =====================================================

function FlagManager:_drop(flag: Flag)
    if flag.carrierDiedConn then
        flag.carrierDiedConn:Disconnect()
        flag.carrierDiedConn = nil
    end

    -- Remove welds
    for _, obj in ipairs(flag.part:GetChildren()) do
        if obj:IsA("WeldConstraint") then obj:Destroy() end
    end

    flag.part.Anchored  = true
    flag.state          = "DROPPED"
    flag.dropTime       = os.clock()
    flag.carrier        = nil

    Remotes.FireAll("FlagDropped", flag.teamId)

    -- Auto-return after FLAG_AUTO_RETURN_TIME
    flag.returnThread = task.delay(GameConfig.FLAG_AUTO_RETURN_TIME, function()
        if flag.state == "DROPPED" then
            FlagManager:_returnToBase(flag)
        end
    end)
end

-- =====================================================
-- RETURN TO BASE
-- =====================================================

function FlagManager:_returnToBase(flag: Flag)
    if flag.returnThread then task.cancel(flag.returnThread) end
    flag.returnThread   = nil

    flag.part.Anchored  = true
    flag.part.CFrame    = flag.homePosition
    flag.state          = "AT_BASE"
    flag.carrier        = nil
    flag.dropTime       = nil

    print("[FlagManager] Flag", flag.teamId, "returned to base.")
end

-- =====================================================
-- CAPTURE CHECK
-- =====================================================

-- Called when a player touches their OWN team's flag stand.
-- If they're carrying the enemy flag, it's a capture!
function FlagManager:_checkCapture(player: Player)
    local playerTeam = _teamManager and _teamManager:GetTeamId(player)
    if not playerTeam then return end

    for _, flag in ipairs(flags) do
        -- Find the flag being carried by this player that belongs to the enemy
        if flag.state == "CARRIED" and flag.carrier == player and flag.teamId ~= playerTeam then
            -- CAPTURE!
            if _scoringManager then
                _scoringManager:RegisterFlagCapture(player)
            end
            FlagManager:_returnToBase(flag)
            print("[FlagManager] CAPTURE by", player.Name, "for team", playerTeam)
            return
        end
    end
end

-- =====================================================
-- RESET / CLEANUP
-- =====================================================

function FlagManager:ResetFlags()
    for _, flag in ipairs(flags) do
        if flag.carrier and flag.carrierDiedConn then
            flag.carrierDiedConn:Disconnect()
        end
        if flag.returnThread then task.cancel(flag.returnThread) end
        self:_returnToBase(flag)
    end
end

function FlagManager:Cleanup()
    self:ResetFlags()
    for _, conn in ipairs(connections) do conn:Disconnect() end
    connections = {}
    for _, flag in ipairs(flags) do
        if flag.touchConn then flag.touchConn:Disconnect() end
    end
    flags = {}
end

return FlagManager

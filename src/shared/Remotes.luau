--!strict
-- Remotes.luau
-- Creates (server) or retrieves (client) every RemoteEvent and RemoteFunction.
-- Require this module early — it blocks until the folder is ready.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

-- =====================================================
-- REMOTE EVENT NAMES  (payload described in comment)
-- =====================================================
local EVENTS: { string } = {
    -- Game flow
    "GameStateChanged",         -- (stateName: string, data: {})
    "TimerUpdate",              -- (secondsRemaining: number)
    "ScoreUpdate",              -- (aScore, bScore, aWins, bWins: number)
    "ShowCountdown",            -- (seconds: number)

    -- Map / loading
    "ShowLoadingScreen",        -- (mapName: string)
    "HideLoadingScreen",        -- ()

    -- Teams / voting
    "StartTeamVote",            -- (colorOptions: table)
    "CastTeamVote",             -- CLIENT→SERVER: (colorIndex: number)
    "TeamVoteResult",           -- (colorA: table, colorB: table)

    -- No Man's Zone
    "NoManZoneEntered",         -- ()
    "NoManZoneExited",          -- ()

    -- Combat events
    "TakedownEvent",            -- (attackerName, victimName, points, inNMZ)
    "AssistEvent",              -- (assistName, victimName, points)
    "KillFeedUpdate",           -- (attackerName, victimName, weaponName)
    "HitEffect",                -- (position: Vector3, normal: Vector3, color: Color3)
    "AmmoUpdate",               -- (current: number, max: number, reloading: boolean)
    "PlayerRespawnCountdown",   -- (seconds: number)  — sent only to dying player

    -- Weapons (client fires to server)
    "WeaponFired",              -- CLIENT→SERVER: (weaponName, origin: Vector3, direction: Vector3)

    -- Flags
    "FlagPickedUp",             -- (playerName, teamName)
    "FlagDropped",              -- (teamName)
    "FlagCaptured",             -- (playerName, teamName, points)

    -- Power-up
    "PowerUpCollected",         -- (playerName)
    "PowerUpRespawned",         -- ()

    -- End-game
    "ShowVictoryScreen",        -- (teamName, teamColor: Color3, isRoundWin: bool)
    "ShowPodium",               -- (podiumEntries: table)
    "PlayConfetti",             -- ()
    "TiebreakerStart",          -- (p1Name, p2Name)

    -- Lobby
    "BinocularsToggle",         -- CLIENT→SERVER: ()
}

local FUNCTIONS: { string } = {
    "GetGameState",             -- () → { stateName, aScore, bScore, aWins, bWins }
}

-- =====================================================
-- MODULE
-- =====================================================
local Remotes = {}
local _folder: Folder

if IS_SERVER then
    _folder      = Instance.new("Folder")
    _folder.Name = "GameRemotes"
    _folder.Parent = ReplicatedStorage

    for _, name in ipairs(EVENTS) do
        local re    = Instance.new("RemoteEvent")
        re.Name     = name
        re.Parent   = _folder
    end
    for _, name in ipairs(FUNCTIONS) do
        local rf    = Instance.new("RemoteFunction")
        rf.Name     = name
        rf.Parent   = _folder
    end
else
    _folder = ReplicatedStorage:WaitForChild("GameRemotes", 20)
    assert(_folder, "[Remotes] Timed out waiting for GameRemotes folder")
end

local function get(name: string): Instance
    local obj = _folder:WaitForChild(name, 10)
    assert(obj, "[Remotes] Remote not found: " .. name)
    return obj
end

-- =====================================================
-- SERVER-SIDE HELPERS
-- =====================================================

function Remotes.FireAll(name: string, ...: any)
    (get(name) :: RemoteEvent):FireAllClients(...)
end

function Remotes.FireClient(name: string, player: Player, ...: any)
    (get(name) :: RemoteEvent):FireClient(player, ...)
end

function Remotes.OnServer(name: string, callback: (Player, ...any) -> ()): RBXScriptConnection
    return (get(name) :: RemoteEvent).OnServerEvent:Connect(callback)
end

function Remotes.BindFunction(name: string, callback: (Player, ...any) -> ...any)
    (get(name) :: RemoteFunction).OnServerInvoke = callback
end

-- =====================================================
-- CLIENT-SIDE HELPERS
-- =====================================================

function Remotes.OnClient(name: string, callback: (...any) -> ()): RBXScriptConnection
    return (get(name) :: RemoteEvent).OnClientEvent:Connect(callback)
end

function Remotes.FireServer(name: string, ...: any)
    (get(name) :: RemoteEvent):FireServer(...)
end

function Remotes.Invoke(name: string, ...: any): ...any
    return (get(name) :: RemoteFunction):InvokeServer(...)
end

return Remotes

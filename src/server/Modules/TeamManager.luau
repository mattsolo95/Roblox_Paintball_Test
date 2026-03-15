--!strict
-- TeamManager.luau (Server Module)
-- Randomizes teams, runs team color vote, tracks membership, handles spawning.

local Players           = game:GetService("Players")
local Teams             = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes    = require(ReplicatedStorage:WaitForChild("Remotes"))

local TeamManager = {}

local teamA: Team?          = nil
local teamB: Team?          = nil
local teamAPlayers: {Player} = {}
local teamBPlayers: {Player} = {}

-- Vote tracking
local voteTally: {[number]: number}  = {}
local playerVotes: {[Player]: number} = {}
local voteConn: RBXScriptConnection?  = nil

-- =====================================================
-- TEAM SETUP
-- =====================================================

function TeamManager:ClearTeams()
    if teamA then teamA:Destroy(); teamA = nil end
    if teamB then teamB:Destroy(); teamB = nil end
    teamAPlayers = {}
    teamBPlayers = {}
    if voteConn then voteConn:Disconnect(); voteConn = nil end
end

function TeamManager:AssignTeams(playerList: {Player})
    self:ClearTeams()

    -- Fisher-Yates shuffle
    local shuffled = table.clone(playerList)
    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local half = math.floor(#shuffled / 2)
    for i, p in ipairs(shuffled) do
        if i <= half then
            table.insert(teamAPlayers, p)
        else
            table.insert(teamBPlayers, p)
        end
    end

    -- Create Roblox Team instances (placeholder color until vote)
    teamA               = Instance.new("Team")
    teamA.Name          = "Team Alpha"
    teamA.AutoAssignable = false
    teamA.TeamColor     = BrickColor.new("Medium stone grey")
    teamA.Parent        = Teams

    teamB               = Instance.new("Team")
    teamB.Name          = "Team Bravo"
    teamB.AutoAssignable = false
    teamB.TeamColor     = BrickColor.new("Medium stone grey")
    teamB.Parent        = Teams

    for _, p in ipairs(teamAPlayers) do p.Team = teamA end
    for _, p in ipairs(teamBPlayers) do p.Team = teamB end

    print("[TeamManager] Assigned", #teamAPlayers, "→ Alpha |", #teamBPlayers, "→ Bravo")
end

-- =====================================================
-- COLOR VOTE
-- =====================================================

function TeamManager:StartColorVote()
    voteTally   = {}
    playerVotes = {}
    for i = 1, #GameConfig.TEAM_COLOR_OPTIONS do
        voteTally[i] = 0
    end

    Remotes.FireAll("StartTeamVote", GameConfig.TEAM_COLOR_OPTIONS)

    voteConn = Remotes.OnServer("CastTeamVote", function(player: Player, colorIndex: number)
        if typeof(colorIndex) ~= "number" then return end
        colorIndex = math.clamp(math.round(colorIndex), 1, #GameConfig.TEAM_COLOR_OPTIONS)

        if playerVotes[player] then
            voteTally[playerVotes[player]] = math.max(0, voteTally[playerVotes[player]] - 1)
        end
        playerVotes[player]    = colorIndex
        voteTally[colorIndex]  = (voteTally[colorIndex] or 0) + 1
    end)
end

function TeamManager:ResolveColorVote()
    if voteConn then voteConn:Disconnect(); voteConn = nil end

    -- Sort color indices by vote count
    local sorted = {}
    for idx, count in pairs(voteTally) do
        table.insert(sorted, { idx = idx, count = count })
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    local idxA = (sorted[1] and sorted[1].idx) or 1
    local idxB = (sorted[2] and sorted[2].idx) or 2
    if idxB == idxA then
        idxB = if idxA == 1 then 2 else 1
    end

    local cA = GameConfig.TEAM_COLOR_OPTIONS[idxA]
    local cB = GameConfig.TEAM_COLOR_OPTIONS[idxB]

    if teamA then
        teamA.TeamColor = cA.color
        for _, p in ipairs(teamAPlayers) do p.TeamColor = cA.color end
    end
    if teamB then
        teamB.TeamColor = cB.color
        for _, p in ipairs(teamBPlayers) do p.TeamColor = cB.color end
    end

    Remotes.FireAll("TeamVoteResult", cA, cB)
    print("[TeamManager] Colors resolved:", cA.name, "vs", cB.name)
end

-- =====================================================
-- SPAWNING
-- =====================================================

function TeamManager:SpawnAllPlayers()
    local spawnRoot = workspace:FindFirstChild("SpawnPoints")
    local spawnA    = spawnRoot and spawnRoot:FindFirstChild("TeamA")
    local spawnB    = spawnRoot and spawnRoot:FindFirstChild("TeamB")

    local function spawnPlayer(player: Player, spawnGroup: Instance?, index: number)
        if not player.Character then
            player:LoadCharacter()
            player.CharacterAdded:Wait()
        end
        local char = player.Character
        if not char then return end

        local spawnParts = spawnGroup and spawnGroup:GetChildren() or {}
        local part       = spawnParts[((index - 1) % math.max(1, #spawnParts)) + 1]
        if part and part:IsA("BasePart") then
            char:SetPrimaryPartCFrame(CFrame.new(part.Position + Vector3.new(0, 5, 0)))
        end
    end

    for i, p in ipairs(teamAPlayers) do
        task.spawn(spawnPlayer, p, spawnA, i)
    end
    for i, p in ipairs(teamBPlayers) do
        task.spawn(spawnPlayer, p, spawnB, i)
    end
end

-- =====================================================
-- QUERIES
-- =====================================================

function TeamManager:GetTeamInfo(teamId: string): (string, Color3)
    if teamId == "A" and teamA then
        return teamA.Name, teamA.TeamColor.Color
    elseif teamId == "B" and teamB then
        return teamB.Name, teamB.TeamColor.Color
    end
    return "Unknown", Color3.new(1, 1, 1)
end

function TeamManager:GetTeamId(player: Player): string?
    for _, p in ipairs(teamAPlayers) do
        if p == player then return "A" end
    end
    for _, p in ipairs(teamBPlayers) do
        if p == player then return "B" end
    end
    return nil
end

function TeamManager:GetTeamPlayers(teamId: string): {Player}
    return if teamId == "A" then teamAPlayers else teamBPlayers
end

function TeamManager:IsEnemy(a: Player, b: Player): boolean
    return self:GetTeamId(a) ~= self:GetTeamId(b)
end

function TeamManager:GetOpposingTeam(teamId: string): string
    return if teamId == "A" then "B" else "A"
end

return TeamManager

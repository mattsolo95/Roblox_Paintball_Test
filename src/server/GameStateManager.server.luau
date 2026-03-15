--!strict
-- GameStateManager.server.luau
-- THE central game loop. Owns state transitions and coordinates all modules.
--
-- State machine:
--   LOBBY → COUNTDOWN → TEAM_VOTE → MAP_LOADING → GAME_ACTIVE
--   → GAME_OVER → [TIEBREAKER?] → repeat until a team hits 3 wins
--   → ROUND_VICTORY → LOBBY (loop forever)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig    = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes       = require(ReplicatedStorage:WaitForChild("Remotes"))

local Mods              = script.Parent:WaitForChild("Modules")
local TeamManager       = require(Mods:WaitForChild("TeamManager"))
local ScoringManager    = require(Mods:WaitForChild("ScoringManager"))
local FlagManager       = require(Mods:WaitForChild("FlagManager"))
local PowerUpManager    = require(Mods:WaitForChild("PowerUpManager"))
local WeaponSystem      = require(Mods:WaitForChild("WeaponSystem"))
local LobbyManager      = require(Mods:WaitForChild("LobbyManager"))
local MapManager        = require(Mods:WaitForChild("MapManager"))
local TiebreakerManager = require(Mods:WaitForChild("TiebreakerManager"))

-- =====================================================
-- STATE NAMES
-- =====================================================
local State = {
    LOBBY           = "LOBBY",
    COUNTDOWN       = "COUNTDOWN",
    TEAM_VOTE       = "TEAM_VOTE",
    MAP_LOADING     = "MAP_LOADING",
    GAME_ACTIVE     = "GAME_ACTIVE",
    GAME_OVER       = "GAME_OVER",
    TIEBREAKER      = "TIEBREAKER",
    ROUND_VICTORY   = "ROUND_VICTORY",
}

-- Round-level bookkeeping
local teamAWins     = 0
local teamBWins     = 0
local currentMap    = "snow"    -- "snow" | "grass"
local currentState  = State.LOBBY

-- =====================================================
-- HELPERS
-- =====================================================

local function setState(s: string, data: { [string]: any }?)
    currentState = s
    Remotes.FireAll("GameStateChanged", s, data or {})
    print("[GSM] State →", s)
end

-- Counts down from `duration` to 0, firing TimerUpdate each second.
local function runTimer(duration: number, onTick: ((number) -> ())?): ()
    for t = duration, 0, -1 do
        Remotes.FireAll("TimerUpdate", t)
        if onTick then
            onTick(t)
        end
        if t > 0 then
            task.wait(1)
        end
    end
end

-- =====================================================
-- PHASES
-- =====================================================

-- Moves players to lobby and waits until 2+ are present and lobbyTime elapses.
local function lobbyPhase(waitSeconds: number): ()
    setState(State.LOBBY)
    task.spawn(function() LobbyManager:MovePlayersToLobby() end)  -- non-blocking

    local elapsed = 0
    print("[GSM] Lobby phase — waiting for", GameConfig.MIN_PLAYERS_TO_START, "player(s)...")
    while true do
        task.wait(1)
        if #Players:GetPlayers() < GameConfig.MIN_PLAYERS_TO_START then
            elapsed = 0
        else
            elapsed += 1
            if elapsed >= waitSeconds then break end
        end
    end
    print("[GSM] Lobby phase done.")
end

local function countdownPhase(): ()
    setState(State.COUNTDOWN)
    print("[GSM] Countdown starting...")
    task.spawn(function() LobbyManager:MovePlayersToRooftop() end)  -- non-blocking
    Remotes.FireAll("ShowCountdown", GameConfig.PREGAME_COUNTDOWN)
    runTimer(GameConfig.PREGAME_COUNTDOWN)
end

-- Map vote: players choose Snow or Grass
local function mapVotePhase(): ()
    local votes = { snow = 0, grass = 0 }
    Remotes.FireAll("MapVote", {"snow", "grass"})
    local conn = Remotes.OnServer("CastMapVote", function(_player: Player, choice: string)
        if choice == "snow" or choice == "grass" then
            votes[choice] += 1
        end
    end)
    runTimer(12)   -- 12-second map vote
    conn:Disconnect()
    currentMap = if votes.grass > votes.snow then "grass" else "snow"
    print("[GSM] Map voted:", currentMap)
end

local function teamVotePhase(): ()
    TeamManager:AssignTeams(Players:GetPlayers())
    setState(State.TEAM_VOTE)
    TeamManager:StartColorVote()
    runTimer(GameConfig.TEAM_VOTE_DURATION)
    TeamManager:ResolveColorVote()
end

local function mapLoadingPhase(): ()
    setState(State.MAP_LOADING)
    local playerCount = #Players:GetPlayers()
    print("[GSM] Loading map:", currentMap, "for", playerCount, "players")
    Remotes.FireAll("ShowLoadingScreen", currentMap)
    MapManager:ClearMap()
    MapManager:GenerateMap(currentMap, playerCount)
    task.wait(GameConfig.MAP_LOAD_DELAY)
    Remotes.FireAll("HideLoadingScreen")
    print("[GSM] Map ready.")
end

-- Returns "A", "B", or nil for a tie.
local function gamePhase(): string?
    setState(State.GAME_ACTIVE)

    ScoringManager:Reset()
    FlagManager:Initialize()
    PowerUpManager:Initialize()
    WeaponSystem:Initialize()
    TeamManager:SpawnAllPlayers()

    local scoreBroadcastTick = 0
    runTimer(GameConfig.GAME_DURATION, function(_t: number)
        local aScore, bScore = ScoringManager:GetTeamScores()
        Remotes.FireAll("ScoreUpdate", aScore, bScore, teamAWins, teamBWins)
        -- Broadcast scoreboard data every 5 seconds
        scoreBroadcastTick += 1
        if scoreBroadcastTick >= 5 then
            scoreBroadcastTick = 0
            local sbData = ScoringManager:GetScoreboardData(TeamManager)
            Remotes.FireAll("ScoreboardUpdate", sbData)
        end
        -- Notify each player of their personal points
        for _, player in ipairs(Players:GetPlayers()) do
            local allStats = ScoringManager:GetAllStats()
            local s = allStats[player]
            if s then
                Remotes.FireClient("PersonalPointsUpdate", player, s.pointsEarned)
            end
        end
    end)

    setState(State.GAME_OVER)
    FlagManager:Cleanup()
    PowerUpManager:Cleanup()
    WeaponSystem:Cleanup()

    local aScore, bScore = ScoringManager:GetTeamScores()
    if aScore > bScore then
        return "A"
    elseif bScore > aScore then
        return "B"
    end
    return nil  -- TIE
end

local function tiebreakerPhase(): string
    setState(State.TIEBREAKER)
    return TiebreakerManager:Run(ScoringManager:GetAllStats(), TeamManager)
end

local function showGameVictory(winner: string): ()
    local teamName, teamColor = TeamManager:GetTeamInfo(winner)
    Remotes.FireAll("ShowVictoryScreen", teamName, teamColor, false)
    task.wait(6)
end

local function showRoundVictory(winner: string): ()
    setState(State.ROUND_VICTORY)
    local teamName, teamColor = TeamManager:GetTeamInfo(winner)
    Remotes.FireAll("ShowVictoryScreen", teamName, teamColor, true)
    Remotes.FireAll("PlayConfetti")
    task.wait(4)

    -- Podium: top 3 skilled players on winning team
    local podiumData = ScoringManager:GetPodiumData(winner, TeamManager)
    Remotes.FireAll("ShowPodium", podiumData)
    task.wait(12)
end

-- =====================================================
-- MAIN LOOP
-- =====================================================

local function mainLoop(): ()
    while true do
        teamAWins   = 0
        teamBWins   = 0
        -- Alternate maps each round; random on first
        currentMap  = if math.random(1, 2) == 1 then "snow" else "grass"

        -- On the very first iteration lobbyWait is 0 so the game starts fast
        -- (players still need >=2 present before countdown)
        local lobbyWait = GameConfig.LOBBY_WAIT_AFTER_GAME
        lobbyPhase(lobbyWait)

        countdownPhase()
        mapVotePhase()
        teamVotePhase()
        mapLoadingPhase()

        -- Best of 5 — first to 3 wins
        while teamAWins < GameConfig.GAMES_TO_WIN_ROUND
          and teamBWins < GameConfig.GAMES_TO_WIN_ROUND do

            local winner = gamePhase()

            if winner == nil then
                winner = tiebreakerPhase()
            end

            showGameVictory(winner :: string)

            if winner == "A" then
                teamAWins += 1
            else
                teamBWins += 1
            end

            Remotes.FireAll("ScoreUpdate", 0, 0, teamAWins, teamBWins)

            -- If the round continues, briefly reset and re-spawn
            if teamAWins < GameConfig.GAMES_TO_WIN_ROUND
              and teamBWins < GameConfig.GAMES_TO_WIN_ROUND then
                task.wait(3)
                ScoringManager:Reset()
                FlagManager:ResetFlags()
                PowerUpManager:Initialize()
                TeamManager:SpawnAllPlayers()
            end
        end

        local roundWinner = if teamAWins >= GameConfig.GAMES_TO_WIN_ROUND then "A" else "B"
        showRoundVictory(roundWinner)

        MapManager:ClearMap()
        TeamManager:ClearTeams()
    end
end

-- =====================================================
-- REMOTE: GetGameState (client can query at any time)
-- =====================================================
Remotes.BindFunction("GetGameState", function(_player: Player)
    local aScore, bScore = ScoringManager:GetTeamScores()
    return {
        stateName = currentState,
        aScore    = aScore,
        bScore    = bScore,
        aWins     = teamAWins,
        bWins     = teamBWins,
        mapName   = currentMap,
    }
end)

-- =====================================================
-- STARTUP
-- =====================================================
LobbyManager:Initialize()

task.spawn(function()
    local ok, err = pcall(mainLoop)
    if not ok then
        warn("[GSM] Main loop crashed:", err)
        task.wait(5)
        task.spawn(mainLoop)
    end
end)

print("[GSM] Game loop started.")

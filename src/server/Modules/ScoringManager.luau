--!strict
-- ScoringManager.luau (Server Module)
-- Tracks per-player stats, team scores, recent damage for assists.
-- Handles the No Man's Zone score multiplier.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig        = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes           = require(ReplicatedStorage:WaitForChild("Remotes"))
local SkillCalculator   = require(ReplicatedStorage:WaitForChild("SkillCalculator"))

type PlayerStats = SkillCalculator.PlayerStats & {
    pointsEarned:   number,
    teamId:         string,
    gameStartTime:  number,
}

local ScoringManager = {}

-- { [Player]: PlayerStats }
local stats:        {[Player]: PlayerStats}         = {}
-- Team scores (sum of points from all players)
local teamScores:   {[string]: number}              = { A = 0, B = 0 }

-- Recent damage log for assist detection
-- { [damagerPlayer]: { [victimPlayer]: lastDamageTime } }
local damageLog:    {[Player]: {[Player]: number}}  = {}

-- Players currently inside No Man's Zone
local inNMZ:        {[Player]: boolean}             = {}

-- =====================================================
-- INITIALIZATION
-- =====================================================

function ScoringManager:Reset()
    stats      = {}
    teamScores = { A = 0, B = 0 }
    damageLog  = {}
    inNMZ      = {}

    -- Seed entries for all current players
    for _, player in ipairs(Players:GetPlayers()) do
        self:_initPlayer(player)
    end
end

function ScoringManager:_initPlayer(player: Player)
    if stats[player] then return end

    -- TeamId will be updated once teams are assigned
    stats[player] = {
        takedowns    = 0,
        assists      = 0,
        flagCaptures = 0,
        deaths       = 0,
        secondsPlayed = 0,
        pointsEarned = 0,
        teamId       = "",
        gameStartTime = os.clock(),
    }
end

function ScoringManager:SetTeamId(player: Player, teamId: string)
    if stats[player] then
        stats[player].teamId = teamId
    end
end

-- =====================================================
-- NO MAN'S ZONE
-- =====================================================

function ScoringManager:SetInNMZ(player: Player, value: boolean)
    inNMZ[player] = value
end

local function multiplier(player: Player): number
    return if inNMZ[player] then GameConfig.NMZ_MULTIPLIER else 1
end

-- =====================================================
-- DAMAGE LOG (for assists)
-- =====================================================

function ScoringManager:RecordDamage(damager: Player, victim: Player)
    if not damageLog[damager] then damageLog[damager] = {} end
    damageLog[damager][victim] = os.clock()
end

-- Returns all players (except the killer) who damaged victim within ASSIST_WINDOW
local function findAssisters(killer: Player, victim: Player): {Player}
    local now       = os.clock()
    local assisters = {}
    for damager, victims in pairs(damageLog) do
        if damager ~= killer and victims[victim] then
            if now - victims[victim] <= GameConfig.ASSIST_WINDOW then
                table.insert(assisters, damager)
            end
        end
    end
    -- Clear victim from everyone's log
    for _, victims in pairs(damageLog) do
        victims[victim] = nil
    end
    return assisters
end

-- =====================================================
-- SCORING EVENTS
-- =====================================================

function ScoringManager:RegisterTakedown(
    killer: Player,
    victim: Player,
    weaponName: string
)
    if not stats[killer] then self:_initPlayer(killer) end
    if not stats[victim] then self:_initPlayer(victim) end

    local mult   = multiplier(killer)
    local points = GameConfig.POINTS_TAKEDOWN * mult
    local inZone = inNMZ[killer] == true

    stats[killer].takedowns   += 1
    stats[killer].pointsEarned += points
    teamScores[stats[killer].teamId] = (teamScores[stats[killer].teamId] or 0) + points

    stats[victim].deaths += 1
    stats[victim].secondsPlayed = os.clock() - stats[victim].gameStartTime

    -- Assists
    local assisters = findAssisters(killer, victim)
    for _, assister in ipairs(assisters) do
        if not stats[assister] then self:_initPlayer(assister) end
        local aMult   = multiplier(assister)
        local aPoints = GameConfig.POINTS_ASSIST * aMult
        stats[assister].assists    += 1
        stats[assister].pointsEarned += aPoints
        teamScores[stats[assister].teamId] = (teamScores[stats[assister].teamId] or 0) + aPoints

        Remotes.FireAll("AssistEvent", assister.Name, victim.Name, aPoints)
    end

    Remotes.FireAll("TakedownEvent", killer.Name, victim.Name, points, inZone)
    Remotes.FireAll("KillFeedUpdate", killer.Name, victim.Name, weaponName)
end

function ScoringManager:RegisterFlagCapture(carrier: Player)
    if not stats[carrier] then self:_initPlayer(carrier) end

    local mult   = multiplier(carrier)
    local points = GameConfig.POINTS_FLAG_CAPTURE * mult

    stats[carrier].flagCaptures += 1
    stats[carrier].pointsEarned += points
    teamScores[stats[carrier].teamId] = (teamScores[stats[carrier].teamId] or 0) + points

    Remotes.FireAll("FlagCaptured", carrier.Name, stats[carrier].teamId, points)
end

-- =====================================================
-- QUERIES
-- =====================================================

function ScoringManager:GetTeamScores(): (number, number)
    return teamScores.A or 0, teamScores.B or 0
end

function ScoringManager:GetAllStats(): {[Player]: SkillCalculator.PlayerStats}
    local result: {[Player]: SkillCalculator.PlayerStats} = {}
    for player, s in pairs(stats) do
        result[player] = {
            takedowns    = s.takedowns,
            assists      = s.assists,
            flagCaptures = s.flagCaptures,
            deaths       = s.deaths,
            secondsPlayed = os.clock() - s.gameStartTime,
            pointsEarned = s.pointsEarned,
        }
    end
    return result
end

-- Returns top-3 players on winning team for the podium
function ScoringManager:GetPodiumData(winnerTeamId: string, teamManager: any): {{}}
    local allStats  = self:GetAllStats()
    local teamPlayers = teamManager:GetTeamPlayers(winnerTeamId)
    local top3      = SkillCalculator.TopN(allStats, teamPlayers, 3)

    local podium = {}
    for rank, entry in ipairs(top3) do
        local s = stats[entry.player]
        table.insert(podium, {
            rank         = rank,
            playerName   = entry.player.Name,
            score        = math.floor(entry.score * 10) / 10,
            takedowns    = s and s.takedowns or 0,
            assists      = s and s.assists or 0,
            flagCaptures = s and s.flagCaptures or 0,
            deaths       = s and s.deaths or 0,
        })
    end
    return podium
end

-- =====================================================
-- PLAYER LIFECYCLE
-- =====================================================

Players.PlayerAdded:Connect(function(player)
    ScoringManager:_initPlayer(player)
end)
Players.PlayerRemoving:Connect(function(player)
    stats[player]     = nil
    damageLog[player] = nil
    inNMZ[player]     = nil
end)

return ScoringManager

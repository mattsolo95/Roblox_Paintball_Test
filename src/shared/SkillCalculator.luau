--!strict
-- SkillCalculator.luau
-- Computes per-player skill scores and produces ranked lists.
--
-- Formula:
--   raw = Takedowns×3 + Assists×1 + FlagCaptures×10 - Deaths×0.5
--   skill = max(0, raw) / max(1, minutesPlayed)
--
-- High score = efficient killer who captures flags and doesn't die often.
-- Used for: tiebreaker selection, podium ordering, post-game stats.

local GameConfig = require(script.Parent.GameConfig)

local SkillCalculator = {}

export type PlayerStats = {
    takedowns:      number,
    assists:        number,
    flagCaptures:   number,
    deaths:         number,
    secondsPlayed:  number,
    pointsEarned:   number,
}

-- Returns the numeric skill score for a single player's stats
function SkillCalculator.Calculate(stats: PlayerStats): number
    local minutesPlayed = math.max(1, stats.secondsPlayed / 60)
    local raw =
        stats.takedowns     * GameConfig.SKILL_TAKEDOWN_WEIGHT
      + stats.assists       * GameConfig.SKILL_ASSIST_WEIGHT
      + stats.flagCaptures  * GameConfig.SKILL_FLAG_WEIGHT
      - stats.deaths        * GameConfig.SKILL_DEATH_PENALTY
    return math.max(0, raw / minutesPlayed)
end

-- Returns all players sorted by skill score descending.
-- playerStatsMap: { [Player]: PlayerStats }
function SkillCalculator.Rank(playerStatsMap: { [any]: PlayerStats }): { { player: any, score: number } }
    local ranked = {}
    for player, stats in pairs(playerStatsMap) do
        table.insert(ranked, {
            player = player,
            score  = SkillCalculator.Calculate(stats),
        })
    end
    table.sort(ranked, function(a, b) return a.score > b.score end)
    return ranked
end

-- Returns the single highest-skilled player from a specific subset of players.
function SkillCalculator.BestFromGroup(
    playerStatsMap: { [any]: PlayerStats },
    group: { any }
): any
    local best      = nil
    local bestScore = -math.huge
    for _, player in ipairs(group) do
        local stats = playerStatsMap[player]
        if stats then
            local score = SkillCalculator.Calculate(stats)
            if score > bestScore then
                bestScore = score
                best      = player
            end
        end
    end
    return best
end

-- Returns top N players from a group (for podium display).
function SkillCalculator.TopN(
    playerStatsMap: { [any]: PlayerStats },
    group: { any },
    n: number
): { { player: any, score: number } }
    local ranked = {}
    for _, player in ipairs(group) do
        local stats = playerStatsMap[player]
        if stats then
            table.insert(ranked, {
                player = player,
                score  = SkillCalculator.Calculate(stats),
            })
        end
    end
    table.sort(ranked, function(a, b) return a.score > b.score end)

    local result = {}
    for i = 1, math.min(n, #ranked) do
        table.insert(result, ranked[i])
    end
    return result
end

return SkillCalculator

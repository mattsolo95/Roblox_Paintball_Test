--!strict
-- TiebreakerManager.luau (Server Module)
-- When a game ends in a tie, the top-skilled player from each team
-- is placed at opposite edges of the No Man's Zone for a 1v1 duel.
-- Everyone else spectates. First to die loses for their team.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig        = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes           = require(ReplicatedStorage:WaitForChild("Remotes"))
local SkillCalculator   = require(ReplicatedStorage:WaitForChild("SkillCalculator"))

local TiebreakerManager = {}

-- =====================================================
-- MAIN ENTRY POINT
-- =====================================================

-- Returns "A" or "B" — the winning team.
function TiebreakerManager:Run(
    allStats: { [any]: SkillCalculator.PlayerStats },
    teamManager: any
): string
    local teamAPlayers = teamManager:GetTeamPlayers("A")
    local teamBPlayers = teamManager:GetTeamPlayers("B")

    local playerA = SkillCalculator.BestFromGroup(allStats, teamAPlayers)
    local playerB = SkillCalculator.BestFromGroup(allStats, teamBPlayers)

    -- Fallback if someone left mid-game
    if not playerA then
        for _, p in ipairs(teamAPlayers) do playerA = p; break end
    end
    if not playerB then
        for _, p in ipairs(teamBPlayers) do playerB = p; break end
    end

    -- If a whole team is gone, other team wins automatically
    if not playerA then return "B" end
    if not playerB then return "A" end

    Remotes.FireAll("TiebreakerStart", playerA.Name, playerB.Name)
    print("[Tiebreaker] START:", playerA.Name, "vs", playerB.Name)

    -- Position duelists at edges of NMZ
    self:_positionDuelists(playerA, playerB)

    -- Make everyone else a ghost (no collide, invisible)
    local spectators = self:_makeSpectators(playerA, playerB, Players:GetPlayers())

    -- Wait for one of them to die
    local winner = self:_waitForResult(playerA, playerB, teamManager)

    -- Restore spectators
    self:_restoreSpectators(spectators)

    print("[Tiebreaker] Winner team:", winner)
    return winner
end

-- =====================================================
-- POSITIONING
-- =====================================================

function TiebreakerManager:_positionDuelists(playerA: Player, playerB: Player)
    -- Place them just inside the NMZ on opposite sides
    local nmzBounds = workspace:FindFirstChild("NMZBounds")
    local boundA    = nmzBounds and nmzBounds:FindFirstChild("NMZBound_A")
    local boundB    = nmzBounds and nmzBounds:FindFirstChild("NMZBound_B")

    local posA = boundA
        and (boundA :: BasePart).Position + Vector3.new(0, 5, 15)
        or Vector3.new(0, 5, -50)
    local posB = boundB
        and (boundB :: BasePart).Position + Vector3.new(0, 5, -15)
        or Vector3.new(0, 5,  50)

    local function teleport(player: Player, pos: Vector3)
        if not player.Character then
            player:LoadCharacter()
            player.CharacterAdded:Wait()
        end
        local char = player.Character
        if char then
            char:SetPrimaryPartCFrame(CFrame.new(pos))
            -- Full heal
            local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if hum then
                hum.MaxHealth = GameConfig.DEFAULT_MAX_HEALTH
                hum.Health    = GameConfig.DEFAULT_MAX_HEALTH
            end
        end
    end

    teleport(playerA, posA)
    teleport(playerB, posB)
end

-- =====================================================
-- SPECTATOR MODE
-- =====================================================

type SpectatorInfo = {
    player:     Player,
    walkSpeed:  number,
    jumpPower:  number,
}

function TiebreakerManager:_makeSpectators(
    duelistA: Player,
    duelistB: Player,
    allPlayers: {Player}
): {SpectatorInfo}
    local spectators = {}
    for _, player in ipairs(allPlayers) do
        if player == duelistA or player == duelistB then continue end
        local char = player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if hum then
            table.insert(spectators, {
                player    = player,
                walkSpeed = hum.WalkSpeed,
                jumpPower = hum.JumpPower,
            })
            hum.WalkSpeed = 0
            hum.JumpPower = 0
        end
    end
    return spectators
end

function TiebreakerManager:_restoreSpectators(spectators: {SpectatorInfo})
    for _, info in ipairs(spectators) do
        local char = info.player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if hum then
            hum.WalkSpeed = info.walkSpeed
            hum.JumpPower = info.jumpPower
        end
    end
end

-- =====================================================
-- RESULT DETECTION
-- =====================================================

function TiebreakerManager:_waitForResult(
    playerA: Player,
    playerB: Player,
    teamManager: any
): string
    -- Give each duelist 1 life. First to die → their team loses.
    local resultTeam: string? = nil
    local done = Instance.new("BindableEvent")

    local function watchPlayer(player: Player)
        local char = player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not hum then
            -- Player has no character somehow — their team loses
            if resultTeam == nil then
                resultTeam = teamManager:GetOpposingTeam(teamManager:GetTeamId(player))
                done:Fire()
            end
            return
        end

        hum.Died:Connect(function()
            if resultTeam ~= nil then return end  -- already settled
            local loserTeam = teamManager:GetTeamId(player)
            resultTeam      = teamManager:GetOpposingTeam(loserTeam)
            done:Fire()
        end)
    end

    task.spawn(watchPlayer, playerA)
    task.spawn(watchPlayer, playerB)

    -- Timeout safety net (60 seconds)
    task.delay(60, function()
        if resultTeam == nil then
            resultTeam = "A"   -- arbitrary fallback
            done:Fire()
        end
    end)

    done.Event:Wait()
    done:Destroy()

    return resultTeam :: string
end

return TiebreakerManager

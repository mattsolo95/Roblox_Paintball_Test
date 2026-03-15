--!strict
-- ClientController.client.luau
-- Entry point for all client-side systems.
-- Requires and initializes every client module in the correct order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- Wait for shared modules to exist
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

-- Client modules (all in the Modules folder next to this script)
local Modules                   = script.Parent:WaitForChild("Modules")
local HUDController             = require(Modules:WaitForChild("HUDController"))
local NoManZoneClient           = require(Modules:WaitForChild("NoManZoneClient"))
local WeaponClient              = require(Modules:WaitForChild("WeaponClient"))
local LobbyUIController         = require(Modules:WaitForChild("LobbyUIController"))
local CameraController          = require(Modules:WaitForChild("CameraController"))
local ScoreboardController      = require(Modules:WaitForChild("ScoreboardController"))

local localPlayer = Players.LocalPlayer

-- =====================================================
-- INITIALIZE ALL MODULES
-- =====================================================

LobbyUIController:Initialize()
HUDController:Initialize()
NoManZoneClient:Initialize()
WeaponClient:Initialize()
CameraController:Initialize()
ScoreboardController:Initialize()

print("[ClientController] All modules initialized for", localPlayer.Name)

-- =====================================================
-- GAME STATE ROUTING
-- State changes tell each module what mode to be in.
-- =====================================================

Remotes.OnClient("GameStateChanged", function(stateName: string, _data: {})
    if stateName == "LOBBY" or stateName == "COUNTDOWN" then
        HUDController:SetVisible(false)
        LobbyUIController:SetVisible(true)
        CameraController:SetMode("LOBBY")

    elseif stateName == "TEAM_VOTE" then
        LobbyUIController:ShowVoteUI(true)

    elseif stateName == "MAP_LOADING" then
        LobbyUIController:SetVisible(false)
        -- Loading screen is handled by ShowLoadingScreen event

    elseif stateName == "GAME_ACTIVE" then
        HUDController:SetVisible(true)
        LobbyUIController:SetVisible(false)
        CameraController:SetMode("GAMEPLAY")

    elseif stateName == "TIEBREAKER" then
        CameraController:SetMode("TIEBREAKER")

    elseif stateName == "ROUND_VICTORY" then
        CameraController:SetMode("PODIUM")

    elseif stateName == "GAME_OVER" then
        HUDController:SetVisible(false)
    end
end)

-- =====================================================
-- QUERY CURRENT STATE ON JOIN (catch up if mid-game)
-- =====================================================

task.spawn(function()
    local stateData = Remotes.Invoke("GetGameState")
    if stateData then
        Remotes.FireServer("GameStateChanged")   -- no-op ping; state routing above handles it
        -- Apply immediately
        if stateData.stateName == "GAME_ACTIVE" then
            HUDController:SetVisible(true)
            CameraController:SetMode("GAMEPLAY")
        else
            LobbyUIController:SetVisible(true)
            CameraController:SetMode("LOBBY")
        end
    end
end)

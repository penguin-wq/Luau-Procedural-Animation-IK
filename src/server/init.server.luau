local Players = game:GetService("Players")
local GoalPart = game:GetService("Workspace").Target

local Shared = game:GetService("ReplicatedStorage").Shared
local Antlion = require(Shared.antlion)

local function spawnAntlion(amount)
  for i = 1, amount do
    local antlion = Antlion.new(CFrame.new(0, 10, 0))
    antlion:setTarget(GoalPart)
  end
end

local function ignoreAllPlayers()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            antlion:ignore(player.Character)
        end
    end
end

spawnAntlion(3)
ignoreAllPlayers()

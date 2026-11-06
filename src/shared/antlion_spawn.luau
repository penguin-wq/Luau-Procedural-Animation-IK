local Players = game:GetService("Players")

local target = game:GetService("Workspace").Target
local antlion = require("./antlion")

local Module = {}

function Module:start() : ()
  local count = 3
  local function __spawn(count)
    for i = 1, count do
      local __antlion = antlion.new(CFrame.new(0,10,0))
      __antlion:setTarget(target)
    end
  end

  local function __ignore_players()
      for _, player in ipairs(Players:GetPlayers()) do
          if player.Character then
              antlion:ignore(player.Character)
          end
      end
  end
end

return Module

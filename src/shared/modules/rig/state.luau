local Workspace = game:GetService("Workspace")
local config = require("../helpers/config")

local State = {}

function State:setState(nextState)
	self.state = nextState
  self.model:SetAttribute("State", nextState)
	self.stateTime = 0
	self.hitDone = false
	self.secondHitDone = false
	self.landed = false
end

function State:pouncing()
	return self.state == "Bite"
		and self.attackVariant == "maul"
		and self.stateTime >= config.MAUL_POUNCE_START
		and self.stateTime < config.MAUL_STRIKE
end

function State:pickAttackVariant()
	local r = math.random()
	if r < 0.4 then
		return "bite"
	end
	if r < 0.75 then
		return "rend"
	end
	return "maul"
end

function State:strikeTime()
	if self.attackVariant == "rend" then
		return config.REND_STRIKE
	end
	if self.attackVariant == "maul" then
		return config.MAUL_STRIKE
	end
	return config.BITE_STRIKE
end

function State:variantEndTime()
	if self.attackVariant == "rend" then
		return config.REND_TIME
	end
	if self.attackVariant == "maul" then
		return config.MAUL_TIME
	end
	return config.BITE_TIME
end

function State:resolveTarget()
	local target = self.target
	if target == nil then
		return nil
	end
	if typeof(target) == "Vector3" then
		return target
	end
	if target.Parent == nil then
		self.target = nil
		return nil
	end
	return target.Position
end

function State:syncBodyParams()
	local list = table.clone(self.rayParams.FilterDescendantsInstances)
	if self.targetModel then
		table.insert(list, self.targetModel)
	end
	self.bodyParams.FilterDescendantsInstances = list
end

function State:refreshBodyFilter()
	local target = self.target
	local model = nil
	if target ~= nil and typeof(target) ~= "Vector3" then
		model = target:FindFirstAncestorOfClass("Model")
	end
	if model == self.targetModel then
		return
	end
	self.targetModel = model
	self:syncBodyParams()
end

function State:lineOfSight(point)
	local origin = self.position + self.up
	return Workspace:Raycast(origin, (point - origin) * 0.92, self.rayParams) == nil
end

function State:dealDamage(amount, radius)
	local target = self.target
	if target == nil or typeof(target) == "Vector3" then
		return false
	end
	if (target.Position - self.position).Magnitude > radius then
		return false
	end
	local parent = target.Parent
	local humanoid = parent and parent:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	humanoid:TakeDamage(amount)
	return true
end

function State:think(targetPos, dist)
    local cfg = self.cfg
    local state = self.state

    if state == "Idle" then
        if targetPos and dist < cfg.senseRange then
            self:setState("Chase")
        end
    elseif state == "Chase" then
        if targetPos == nil or dist > cfg.loseRange then
            self:setState("Idle")
        elseif dist < cfg.biteRange and self.biteCd <= 0 then
            self.attackVariant = self:pickAttackVariant()
            self:setState("Bite")
        elseif self.leapCd <= 0
            and dist > cfg.leapMinRange
            and dist < cfg.leapMaxRange
            and self:lineOfSight(targetPos) then
            self:setState("Leap")
        elseif self:scan(targetPos, dist) then
            self:setState("Windup")
        end
    elseif state == "Bite" then
        local strikeT = self:strikeTime()
        local endT = self:variantEndTime()
        local damage = if self.attackVariant == "maul" then cfg.biteDamage * 0.8 else cfg.biteDamage
        local radius = if self.attackVariant == "rend" then cfg.biteRange + 2.5 else cfg.biteRange + 1.5

        if not self.hitDone and self.stateTime >= strikeT then
            self.hitDone = true
            self:dealDamage(damage, radius)
        end
        if self.attackVariant == "maul" and not self.secondHitDone and self.stateTime >= config.MAUL_SECOND_STRIKE then
            self.secondHitDone = true
            self:dealDamage(damage, radius)
        end
        if self.stateTime >= endT then
            self.biteCd = cfg.biteCooldown
            self:setState("Chase")
        end
    elseif state == "Windup" then
        if targetPos == nil then
            self:setState("Chase")
        elseif self.stateTime >= config.WINDUP_TIME then
            local plan = self:planLeap(targetPos, dist)
            if plan then
                self:launch(plan)
                self.leapCd = cfg.leapCooldown
                self:setState("Leap")
            else
                self.leapCd = 0.5
                self:setState("Chase")
            end
        end
    elseif state == "Recover" then
        if self.stateTime >= config.RECOVER_TIME then
            self:setState("Chase")
        end
    elseif state == "Dead" then
        if self.stateTime >= config.DEATH_TIME then
            self:destroy()
        end
    end
end

return State


local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Modules = Shared.modules

local C = require(Modules.helpers.config)

local Joints = {}

function Joints:groundPoint(hip, ideal)
	local delta = ideal - hip
	local result = Workspace:Raycast(hip, delta.Unit * (delta.Magnitude + self.cfg.castExtra), self.rayParams)
	return if result then result.Position else ideal
end

function Joints:armGround(localPoint)
	local top = self.base:PointToWorldSpace(localPoint + Vector3.new(0, 3, 0))
	local result = Workspace:Raycast(top, self.up * -12, self.rayParams)
	if result then
		return result.Position
	end
	return self.base:PointToWorldSpace(localPoint - Vector3.new(0, self.cfg.rideHeight, 0))
end

function Joints:groupBusy(group)
	for _, leg in self.legs do
		if leg.group == group and leg.stepping then
			return true
		end
	end
	return false
end

function Joints:beginStep(leg, to)
	leg.stepping = true
	leg.stepT = 0
	leg.stepFrom = leg.foot
	leg.stepTo = to
end

function Joints:plantFeet()
	self:refreshPose()
	for _, leg in self.legs do
		local hip = self.base:PointToWorldSpace(leg.hipLocal)
		local ideal = self.base:PointToWorldSpace(leg.restLocal)
		self:beginStep(leg, self:groundPoint(hip, ideal))
	end
end

function Joints:updateJoints(dt, moving)
	local cfg = self.cfg
	local state = self.state
	self:refreshPose()
	local base = self.base
	local pose = self.pose
	local blend = 1 - math.exp(-14 * dt)
	local threshold = cfg.stepThreshold * (1 + math.max(0, self.sp.crouch.x) * 1.2)
	local sf = math.clamp(self.speed / cfg.runSpeed, 0, 1)

	if state == "Idle" then
		self.fidget -= dt
		if self.fidget <= 0 then
			self.fidget = 0.5 + math.random() * 2
			local r = math.random()
			for _ = 1, 6 do
				local pick = self.legs[math.random(1, #self.legs)]
				if pick.stepping or self:groupBusy(1 - pick.group) then
					continue
				end
				local hip = base:PointToWorldSpace(pick.hipLocal)
				local ideal = base:PointToWorldSpace(pick.restLocal)

				local target
				if r < 0.5 then
					local jitter = Vector3.new((math.random() - 0.5) * 1.6, 0, (math.random() - 0.5) * 1.6)
					target = self:groundPoint(hip, ideal + jitter)
				elseif r < 0.85 then
					local ang = math.random() * math.pi * 2
					local dist = 0.6 + math.random() * 1.2
					local offset = Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
					target = self:groundPoint(hip, ideal + offset)
				else
					local jitter = Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3)
					target = self:groundPoint(hip, ideal + jitter)
				end
				self:beginStep(pick, target)
				break
			end
		end
	end

	local stepDuration = if state == "Chase" then cfg.stepDuration * 0.75 else cfg.stepDuration
	local speedLift = if state == "Chase" then 1.2 + sf * 0.4 else 0.85

	local variant = self.attackVariant
	local strikeT = self:strikeTime()
	local endT = self:variantEndTime()
	local biteStrike = state == "Bite" and self.stateTime >= strikeT
	local bitePost = 0
	if biteStrike then
		bitePost = math.clamp((self.stateTime - strikeT) / math.max(endT - strikeT, 0.001), 0, 1)
	end

	if state == "Bite" and variant == "maul" and biteStrike and not self.landed then
		self.landed = true
		for _, leg in self.legs do
			if leg.row ~= -1 then
				local hip = base:PointToWorldSpace(leg.hipLocal)
				local ideal = base:PointToWorldSpace(leg.restLocal)
				self:beginStep(leg, self:groundPoint(hip, ideal))
			end
		end
	end

	local pouncing = self:pouncing()

	for i, leg in self.legs do
		if state == "Leap" or self.falling then
			leg.stepping = false
			leg.lift = 0
			leg.foot = leg.foot:Lerp(pose:PointToWorldSpace(leg.hipLocal + leg.airLocal), blend)
		elseif state == "Dead" then
			leg.stepping = false
			leg.lift = 0
			local decay = math.max(0, 1 - self.stateTime / 4)
			local twitch = Vector3.new(
				math.sin(self.clock * 9 + (i - 1) * 1.7),
				0,
				math.cos(self.clock * 7 + (i - 1) * 2.3)
			) * (0.35 * decay)
			local curl = pose:PointToWorldSpace(leg.hipLocal)
				+ self.up * 2.6
				+ pose:VectorToWorldSpace(leg.outward) * 0.6
				+ twitch
			leg.foot = leg.foot:Lerp(curl, blend)
		elseif pouncing and leg.row ~= -1 then
			leg.stepping = false
			leg.lift = 0
			leg.foot = leg.foot:Lerp(pose:PointToWorldSpace(leg.hipLocal + leg.airLocal), blend)
		elseif state == "Bite" and leg.row == -1 and variant ~= "bite" then
			leg.stepping = false
			leg.lift = 0
			leg.arm = true

			local reachedWorld
			local rate = math.min(1, blend * 1.8)

			if variant == "rend" then
				local swipe = if biteStrike then math.sin(bitePost * math.pi) * 2.5 * leg.side else 0
				reachedWorld = base:PointToWorldSpace(leg.hipLocal + Vector3.new(leg.side * 0.5 + swipe, 1.6, -3.5))
			elseif self.stateTime < C.MAUL_POUNCE_START then
				reachedWorld = base:PointToWorldSpace(leg.hipLocal + Vector3.new(leg.side * 0.9, 1.6, -1.8))
			elseif not biteStrike then
				reachedWorld = base:PointToWorldSpace(leg.hipLocal + Vector3.new(leg.side * 1.5, 1.4, -4.6))
				rate = math.min(1, blend * 3)
			else
				local alt = if leg.side > 0 then 0 else math.pi
				local raise = math.max(0, math.sin(bitePost * math.pi * 5 + alt)) * 1.2 * (1 - bitePost * 0.5)
				local stompLocal = leg.hipLocal + Vector3.new(-leg.side * 0.2, 0, -3.2 + bitePost)
				reachedWorld = self:armGround(stompLocal) + self.up * raise
				rate = math.min(1, blend * 3.5)
			end

			leg.foot = leg.foot:Lerp(reachedWorld, rate)
		else
			local hip = base:PointToWorldSpace(leg.hipLocal)
			local ideal = base:PointToWorldSpace(leg.restLocal)
			leg.drift = (leg.foot - self:groundPoint(hip, ideal)).Magnitude

			if leg.stepping then
				leg.stepT = math.min(leg.stepT + dt / stepDuration, 1)
				local t = leg.stepT
				leg.foot = leg.stepFrom:Lerp(leg.stepTo, t * t * (3 - 2 * t))
				leg.lift = math.sin(t * math.pi) * cfg.stepHeight * speedLift
				if t >= 1 then
					leg.stepping = false
					leg.lift = 0
					leg.arm = false
				end
			elseif state ~= "Windup" and leg.drift > threshold and not self:groupBusy(1 - leg.group) then
				local lead = if moving then self.forward * (self.speed * stepDuration) else Vector3.zero
				self:beginStep(leg, self:groundPoint(hip, ideal + lead))
			end
		end
	end
end

function Joints:fitBody(dt)
	local cfg = self.cfg
	if self.state == "Leap" or self.state == "Dead" or self.falling then
		return
	end

	local maulBite = self.state == "Bite" and self.attackVariant == "maul"
	local front, back, left, right, center = Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero

	for _, leg in self.legs do
		local foot = leg.foot
		if leg.arm or maulBite then
			local hip = self.base:PointToWorldSpace(leg.hipLocal)
			local ideal = self.base:PointToWorldSpace(leg.restLocal)
			foot = self:groundPoint(hip, ideal)
		end
		center += foot
		if leg.row == -1 then
			front += foot
		end
		if leg.row == 1 then
			back += foot
		end
		if leg.side == -1 then
			left += foot
		else
			right += foot
		end
	end
	center /= #self.legs

	local fitUp = (right - left):Cross(front - back)
	if fitUp.Magnitude > 0.001 then
		self.up = self.up:Lerp(fitUp.Unit, 1 - math.exp(-10 * dt)).Unit
		self.forward = (self.forward - self.up * self.forward:Dot(self.up)).Unit
	end

	local ride = cfg.rideHeight * (1 - self.sp.crouch.x * 0.45) + self.bob + self.hop
	local follow = if maulBite then 30 else 14
	local desired = center + self.up * ride
	local offset = self.up * (desired - self.position):Dot(self.up)
	self.position += offset * (1 - math.exp(-follow * dt))
end

return Joints


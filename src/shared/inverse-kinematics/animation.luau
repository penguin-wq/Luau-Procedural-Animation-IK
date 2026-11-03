local shared = game:GetService("ReplicatedStorage").Shared
local modules = shared.inverse-kinematics
local cfg = require(modules.helpers.config)
local util = require(modules.helpers.util)

local sin = math.sin
local pi = math.pi
local spring = util.spring

local Animation = {}

function Animation:animate(dt, targetPos)
	local cfg = self.cfg
	local sp = self.sp
	local state = self.state
	local dead = state == "Dead"
	local sf = math.clamp(self.speed / cfg.runSpeed, 0, 1)
	local hasTarget = targetPos ~= nil
	local idling = state == "Idle"
	local clock = self.clock
	local seed = self.seed

	local strikeT = self:strikeTime()
	local endT = self:variantEndTime()
	local strike = state == "Bite" and self.stateTime >= strikeT
	local postStrike = 0
	if strike then
		postStrike = math.clamp((self.stateTime - strikeT) / math.max(endT - strikeT, 0.001), 0, 1)
	end
	local variant = self.attackVariant
	local maul = state == "Bite" and variant == "maul"
	local coil = maul and self.stateTime < cfg.MAUL_POUNCE_START
	local air = maul and not strike and not coil

	self.breathPhase += dt * (2 + sf * 5)
	local breath = sin(self.breathPhase)
	local breathSlow = sin(self.breathPhase * 0.5 + seed)

	self.gaitPhase += dt * (4.5 + sf * 22)
	local gaitVert = sin(self.gaitPhase * 2)
	local gaitSide = sin(self.gaitPhase)
	local gaitFast = sin(self.gaitPhase * 4)

	self.headScanTimer -= dt
	if self.headScanTimer <= 0 then
		self.headScanTimer = 0.4 + math.random() * 2.2
		self.headScanYaw = (math.random() - 0.5) * 1.8
		self.headScanPitch = (math.random() - 0.5) * 0.55 - 0.05
	end

	self.twitchTimer -= dt
	self.twitchAmount = math.max(0, self.twitchAmount - dt * 4)
	if self.twitchTimer <= 0 then
		self.twitchTimer = 0.8 + math.random() * 3.5
		if math.random() < 0.55 then
			self.twitchAmount = 0.4 + math.random() * 0.6
		end
	end

	local liftL = 0
	local liftR = 0
	for _, leg in self.legs do
		if leg.side < 0 then
			liftL += leg.lift
		else
			liftR += leg.lift
		end
	end

	self.bob = -(liftL + liftR) * 0.05
		+ breath * 0.04 * (1 - sf)
		+ (if state == "Chase" then gaitVert * 0.09 * sf else 0)

	local pitchGoal = 0
	if state == "Windup" then
		pitchGoal = 0.22
	elseif state == "Chase" then
		pitchGoal = -0.09 * sf + gaitVert * 0.05 * sf - 0.03
	elseif state == "Bite" then
		if maul then
			if coil then
				pitchGoal = 0.4
			elseif air then
				pitchGoal = -0.14
			else
				pitchGoal = -0.1 + sin(postStrike * pi * 6) * 0.07 * (1 - postStrike)
			end
		elseif not strike then
			pitchGoal = 0.18
		else
			pitchGoal = 0.12
		end
	elseif state == "Recover" then
		pitchGoal = 0.04
	elseif state == "Leap" then
		pitchGoal = -0.18 + sin(clock * 8) * 0.05
	elseif idling then
		pitchGoal = breathSlow * 0.025 + sin(clock * 1.3 + seed) * 0.015
		if hasTarget then
			pitchGoal -= 0.055
		end
	end

	local lean = math.clamp(self.turnRate * 0.035, -0.35, 0.35)
	local rollGoal = lean + (liftL - liftR) * 0.05
	if dead then
		rollGoal = pi
	elseif state == "Chase" then
		rollGoal += gaitSide * 0.055 * sf
	elseif state == "Bite" and strike then
		rollGoal += sin(postStrike * pi * 4) * (if variant == "maul" then 0.16 else 0.05)
	elseif state == "Leap" then
		rollGoal += sin(clock * 11) * 0.06
	elseif idling then
		rollGoal += sin(clock * 0.8 + seed * 1.7) * 0.02
		if hasTarget then
			rollGoal *= 0.5
		end
	end

	local idleYawNoise = sin(clock * 0.55 + seed) * 0.35
		+ sin(clock * 1.7 + seed * 2.3) * 0.16
		+ sin(clock * 3.9 + seed * 4.1) * 0.06
	local idlePitchNoise = sin(clock * 0.8 + seed * 1.3) * 0.1 + sin(clock * 2.3 + seed * 2.7) * 0.045

	local scanWeight = if idling and not hasTarget then 1 else 0.35
	local headYawGoal = idleYawNoise + self.headScanYaw * scanWeight
	local headPitchGoal = idlePitchNoise - 0.06 + self.headScanPitch * scanWeight
	local headRollGoal = sin(clock * 0.9 + seed * 2.1) * 0.06

	local aimYaw = 0
	local aimPitch = 0
	if hasTarget then
		local rel = self.pose:PointToObjectSpace(targetPos) - Vector3.new(0, 0.1, -cfg.bodyLength * 0.5)
		aimYaw = math.clamp(math.atan2(-rel.X, -rel.Z), -1.1, 1.1)
		aimPitch = math.clamp(math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), -0.5, 0.6)
	end

	if dead then
		headYawGoal = 0
		headPitchGoal = -0.7
		headRollGoal = 0.3
	elseif hasTarget and not idling then
		headYawGoal = aimYaw
		headPitchGoal = aimPitch
		if state == "Chase" then
			headPitchGoal += gaitVert * 0.08 * sf
			headRollGoal += gaitSide * 0.06 * sf
		elseif state == "Leap" then
			headPitchGoal += sin(clock * 9) * 0.06
			headRollGoal += sin(clock * 7) * 0.08
		elseif state == "Bite" then
			if not strike then
				if air then
					headPitchGoal -= 0.12
					headYawGoal *= 0.7
				else
					headPitchGoal += if variant == "maul" then 0.32 else 0.22
					headYawGoal *= 0.35
				end
			elseif variant == "maul" then
				local env = 1 - postStrike
				headYawGoal += sin(postStrike * pi * 8) * 0.5 * env
				headRollGoal += sin(postStrike * pi * 5) * 0.22 * env
				headPitchGoal += sin(postStrike * pi * 8 + 1.2) * 0.14 * env - 0.12
			elseif variant == "rend" then
				local env = 1 - postStrike
				headPitchGoal += 0.2 * env
				headYawGoal += sin(postStrike * pi * 2) * 0.18 * env
			else
				headPitchGoal += 0.15 * (1 - postStrike)
			end
		end
	elseif hasTarget and idling then
		headYawGoal = aimYaw + idleYawNoise * 0.15
		headPitchGoal = aimPitch + idlePitchNoise * 0.25 - 0.05
		headRollGoal = sin(clock * 1.8 + seed) * 0.08
	end

	local idleJawPulse = 0.1
		+ 0.09 * math.max(0, sin(clock * 1.8 + seed) * sin(clock * 0.6 + seed * 2))
		+ 0.04 * sin(clock * 9 + seed * 3)
		+ self.twitchAmount * 0.15
	local jawGoal = idleJawPulse
	local jawStiff = 200
	local jawDamp = 16

	if dead then
		jawGoal = 0.8
	elseif state == "Chase" then
		local snapRate = 12 + sf * 8
		local snap = math.max(0, sin(clock * snapRate + seed * 3) * sin(clock * 3.4 + seed))
		jawGoal = 0.22 + 0.28 * snap + self.twitchAmount * 0.2
	elseif state == "Windup" then
		jawGoal = 1
	elseif state == "Leap" then
		jawGoal = if self.hitDone then 0.15 else 1
	elseif state == "Bite" then
		if not strike then
			jawGoal = 1
		elseif variant == "maul" then
			jawGoal = math.abs(sin(postStrike * pi * 6)) * 0.85
			jawStiff = 800
			jawDamp = 30
		else
			jawGoal = 0
			jawStiff = 600
			jawDamp = 30
		end
	elseif state == "Recover" then
		jawGoal = 0.2 + 0.1 * sin(clock * 5)
	elseif idling and hasTarget then
		jawGoal = idleJawPulse + 0.22
	end

	local wingGoal = 0
	if dead then
		wingGoal = 0.5
	elseif state == "Chase" then
		wingGoal = 0.3 + 0.2 * sf + math.max(0, gaitFast * 0.1 * sf)
	elseif state == "Windup" then
		wingGoal = 0.9
	elseif state == "Leap" then
		wingGoal = 1
	elseif state == "Bite" then
		if variant == "bite" then
			wingGoal = 0.4
		elseif variant == "rend" then
			wingGoal = if strike then 0.55 else 0.6
		elseif strike then
			wingGoal = 0.65 + sin(clock * 40) * 0.1
		elseif air then
			wingGoal = 1
		else
			wingGoal = 0.85
		end
	elseif state == "Recover" then
		wingGoal = 0.15
	elseif idling then
		local flick = math.max(0, sin(clock * 0.5 + seed * 4) * sin(clock * 4.5 + seed))
		wingGoal = 0.02 + flick * 0.18 + self.twitchAmount * 0.12
	end

	local abPitchGoal = 0.25 + breath * 0.05 + sin(clock * (1.5 + 5 * sf) + seed) * 0.03
	if dead then
		abPitchGoal = 0.4
	elseif state == "Windup" then
		abPitchGoal = -0.35
	elseif state == "Leap" then
		abPitchGoal = 0.15 + sin(clock * 6) * 0.08
	elseif state == "Chase" then
		abPitchGoal = 0.15 + gaitVert * 0.06 * sf
	elseif state == "Bite" then
		if not strike then
			abPitchGoal = if coil then -0.45 elseif air then 0.05 else -0.15
		elseif variant == "maul" then
			abPitchGoal = 0.3 + sin(postStrike * pi * 4) * 0.1 * (1 - postStrike)
		else
			abPitchGoal = 0.25
		end
	elseif idling and hasTarget then
		abPitchGoal = 0.35 + breath * 0.04
	end
	local abYawGoal = math.clamp(self.turnRate * 0.06, -0.5, 0.5)
		+ sin(clock * 1.2 + seed) * 0.05 * (if idling then 1 else 0.5)

	local lungeGoal = 0
	if state == "Bite" then
		if not strike then
			lungeGoal = if coil then -0.4 elseif air then 1.1 elseif variant == "rend" then -0.3 else -0.2
		elseif variant == "rend" then
			lungeGoal = 1.3
		else
			lungeGoal = 1
		end
	end

	local crouchGoal = 0
	if state == "Windup" then
		crouchGoal = 1
	elseif state == "Bite" then
		if variant == "maul" then
			crouchGoal = if coil then 1 elseif air then 0 else 0.8
		elseif variant == "rend" then
			crouchGoal = if strike then 0.4 else 0.9
		else
			crouchGoal = if strike then 0.5 else 1
		end
	elseif idling then
		crouchGoal = 0
	else
		crouchGoal = 0.1 * sf
	end

	local hopGoal = 0
	if air then
		local t = (self.stateTime - cfg.MAUL_POUNCE_START) / (cfg.MAUL_STRIKE - cfg.MAUL_POUNCE_START)
		hopGoal = sin(t * pi) * cfg.MAUL_HOP_HEIGHT
	end
	self.hop += (hopGoal - self.hop) * (1 - math.exp(-30 * dt))

	local soft = idling
	local crouchStiff = if maul then 220 elseif state == "Bite" then 120 else 70
	local lungeStiff = if strike then 500 elseif air then 260 else 110
	local lungeDamp = if strike then 30 elseif air then 22 else 13

	spring(sp.pitch, pitchGoal, if soft then 55 else 90, if soft then 9 else 12, dt)
	spring(sp.roll, rollGoal, if dead then 30 else 90, if dead then 5 else 12, dt)
	spring(sp.crouch, crouchGoal, crouchStiff, if maul then 24 else 11, dt)
	spring(sp.headYaw, headYawGoal, if soft then 40 else 80, if soft then 7 else 12, dt)
	spring(sp.headPitch, headPitchGoal, if soft then 40 else 80, if soft then 7 else 12, dt)
	spring(sp.headRoll, headRollGoal, if soft then 45 else 70, if soft then 8 else 11, dt)
	spring(sp.lunge, lungeGoal, lungeStiff, lungeDamp, dt)
	spring(sp.jaw, jawGoal, jawStiff, jawDamp, dt)
	spring(sp.wing, wingGoal, 85, 8.5, dt)
	spring(sp.abYaw, abYawGoal, 50, 6, dt)
	spring(sp.abPitch, abPitchGoal, 55, 7, dt)
end

return Animation


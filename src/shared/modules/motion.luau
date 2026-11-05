local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Modules = Shared.modules

local C = require(Modules.helpers.config)

local Motion = {}

function Motion:refreshPose()
	self.base = CFrame.lookAt(self.position, self.position + self.forward, self.up)
	self.pose = self.base * CFrame.Angles(self.sp.pitch.x, 0, self.sp.roll.x)
end

function Motion:launch(aim)
	local delta = aim - self.position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local dir = if flat.Magnitude > 0.01 then flat.Unit else self.forward
	local dist = flat.Magnitude + 1.5
	local flight = C.LEAP_FLIGHT_TIME
	local gEff = Workspace.Gravity * C.LEAP_GRAVITY_SCALE
	local vertical = (delta.Y + 0.5 * gEff * flight * flight) / flight
	self.velocity = dir * (dist / flight) + Vector3.new(0, vertical, 0)
end

function Motion:steer(dt, targetPos, planar)
	local cfg = self.cfg
	local state = self.state
	local facing = state == "Chase" or state == "Windup" or state == "Bite"
	local moving = false
  local turn = 0

  if facing and targetPos and planar.Magnitude > 0.05 then
		local desired = planar.Unit
		local angle = math.atan2(self.up:Dot(self.forward:Cross(desired)), self.forward:Dot(desired))
		local rate = (if state == "Chase" then 1 else 1.6) * cfg.turnSpeed * dt
		turn = math.clamp(angle, -rate, rate)
		self.forward = CFrame.fromAxisAngle(self.up, turn):VectorToWorldSpace(self.forward)
		moving = state == "Chase"
			and not self.falling
			and planar.Magnitude > cfg.stopDistance
			and math.abs(angle - turn) < math.rad(70)
	end

	self.turnRate += (turn / dt - self.turnRate) * (1 - math.exp(-8 * dt))

	local worst = 0
	for _, leg in self.legs do
		if not leg.stepping then
			worst = math.max(worst, leg.drift)
		end
	end
	local limit = cfg.stepThreshold * 1.6
	local legScale = math.clamp(1 - (worst - limit) / limit, 0.25, 1)
	local goal = if moving then cfg.runSpeed * legScale else 0
	self.speed += (goal - self.speed) * (1 - math.exp(-7 * dt))
	if state ~= "Leap" and state ~= "Dead" then
		self.position += self.forward * (self.speed * dt)
	end

	if self:pouncing() and targetPos then
		local gap = planar:Dot(self.forward) - C.MAUL_POUNCE_GAP
		if gap > 0 then
			local pounceSpeed = math.min(gap / math.max(C.MAUL_STRIKE - self.stateTime, dt), C.MAUL_POUNCE_SPEED)
			self.position += self.forward * (pounceSpeed * dt)
		end
	end

	return moving
end

function Motion:fly(dt)
	local cfg = self.cfg
	local gEff = Workspace.Gravity * C.LEAP_GRAVITY_SCALE
	self.velocity -= Vector3.new(0, gEff * dt, 0)
	if not self.hitDone and self:dealDamage(cfg.leapDamage, cfg.leapHitRadius) then
		self.hitDone = true
	end

	local stepVec = self.velocity * dt
	local hit = Workspace:Raycast(
		self.position,
		stepVec + self.velocity.Unit * (cfg.rideHeight * 1.2),
		self.rayParams
	)

	local groundNormal = if hit and hit.Normal.Y >= 0.5 then hit.Normal else nil
	local grounded = groundNormal ~= nil and self.stateTime > 0.1
	if not grounded and self.stateTime >= C.LEAP_FLIGHT_TIME then
		local below = Vector3.new(0, -(cfg.rideHeight + cfg.castExtra), 0)
		local lower = Workspace:Raycast(self.position, below, self.rayParams)
		if lower then
			grounded = true
			groundNormal = if lower.Normal.Y >= 0.5 then lower.Normal else Vector3.yAxis
		end
	end

	if grounded then
		self.up = groundNormal or Vector3.yAxis
		local flat = self.forward - self.up * self.forward:Dot(self.up)
		self.forward = if flat.Magnitude > 0.01 then flat.Unit else self.up:Cross(Vector3.xAxis).Unit
		self.velocity = Vector3.zero
		self.speed = 0
		self.sp.crouch.x = 0.8
		self.sp.crouch.v = 0
		self.sp.pitch.v = -3
		self:plantFeet()
		self:setState("Recover")
		return
	end

	self.position += stepVec

	local flatVelocity = Vector3.new(self.velocity.X, 0, self.velocity.Z)
	if flatVelocity.Magnitude > 0.1 then
		self.forward = self.forward:Lerp(flatVelocity.Unit, 1 - math.exp(-8 * dt))
	end
	self.up = self.up:Lerp(Vector3.yAxis, 1 - math.exp(-6 * dt)).Unit
	local flatForward = self.forward - self.up * self.forward:Dot(self.up)
	self.forward = if flatForward.Magnitude > 0.01 then flatForward.Unit else self.up:Cross(Vector3.xAxis).Unit
end

function Motion:fall(dt)
	local cfg = self.cfg
	local hit = Workspace:Raycast(self.position, self.up * -(cfg.rideHeight + 4), self.rayParams)
	if hit then
		self.velocity = Vector3.zero
		self.position = self.position:Lerp(hit.Position + hit.Normal * 1.1, 1 - math.exp(-10 * dt))
	else
		self.velocity -= Vector3.new(0, Workspace.Gravity * dt, 0)
		self.position += self.velocity * dt
	end
end

function Motion:gravity(dt)
	local cfg = self.cfg
	if self.state == "Leap" or self.state == "Dead" then
		self.falling = false
		self.fallSpeed = 0
		self.airTime = 0
		return
	end

	if not self.falling then
		local reach = cfg.rideHeight + cfg.castExtra
		local below = Workspace:Raycast(self.position, Vector3.new(0, -reach, 0), self.bodyParams)
		if below then
			self.airTime = 0
			return
		end
		self.airTime += dt
		if self.airTime < 0.1 then
			return
		end
		self.falling = true
		self.fallSpeed = 0
	end

	self.fallSpeed = math.min(self.fallSpeed + Workspace.Gravity * dt, 200)
	local drop = self.fallSpeed * dt
	local hit = Workspace:Raycast(self.position, Vector3.new(0, -(cfg.rideHeight + drop), 0), self.bodyParams)

	if hit then
		self.position = hit.Position + hit.Normal * cfg.rideHeight
		self.up = if hit.Normal.Y >= 0.5 then hit.Normal else Vector3.yAxis
		local flat = self.forward - self.up * self.forward:Dot(self.up)
		self.forward = if flat.Magnitude > 0.01 then flat.Unit else self.up:Cross(Vector3.xAxis).Unit
		self.sp.crouch.x = math.clamp(self.fallSpeed / 60, 0.15, 0.9)
		self.sp.crouch.v = 0
		self.sp.pitch.v = -2
		self.falling = false
		self.fallSpeed = 0
		self.airTime = 0
		self:plantFeet()
		return
	end

	self.position -= Vector3.new(0, drop, 0)
	self.up = self.up:Lerp(Vector3.yAxis, 1 - math.exp(-6 * dt)).Unit
	local flatForward = self.forward - self.up * self.forward:Dot(self.up)
	self.forward = if flatForward.Magnitude > 0.01 then flatForward.Unit else self.up:Cross(Vector3.xAxis).Unit
end

function Motion:separate(dt)
	if self.state == "Dead" or self.state == "Leap" then
		return
	end
	local radius = self.cfg.separation or 5.5
	local push = Vector3.zero
	for other in self.swarm do
		if other == self or other.state == "Dead" or other.state == "Leap" then
			continue
		end
		local offset = self.position - other.position
		local flat = offset - self.up * offset:Dot(self.up)
		local dist = flat.Magnitude
		if dist < radius then
			local away = if dist > 0.05 then flat / dist else Vector3.new(math.cos(self.seed), 0, math.sin(self.seed))
			push += away * ((radius - dist) * 0.5)
		end
	end
	if push.Magnitude > radius then
		push = push.Unit * radius
	end
	if push.Magnitude > 0.001 then
		self.position += push * math.min(1, 10 * dt)
	end
end

function Motion:separate(dt)
	if self.state == "Dead" or self.state == "Leap" then
		return
	end
	local radius = self.cfg.separation or 5.5
	local push = Vector3.zero
	for other in self.swarm do
		if other == self or other.state == "Dead" or other.state == "Leap" then
			continue
		end
		local offset = self.position - other.position
		local flat = offset - self.up * offset:Dot(self.up)
		local dist = flat.Magnitude
		if dist < radius then
			local away = if dist > 0.05 then flat / dist else Vector3.new(math.cos(self.seed), 0, math.sin(self.seed))
			push += away * ((radius - dist) * 0.5)
		end
	end
	if push.Magnitude > radius then
		push = push.Unit * radius
	end
	if push.Magnitude > 0.001 then
		self.position += push * math.min(1, 10 * dt)
	end
end

function Motion:collide()
	if self.state == "Dead" then
		return
	end
	self:refreshPose()
	local base = self.base
	local origin = self.position + self.up * 0.3

	local push = Vector3.zero
	local hits = 0
	for _, probe in C.WALL_PROBES do
		local dir, radius = probe[1], probe[2]
		local world = base:VectorToWorldSpace(dir)
		local hit = Workspace:Raycast(origin, world * radius, self.bodyParams)
		if hit == nil or hit.Normal:Dot(self.up) > 0.6 then
			continue
		end
		local flat = hit.Normal - self.up * hit.Normal:Dot(self.up)
		if flat.Magnitude < 0.05 then
			continue
		end
		local away = flat.Unit
		push += away * ((radius - hit.Distance) * math.abs(world:Dot(away)))
		hits += 1
	end

	if hits > 0 then
		push /= hits
		if push.Magnitude > 2 then
			push = push.Unit * 2
		end
		if push.Magnitude > 0.001 then
			self.position += push
			if self.state == "Leap" then
				local into = self.velocity:Dot(push.Unit)
				if into < 0 then
					self.velocity -= push.Unit * into
				end
			end
		end
	end

	local roof = Workspace:Raycast(self.position, self.up * 1.4, self.bodyParams)
	if roof then
		self.position -= self.up * (1.4 - roof.Distance)
		if self.state == "Leap" and self.velocity.Y > 0 then
			self.velocity = Vector3.new(self.velocity.X, 0, self.velocity.Z)
		end
	end

	local lift = 0
	for _, probe in C.GROUND_PROBES do
		local z, need = probe[1], probe[2]
		local point = base:PointToWorldSpace(Vector3.new(0, 0, z))
		local hit = Workspace:Raycast(point, self.up * -6, self.bodyParams)
		if hit then
			lift = math.max(lift, need - hit.Distance)
		end
	end
	if lift > 0 then
		self.position += self.up * lift
	end
end

return Motion


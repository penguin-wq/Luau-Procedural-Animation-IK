local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Modules = Shared.modules

local C = require(Modules.helpers.config)

local SCAN_INTERVAL = 0.3 -- seconds between planner refreshes
local TARGET_PROBE = 5 -- how far below the target to look for the surface it stands on
local OBSTACLE_MEDIUM = 4 -- rise (studs) at which the target's surface counts as an obstacle
local OBSTACLE_RANGE = 24 -- max flat distance for an obstacle launch
local OBSTACLE_CLEARANCES = { 3, 6, 9, 12 } -- apex heights above the perch, lowest tried first
local OBSTACLE_GRAVITY_SCALE = 1.4
local FLY_ARC = 0.22 -- arc rise per stud of distance
local FLY_MIN_ARC = 4
local FLY_LEAD = 0.8 -- share of the target's motion to lead
local FLY_GRAVITY_MIN = 0.3 -- gravity scale limits for the glide
local FLY_GRAVITY_MAX = 2
local ARC_SAMPLES = 8
local PATH_INTERVAL = 1 -- seconds between route requests
local WAYPOINT_REACH = 3 -- planar distance that counts as reaching a waypoint
local PATH_AGENT = {
	AgentRadius = 3.5,
	AgentHeight = 5,
	AgentCanJump = false,
	AgentCanClimb = false,
	WaypointSpacing = 6,
}

local Nav = {}

-- Launch velocity and flight time for a leap that peaks `apex` studs above `from`, then drops onto `aim`.
local function apexLaunch(from, aim, gravity, apex)
	local delta = aim - from
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local climb = math.sqrt(2 * gravity * apex)
	-- Time up to the apex plus time falling from the apex to the aim's height
	local time = climb / gravity + math.sqrt(2 * math.max(apex - delta.Y, 0.01) / gravity)
	local dir = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zero
	return dir * (flat.Magnitude / time) + Vector3.new(0, climb, 0), time
end

-- Planar velocity of the target, used to lead long flights.
function Nav:targetVelocity()
	local target = self.target
	if target == nil or typeof(target) == "Vector3" then
		return Vector3.zero
	end
	local v = target.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z)
end

-- Height of the surface under the target relative to the ground under the antlion.
-- Returns 0 and nil when the target is airborne, so jumping players never trigger a launch.
function Nav:targetRise(targetPos)
	local hit = Workspace:Raycast(targetPos, Vector3.new(0, -TARGET_PROBE, 0), self.bodyParams)
	if hit == nil then
		return 0, nil
	end
	return hit.Position.Y - (self.position.Y - self.cfg.rideHeight), hit.Position
end

-- Samples the flight path and returns true when nothing solid blocks it before landing.
function Nav:arcClear(plan)
	local from = self.position
	local last = from
	for i = 1, ARC_SAMPLES do
		local t = plan.time * i / ARC_SAMPLES
		local point = from + plan.velocity * t - Vector3.new(0, 0.5 * plan.gravity * t * t, 0)
		local hit = Workspace:Raycast(last, point - last, self.bodyParams)
		-- Touching a floor in the last segments is the landing, not a blockage
		if hit and not (i >= ARC_SAMPLES - 1 and hit.Normal.Y >= 0.5) then
			return false
		end
		last = point
	end
	return true
end

-- Short-range leap: fast, fixed-time hop straight at the target.
function Nav:solveGround(targetPos)
	local time = C.LEAP_FLIGHT_TIME
	local gravity = Workspace.Gravity * C.LEAP_GRAVITY_SCALE
	local delta = targetPos - self.position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local dir = if flat.Magnitude > 0.01 then flat.Unit else self.forward
	local climb = (delta.Y + 0.5 * gravity * time * time) / time
	local velocity = dir * ((flat.Magnitude + 1.5) / time) + Vector3.new(0, climb, 0)

	local plan = { velocity = velocity, gravity = gravity, time = time, kind = "ground" }
	if not self:arcClear(plan) then
		return nil, "blocked"
	end
	return plan
end

-- Long-range leap-and-fly: a high, floaty arc that covers the distance at leapSpeed and leads a moving target.
function Nav:solveFly(targetPos)
	local cfg = self.cfg
	local from = self.position

	-- Lead the target by the estimated flight time, then overshoot slightly like the ground leap
	local flat0 = Vector3.new(targetPos.X - from.X, 0, targetPos.Z - from.Z).Magnitude
	local aim = targetPos + self:targetVelocity() * ((flat0 + 1.5) / cfg.leapSpeed * FLY_LEAD)
	local toAim = aim - from
	local flatDir = Vector3.new(toAim.X, 0, toAim.Z)
	aim += (if flatDir.Magnitude > 0.01 then flatDir.Unit else self.forward) * 1.5

	local delta = aim - from
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude

	-- Arc height grows with distance but never passes the launch limit
	local rise = math.clamp(flat * FLY_ARC, FLY_MIN_ARC, cfg.launchMaxHeight)
	local apex = math.min(math.max(delta.Y, 0) + rise, cfg.launchMaxHeight)
	if apex < delta.Y + 1 then
		return nil, "high"
	end

	-- Gravity that reaches the target at leapSpeed with this apex, kept inside the glide limits
	local want = (math.sqrt(2 * apex) + math.sqrt(2 * (apex - delta.Y))) / (flat / cfg.leapSpeed)
	local gravity = math.clamp(want * want, Workspace.Gravity * FLY_GRAVITY_MIN, Workspace.Gravity * FLY_GRAVITY_MAX)
	local velocity, time = apexLaunch(from, aim, gravity, apex)

	local plan = { velocity = velocity, gravity = gravity, time = time, kind = "fly" }
	if not self:arcClear(plan) then
		return nil, "blocked"
	end
	return plan
end

-- Launch up onto an elevated perch, raising the apex step by step until the arc clears the obstacle edge.
function Nav:solveObstacle(aim)
	local cfg = self.cfg
	local gravity = Workspace.Gravity * OBSTACLE_GRAVITY_SCALE
	local dy = aim.Y - self.position.Y
	local flat = Vector3.new(aim.X - self.position.X, 0, aim.Z - self.position.Z).Magnitude

	for _, clearance in OBSTACLE_CLEARANCES do
		local apex = math.max(dy, 0) + clearance
		-- A higher arc would exceed the launch limit
		if apex > cfg.launchMaxHeight then
			break
		end
		local velocity, time = apexLaunch(self.position, aim, gravity, apex)
		if flat / time <= cfg.leapSpeed * 1.5 then
			local plan = { velocity = velocity, gravity = gravity, time = time, kind = "obstacle" }
			if self:arcClear(plan) then
				return plan
			end
		end
	end
	return nil
end

-- Chooses the leap for the current target (obstacle launch, short ground leap or long fly) and returns its plan.
-- Returns nil plus a reason ("high", "blocked" or "range") when no leap fits.
function Nav:planLeap(targetPos, dist)
	local cfg = self.cfg
	local delta = targetPos - self.position
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local rise, perch = self:targetRise(targetPos)

	-- Target stands on a medium or high obstacle
	if perch and rise >= OBSTACLE_MEDIUM then
		-- Beyond the launch limit: fall back to pathfinding for an alternate route
		if rise + OBSTACLE_CLEARANCES[1] > cfg.launchMaxHeight then
			return nil, "high"
		end
		if flat > OBSTACLE_RANGE then
			return nil, "range"
		end
		local plan = self:solveObstacle(perch + Vector3.new(0, cfg.rideHeight, 0))
		if plan == nil then
			return nil, "blocked"
		end
		return plan
	end

	-- Level target: ground leap up close, fly leap further out
	if dist >= cfg.leapMinRange and dist <= cfg.leapMaxRange then
		return self:solveGround(targetPos)
	elseif dist > cfg.leapMaxRange and dist <= cfg.flyMaxRange then
		return self:solveFly(targetPos)
	end
	return nil, "range"
end

-- Computes a route off-thread (ComputeAsync yields) and stores its waypoints when it finishes.
function Nav:requestPath(targetPos)
	if self.pathBusy or self.clock < self.pathAt then
		return
	end
	self.pathBusy = true
	self.pathAt = self.clock + PATH_INTERVAL
	local start = self.position - Vector3.new(0, self.cfg.rideHeight, 0)

	task.spawn(function()
		local path = PathfindingService:CreatePath(PATH_AGENT)
		local ok = pcall(function()
			path:ComputeAsync(start, targetPos)
		end)
		-- The antlion may have been destroyed while the path was computing
		if not self.destroyed then
			local points = nil
			if ok and path.Status == Enum.PathStatus.Success then
				points = {}
				for _, waypoint in path:GetWaypoints() do
					table.insert(points, waypoint.Position)
				end
			end
			self.waypoints = points
			self.waypointIndex = 2
		end
		self.pathBusy = false
	end)
end

-- Planar vector toward the next waypoint, or nil when no route is active (steer then heads straight for the target).
function Nav:routeVector()
	local points = self.waypoints
	if not self.usePath or points == nil then
		return nil
	end
	for index = self.waypointIndex, #points do
		local offset = points[index] - self.position
		local flat = offset - self.up * offset:Dot(self.up)
		if flat.Magnitude > WAYPOINT_REACH then
			-- Remember progress so reached waypoints are not revisited
			self.waypointIndex = index
			return flat
		end
	end
	return nil
end

-- Throttled planner: refreshes the pathfinding decision and reports whether a leap should start now.
function Nav:scan(targetPos, dist)
	if self.clock < self.scanAt then
		return false
	end
	self.scanAt = self.clock + SCAN_INTERVAL

	local plan, reason = self:planLeap(targetPos, dist)

	-- Walk a route when no leap fits and the target is too high, the arc is blocked, or a wall is in the way
	self.usePath = plan == nil and (reason == "high" or reason == "blocked" or not self:lineOfSight(targetPos))
	if self.usePath then
		self:requestPath(targetPos)
	else
		self.waypoints = nil
	end

	return plan ~= nil and self.leapCd <= 0
end

return Nav

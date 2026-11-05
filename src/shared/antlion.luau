local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Modules = Shared.modules

local Config = require(Modules.helpers.config)
local util = require(Modules.helpers.util)

local Antlion = {}
Antlion.__index = Antlion

local swarm = {}

local ATTRIBUTES = {
	"maxHealth",
	"runSpeed",
	"turnSpeed",
	"senseRange",
	"loseRange",
	"stopDistance",
	"biteRange",
	"biteDamage",
	"biteCooldown",
	"leapDamage",
	"leapCooldown",
	"leapMinRange",
	"leapMaxRange",
	"leapSpeed",
	"leapHitRadius",
  "launchMaxHeight",
  "flyMaxRange",
}

for _, module in {
	require(Modules.rig.state),
	require(Modules.rig.bodies),
	require(Modules.rig.joints),
	require(Modules.animation),
	require(Modules.navigation),
  require(Modules.motion),
} do
	for key, fn in module do
		Antlion[key] = fn
	end
end

function Antlion.new(spawn, config, parent)
	local self = setmetatable({}, Antlion)

	local cfg = table.clone(Config.defaults)
	if config then
		for key, value in config do
			cfg[key] = value
		end
	end

	self.cfg = cfg
	self.model = Instance.new("Model")
	self.model.Name = "Antlion"
	self.health = cfg.maxHealth
	self.onDeath = nil

  self.falling = false
  self.fallingSpeed = 0
  self.airTime = 0

	self.leapGravity = 0
	self.leapTime = 0
	self.leapKind = "ground"
	self.scanAt = 0
	self.usePath = false
	self.waypoints = nil
	self.waypointIndex = 1
	self.pathAt = 0
	self.pathBusy = false

	for _, key in ATTRIBUTES do
		self.model:SetAttribute(key, cfg[key])
	end
	self.model:SetAttribute("State", "Idle")
	self.model.AttributeChanged:Connect(function(name)
		local value = self.model:GetAttribute(name)
		if table.find(ATTRIBUTES, name) and typeof(value) == "number" then
			cfg[name] = value
		end
	end)

	self.legs = {}
	self.jawBase = {}
	self.jawTip = {}
	self.wings = {}
	self.seed = math.random() * 100
	self.sp = {
		pitch = util.newSpring(),
		roll = util.newSpring(),
		crouch = util.newSpring(),
		headYaw = util.newSpring(),
		headPitch = util.newSpring(),
		headRoll = util.newSpring(),
		lunge = util.newSpring(),
		jaw = util.newSpring(),
		wing = util.newSpring(),
		abYaw = util.newSpring(),
		abPitch = util.newSpring(),
	}

	self.position = spawn.Position
	self.forward = spawn.LookVector
	self.up = spawn.UpVector
	self.velocity = Vector3.zero
	self.base = CFrame.new()
	self.pose = CFrame.new()

	self.target = nil
	self.targetModel = nil
	self.state = "Idle"
	self.attackVariant = "bite"
	self.stateTime = 0
	self.clock = 0
	self.speed = 0
	self.turnRate = 0
	self.bob = 0
	self.hop = 0
	self.leapCd = 0
	self.biteCd = 0
	self.fidget = 2
	self.hitDone = false
	self.secondHitDone = false
	self.landed = false
	self.destroyed = false

	self.breathPhase = 0
	self.gaitPhase = 0
	self.headScanTimer = 0
	self.headScanYaw = 0
	self.headScanPitch = 0
	self.twitchTimer = 0
	self.twitchAmount = 0

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.RespectCanCollide = true
	self.rayParams.FilterDescendantsInstances = { self.model }

	self.bodyParams = RaycastParams.new()
	self.bodyParams.FilterType = Enum.RaycastFilterType.Exclude
	self.bodyParams.RespectCanCollide = true
	self.bodyParams.FilterDescendantsInstances = { self.model }

	self:buildBodies()

	local down = Workspace:Raycast(self.position, self.up * -80, self.rayParams)
	if down then
		self.position = down.Position + down.Normal * cfg.rideHeight
		self.up = down.Normal
		local flat = self.forward - self.up * self.forward:Dot(self.up)
		self.forward = if flat.Magnitude > 0.01 then flat.Unit else self.up:Cross(Vector3.xAxis).Unit
	end

	self.sp.abPitch.x = 0.25
	self:refreshPose()
	for _, leg in self.legs do
		local hip = self.base:PointToWorldSpace(leg.hipLocal)
		local ideal = self.base:PointToWorldSpace(leg.restLocal)
		leg.foot = self:groundPoint(hip, ideal)
		leg.stepFrom = leg.foot
		leg.stepTo = leg.foot
	end

	self:render()
	self.model.Parent = parent or Workspace
	self.connection = RunService.Heartbeat:Connect(function(dt)
		self:step(dt)
	end)

	self.swarm = swarm
	swarm[self] = true

	return self
end

function Antlion:setTarget(target)
	self.target = target
end

function Antlion:ignore(...)
	local list = table.clone(self.rayParams.FilterDescendantsInstances)
	for _, instance in { ... } do
		table.insert(list, instance)
	end
	self.rayParams.FilterDescendantsInstances = list
	self:syncBodyParams()
end

function Antlion:getPosition()
	return self.position
end

function Antlion:isAlive()
	return not self.destroyed and self.state ~= "Dead"
end

function Antlion:damage(amount)
	if self.state == "Dead" then
		return
	end
	self.health -= amount
	self.sp.pitch.v -= 4
	self.sp.roll.v += (math.random() - 0.5) * 10
	self.sp.jaw.v += 8
	self.sp.wing.v += 6
	if self.health <= 0 then
		self.health = 0
		self:setState("Dead")
		local callback = self.onDeath
		if callback then
			callback()
		end
	end
end

function Antlion:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.swarm[self] = nil
	self.connection:Disconnect()
	self.model:Destroy()
end

function Antlion:step(rawDt)
	local dt = math.min(rawDt, 1 / 30)
	self.clock += dt
	self.stateTime += dt
	self.leapCd -= dt
	self.biteCd -= dt

	if self.position.Y < Workspace.FallenPartsDestroyHeight then
		self:destroy()
		return
	end

	local targetPos = self:resolveTarget()
	self:refreshBodyFilter()

	local toTarget = Vector3.zero
	local planar = Vector3.zero
	if targetPos then
		toTarget = targetPos - self.position
		planar = toTarget - self.up * toTarget:Dot(self.up)
	end
	local dist = if targetPos then toTarget.Magnitude else math.huge

	self:think(targetPos, dist)
	if self.destroyed then
		return
	end

	local moving = self:steer(dt, targetPos, planar)
	if self.state == "Leap" then
		self:fly(dt)
	elseif self.state == "Dead" then
		self:fall(dt)
	end
  
  self:gravity(dt)
	self:animate(dt, targetPos)
	self:updateJoints(dt, moving)
	self:fitBody(dt)
	self:separate(dt)
	self:collide()
	self:render()
end

return Antlion

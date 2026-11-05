local Shared = game:GetService("ReplicatedStorage").Shared
local Modules = Shared.modules

local C = require(Modules.helpers.config)
local util = require(Modules.helpers.util)

local Bodies = {}

function Bodies:makePart(name, size, color, shape, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.Color = color
	part.Transparency = transparency or 0
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = self.model
	return part
end

function Bodies:buildBodies()
	local cfg = self.cfg
  
  -- body part colors
	local shell = Color3.fromRGB(139, 96, 48)
	local dark = Color3.fromRGB(84, 58, 30)
	local belly = Color3.fromRGB(176, 128, 66)
	local bone = Color3.fromRGB(222, 198, 148)
	local membrane = Color3.fromRGB(214, 172, 92)
  
  -- body scales
	self.thorax = self:makePart(
    "Thorax",
    Vector3.new(cfg.bodyWidth, 1.3, cfg.bodyLength), shell)

	self.head = self:makePart(
    "Head", Vector3.new(1.5, 1.1, C.HEAD_LENGTH), shell)

	self.abdomen = self:makePart(
    "Abdomen", C.ABDOMEN_SIZE, belly)

	self.model.PrimaryPart = self.thorax

	for _, name in { "L", "R" } do
		table.insert(self.jawBase, self:makePart(
      "Jaw" .. name .. "Base", 
      Vector3.new(0.3, 0.3, C.JAW_BASE), bone))
		
    table.insert(self.jawTip, self:makePart(
      "Jaw" .. name .. "Tip",
      Vector3.new(0.22, 0.22, C.JAW_TIP), bone))

		table.insert(
			self.wings,
			self:makePart(
				"Wing" .. name,
				Vector3.new(0.95, 0.08, C.WING_LENGTH),
				membrane,
				Enum.PartType.Block,
				0.4
			))
	end

	for side = 0, 1 do
		for row = 0, 2 do
			local s = if side == 0 then -1 else 1
			local r = row - 1
			local hipLocal = Vector3.new(s * cfg.bodyWidth * 0.5, 0, r * cfg.rowSpacing)
			local outward = Vector3.new(s, 0, r * 0.6).Unit
			local restLocal = hipLocal + outward * cfg.reach - Vector3.new(0, cfg.rideHeight, 0)
			local index = #self.legs
			
      table.insert(self.legs, {
				row = r,
				side = s,
				group = (row + side) % 2,
				hipLocal = hipLocal,
				restLocal = restLocal,
				airLocal = Vector3.new(outward.X * 3, -1.6, r * 2.6),
				outward = outward,
				foot = Vector3.zero,
				stepFrom = Vector3.zero,
				stepTo = Vector3.zero,
				stepT = 0,
				stepping = false,
				lift = 0,
				drift = 0,
				arm = false,
				
        upper = self:makePart(
					"Leg" .. index .. "Upper",
					Vector3.new(cfg.legThickness, cfg.legThickness, cfg.upperLength),
					dark
				),
				
        lower = self:makePart(
					"Leg" .. index .. "Lower",
					Vector3.new(cfg.legThickness * 0.75, cfg.legThickness * 0.75, cfg.lowerLength),
					dark
				),
			})
		end
	end
end

function Bodies:render()
	local cfg = self.cfg
	local sp = self.sp
	local dead = self.state == "Dead"
	self:refreshPose()
	local pose = self.pose

	self.thorax.CFrame = pose

	local neck = pose
		* CFrame.new(0, 0.1, -cfg.bodyLength * 0.5)
		* CFrame.Angles(0, sp.headYaw.x, 0)
		* CFrame.Angles(sp.headPitch.x, 0, sp.headRoll.x)
		* CFrame.new(0, 0, -sp.lunge.x)
	self.head.CFrame = neck * CFrame.new(0, 0, -C.HEAD_LENGTH * 0.5)

	local tail = pose
		* CFrame.new(0, -0.3, cfg.bodyLength * 0.5 - 0.25)
		* CFrame.Angles(0, sp.abYaw.x, 0)
		* CFrame.Angles(sp.abPitch.x, 0, 0)
	self.abdomen.CFrame = tail * CFrame.new(0, 0, C.ABDOMEN_SIZE.Z * 0.5)

	local airborne = self.state == "Windup" or self.state == "Leap" or self:pouncing()

	for i = 0, 1 do
		local s = if i == 0 then -1 else 1

		local hinge = neck
			* CFrame.new(s * 0.45, -0.15, -C.HEAD_LENGTH)
			* CFrame.Angles(0, -s * (sp.jaw.x * 0.9 - 0.1), 0)
		
    self.jawBase[i + 1].CFrame = 
      hinge * CFrame.new(0, 0, -C.JAW_BASE * 0.5)
		
    local hook = 
      hinge * CFrame.new(0, 0, -C.JAW_BASE) * CFrame.Angles(0, s * 0.45, 0)	
    self.jawTip[i + 1].CFrame = 
      hook * CFrame.new(0, 0, -C.JAW_TIP * 0.5)

		local idleJitter = math.sin(self.clock * 45 + i) * 0.015
		local flutterScale = if airborne then 0.3 else 1
		
    local baseFlutter = math.sin(self.clock 
      * 70) * 0.08 * math.max(sp.wing.x - 0.2, 0) * flutterScale

		local leapFlap = 0
		if airborne then
			leapFlap = math.sin(self.clock 
      * 280 + i 
      * 0.8) * 0.45 + math.sin(self.clock * 180 + i * 1.7) * 0.12
		end

		local flutter = baseFlutter + idleJitter + leapFlap

		local wing = pose
			* CFrame.new(s * 0.5, 0.7, -0.4)
			* CFrame.Angles(0, s * (0.15 + sp.wing.x), 0)
			* CFrame.Angles(0.08 - sp.wing.x * 0.7 + flutter, 0, 0)
		self.wings[i + 1].CFrame = wing * CFrame.new(0, 0, C.WING_LENGTH * 0.5)
	end

	for _, leg in self.legs do
		local hip = pose:PointToWorldSpace(leg.hipLocal)
		local tip = leg.foot + self.up * leg.lift
		local outward = pose:VectorToWorldSpace(leg.outward)
		local pole = if dead then outward else pose.UpVector + outward * 0.6
		local knee, endPoint = util.solveTwoBone(hip, tip, cfg.upperLength, cfg.lowerLength, pole)
		util.placeSegment(leg.upper, hip, knee)
		util.placeSegment(leg.lower, knee, endPoint)
	end
end

return Bodies


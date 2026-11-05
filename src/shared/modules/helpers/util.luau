local Util = {}

function Util.newSpring()
	return { x = 0, v = 0 }
end

function Util.spring(s, goal, stiffness, damping, dt)
	s.v += (stiffness * (goal - s.x) - damping * s.v) * dt
	s.x += s.v * dt
end

function Util.solveTwoBone(root, target, l1, l2, pole)
	local delta = target - root
	local dist = math.clamp(delta.Magnitude, math.abs(l1 - l2) + 0.01, l1 + l2 - 0.01)
	local dir = delta.Unit
	local along = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
	local height = math.sqrt(math.max(l1 * l1 - along * along, 0))
	local ortho = pole - dir * pole:Dot(dir)
	local bend = if ortho.Magnitude > 0.001 then ortho.Unit else dir:Cross(Vector3.xAxis).Unit
	local knee = root + dir * along + bend * height
	local tip = root + dir * dist
	return knee, tip
end

function Util.placeSegment(part, a, b)
	part.CFrame = CFrame.lookAt((a + b) * 0.5, b)
end

return Util


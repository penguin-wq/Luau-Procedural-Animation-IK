local Config = {}

Config.defaults = {
	maxHealth = 60,
	runSpeed = 18,
	turnSpeed = math.rad(260),
	senseRange = 90,
	loseRange = 140,
	stopDistance = 3.5,
	biteRange = 6.5,
	biteDamage = 12,
	biteCooldown = 0.9,
	leapDamage = 20,
	leapCooldown = 3.5,
	leapMinRange = 12,
	leapMaxRange = 34,
	leapSpeed = 60,
	leapHitRadius = 5,
	bodyLength = 3.4,
	bodyWidth = 2.2,
	rideHeight = 2.4,
	rowSpacing = 1.2,
	upperLength = 2.6,
	lowerLength = 3.8,
	reach = 3,
	stepThreshold = 1.6,
	stepDuration = 0.1,
	stepHeight = 1.2,
	castExtra = 3,
	legThickness = 0.5,
}


-- constants
local ABDOMEN = 2.2

Config.HEAD_LENGTH = 1.7
Config.JAW_BASE = 1
Config.JAW_TIP = 0.8
Config.WING_LENGTH = 2.6
Config.ABDOMEN_SIZE = Vector3.new(ABDOMEN * 0.9, ABDOMEN * 0.8, ABDOMEN * 1.4)

Config.WINDUP_TIME = 0.5
Config.RECOVER_TIME = 0.45
Config.DEATH_TIME = 6

Config.BITE_STRIKE = 0.28
Config.BITE_TIME = 0.6
Config.REND_STRIKE = 0.35
Config.REND_TIME = 0.8

Config.MAUL_POUNCE_START = 0.2
Config.MAUL_STRIKE = 0.38
Config.MAUL_SECOND_STRIKE = 0.78
Config.MAUL_TIME = 1.25
Config.MAUL_POUNCE_GAP = 2.2
Config.MAUL_POUNCE_SPEED = 50
Config.MAUL_HOP_HEIGHT = 1.3

Config.LEAP_FLIGHT_TIME = 0.4
Config.LEAP_GRAVITY_SCALE = 2

Config.WALL_PROBES = {
	{ Vector3.new(0, 0, -1), 5.2 },
	{ Vector3.new(0.7071, 0, -0.7071), 4.4 },
	{ Vector3.new(-0.7071, 0, -0.7071), 4.4 },
	{ Vector3.new(1, 0, 0), 2.6 },
	{ Vector3.new(-1, 0, 0), 2.6 },
	{ Vector3.new(0.7071, 0, 0.7071), 4.4 },
	{ Vector3.new(-0.7071, 0, 0.7071), 4.4 },
	{ Vector3.new(0, 0, 1), 4.9 },
}

Config.GROUND_PROBES = {
	{ -2.6, 1.0 },
	{ 0, 1.0 },
	{ 2.8, 1.7 },
}

return Config


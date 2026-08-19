-- Discord: big4kcrackin_4s | Roblox: THEDABLOL35

-- builds one island for testing
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Terrain = Workspace.Terrain

-- One table so every tunable number lives in one place
local CONFIG = {
	Seed = Random.new():NextInteger(1, 2147483646),
	CellSize = 8,
	GridRadius = 18,
	BaseHeight = 22,
	MaxHeight = 36,
	IslandRadius = 132,
	WaterLevel = 0,
	TreeChance = 0.10,
	RockChance = 0.16,
	DetailChance = 0.24,
	ChunkSize = 6, -- rows generated before yielding, keeps frames smooth
}

-- Cached Enum lookups so hot loops don't retype Enum paths
local MATERIALS = {
	Grass = Enum.Material.Grass,
	Ground = Enum.Material.Ground,
	Rock = Enum.Material.Rock,
	Sand = Enum.Material.Sand,
	Snow = Enum.Material.Snow,
	Water = Enum.Material.Water,
}

-- Folder groups every spawned part for easy cleanup later
local generatorFolder = Instance.new("Folder")
generatorFolder.Name = "ProceduralIsland"
generatorFolder.Parent = Workspace

-- Removes a leftover island from a previous run before rebuilding
local oldIsland = Workspace:FindFirstChild("ProceduralIsland")
if oldIsland and oldIsland ~= generatorFolder then
	oldIsland:Destroy()
end

-- Custom RNG so a given seed always draws the same island (seed is randomized per server below)
local RandomSource = {}
RandomSource.__index = RandomSource

function RandomSource.new(seed)
	local self = setmetatable({}, RandomSource)
	self.State = seed
	return self
end

-- Lehmer generator: cheap, deterministic, good enough for terrain
function RandomSource:NextNumber()
	self.State = (self.State * 16807) % 2147483647
	return (self.State - 1) / 2147483646
end

function RandomSource:Range(minimum, maximum)
	return minimum + (maximum - minimum) * self:NextNumber()
end

-- +1 on the max keeps outcomes evenly spread before flooring
function RandomSource:Integer(minimum, maximum)
	return math.floor(self:Range(minimum, maximum + 1))
end

function RandomSource:Chance(percent)
	return self:NextNumber() <= percent
end

local random = RandomSource.new(CONFIG.Seed)

-- Rescales a value from one range into another, linearly
local function remap(value, fromLow, fromHigh, toLow, toHigh)
	local alpha = (value - fromLow) / (fromHigh - fromLow)
	return toLow + (toHigh - toLow) * alpha
end

-- Eases a 0-1 value so edges taper instead of cutting sharply
local function smoothstep(value)
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end

local function getDistanceFromCenter(x, z)
	return math.sqrt(x * x + z * z)
end

-- 1 near the middle, fading to 0 at the shoreline
local function getIslandMask(x, z)
	local distance = getDistanceFromCenter(x, z)
	local edge = distance / CONFIG.IslandRadius
	local mask = 1 - smoothstep(edge)
	return math.clamp(mask, 0, 1)
end

-- Layered noise (Perlin octaves) avoids a flat, repetitive landscape
local function getHeightNoise(x, z)
	local large = math.noise(x * 0.018, z * 0.018, CONFIG.Seed)
	local medium = math.noise(x * 0.052, z * 0.052, CONFIG.Seed + 50)
	local small = math.noise(x * 0.14, z * 0.14, CONFIG.Seed + 100)

	-- Weighted so broad shapes dominate over fine detail
	local combined = large * 0.62
	combined += medium * 0.27
	combined += small * 0.11

	return combined
end

local function getTerrainHeight(x, z)
	local mask = getIslandMask(x, z)
	local noise = getHeightNoise(x, z)
	local noiseHeight = remap(noise, -1, 1, -8, CONFIG.MaxHeight)
	-- Pulls land down toward the sea as the mask shrinks
	local edgeDrop = (1 - mask) * 74
	local height = CONFIG.BaseHeight + noiseHeight * mask - edgeDrop

	-- Stops cliffs from generating an impossibly deep seabed
	return math.max(height, -42)
end

-- Height plus separate noise fields decide the biome per spot
local function getBiome(height, x, z)
	local moisture = math.noise(x * 0.03, z * 0.03, CONFIG.Seed + 200)
	local temperature = math.noise(x * 0.022, z * 0.022, CONFIG.Seed + 400)

	if height < 7 then
		return "Beach"
	end

	if height > 46 then
		return "Snow"
	end

	if moisture > 0.35 then
		return "Forest"
	end

	if temperature > 0.42 then
		return "Dry"
	end

	return "Plains"
end

-- Picks the visible ground texture to match the biome and altitude
local function getSurfaceMaterial(biome, height)
	if biome == "Beach" then
		return MATERIALS.Sand
	end

	if biome == "Snow" then
		return MATERIALS.Snow
	end

	-- High ground reads as rock regardless of biome below it
	if height > 39 then
		return MATERIALS.Rock
	end

	if biome == "Dry" then
		return MATERIALS.Ground
	end

	return MATERIALS.Grass
end

-- Shared part factory keeps every prop's setup identical and tagged
local function createPart(name, size, cframe, material, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Material = material
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = generatorFolder
	-- Tag lets other scripts find these parts without searching names
	CollectionService:AddTag(part, "ProceduralIslandPart")
	return part
end

-- Finds the exact terrain surface, since sculpted terrain has no fixed height
local function getGroundPosition(x, z)
	local rayOrigin = Vector3.new(x, 180, z)
	local rayDirection = Vector3.new(0, -300, 0)

	local parameters = RaycastParams.new()
	-- Include-only filter ignores decorations already placed nearby
	parameters.FilterType = Enum.RaycastFilterType.Include
	parameters.FilterDescendantsInstances = { Terrain }

	local hit = Workspace:Raycast(rayOrigin, rayDirection, parameters)

	if hit then
		return hit.Position, hit.Normal
	end

	return nil, nil
end

-- Falls back to world-up on steep slopes so props don't tilt sideways
local function getSafeUp(normal)
	if normal.Y < 0.65 then
		return Vector3.yAxis
	end

	return normal
end

local function makeRock(position, normal, scale)
	local up = getSafeUp(normal)
	local yaw = random:Range(0, math.pi * 2)
	local tilt = CFrame.fromAxisAngle(Vector3.xAxis, random:Range(-0.24, 0.24))
	-- Random yaw plus slight tilt stops rocks looking copy-pasted
	local rotation = CFrame.Angles(0, yaw, 0) * tilt
	local offset = up * (scale.Y * 0.33)

	local rock = createPart(
		"Rock",
		scale,
		CFrame.new(position + offset) * rotation,
		MATERIALS.Rock,
		Color3.fromRGB(91, 89, 83)
	)

	-- Ball shape reads as a boulder once stretched non-uniformly
	rock.Shape = Enum.PartType.Ball
	rock:SetAttribute("DecorationType", "Rock")
end

local function makeFlower(position, normal)
	local up = getSafeUp(normal)
	local colorChoices = {
		Color3.fromRGB(255, 99, 156),
		Color3.fromRGB(255, 225, 88),
		Color3.fromRGB(150, 119, 255),
	}

	local stem = createPart(
		"FlowerStem",
		Vector3.new(0.16, 1.2, 0.16),
		CFrame.new(position + up * 0.6),
		MATERIALS.Grass,
		Color3.fromRGB(45, 130, 54)
	)

	local bloom = createPart(
		"FlowerBloom",
		Vector3.new(0.7, 0.7, 0.7),
		CFrame.new(position + up * 1.25),
		-- Neon keeps petals bright without needing extra lighting
		Enum.Material.Neon,
		colorChoices[random:Integer(1, #colorChoices)]
	)

	bloom.Shape = Enum.PartType.Ball
	stem:SetAttribute("DecorationType", "Flower")
	bloom:SetAttribute("DecorationType", "Flower")
end

local function makeTree(position, normal, scale)
	local up = getSafeUp(normal)
	local trunkHeight = random:Range(7, 12) * scale
	local trunkWidth = random:Range(1.2, 1.8) * scale
	local trunkCenter = position + up * (trunkHeight * 0.5)

	local trunk = createPart(
		"TreeTrunk",
		Vector3.new(trunkWidth, trunkHeight, trunkWidth),
		CFrame.new(trunkCenter),
		Enum.Material.Wood,
		Color3.fromRGB(90, 57, 34)
	)

	-- Cylinder needs a 90-degree roll to stand upright, not sideways
	trunk.Shape = Enum.PartType.Cylinder
	trunk.CFrame *= CFrame.Angles(0, 0, math.rad(90))

	local crownCenter = position + up * (trunkHeight * 0.95)
	local crownSize = random:Range(6, 9) * scale

	-- Three offset leaf balls fake a full canopy without a mesh
	for index = 1, 3 do
		local angle = (index / 3) * math.pi * 2
		local side = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local offset = side * crownSize * 0.25
		offset += up * random:Range(-0.4, 1.2)

		local leaf = createPart(
			"TreeLeaves",
			Vector3.new(crownSize, crownSize, crownSize),
			CFrame.new(crownCenter + offset),
			MATERIALS.Grass,
			Color3.fromRGB(
				random:Integer(40, 64),
				random:Integer(115, 155),
				random:Integer(48, 72)
			)
		)

		leaf.Shape = Enum.PartType.Ball
		leaf:SetAttribute("DecorationType", "Tree")
	end

	trunk:SetAttribute("DecorationType", "Tree")
end

local function createTerrainCell(x, z)
	local height = getTerrainHeight(x, z)
	local biome = getBiome(height, x, z)
	local material = getSurfaceMaterial(biome, height)
	local surfaceY = height

	-- Solid rock fills below so terrain never has a hollow underside
	local blockHeight = math.max(height + 46, 3)
	local blockCenter = Vector3.new(x, -46 + blockHeight * 0.5, z)
	local blockSize = Vector3.new(CONFIG.CellSize, blockHeight, CONFIG.CellSize)

	Terrain:FillBlock(
		CFrame.new(blockCenter),
		blockSize,
		MATERIALS.Rock
	)

	-- Thin cap layered on top gives the correct visible material
	local topThickness = math.min(5, blockHeight)
	local topCenter = Vector3.new(
		x,
		surfaceY - topThickness * 0.5,
		z
	)

	Terrain:FillBlock(
		CFrame.new(topCenter),
		Vector3.new(CONFIG.CellSize, topThickness, CONFIG.CellSize),
		material
	)

	return height, biome
end

local function decorateCell(x, z, height, biome)
	-- Skips underwater or near-shore cells so props don't float on waves
	if height < 4 then
		return
	end

	local position, normal = getGroundPosition(x, z)

	if not position then
		return
	end

	-- Trees only roll in forest cells, keeping biomes visually distinct
	if biome == "Forest" and random:Chance(CONFIG.TreeChance) then
		makeTree(position, normal, random:Range(0.8, 1.25))
		return
	end

	if random:Chance(CONFIG.RockChance) then
		local scale = Vector3.new(
			random:Range(2, 5),
			random:Range(1.5, 4),
			random:Range(2, 5)
		)

		makeRock(position, normal, scale)
		return
	end

	if biome == "Plains" and random:Chance(CONFIG.DetailChance) then
		makeFlower(position, normal)
	end
end

local function createWater()
	local size = CONFIG.IslandRadius * 2.6
	-- Sunk slightly below sea level so the surface reads as a plane
	local waterCenter = Vector3.new(0, CONFIG.WaterLevel - 3, 0)

	Terrain:FillBlock(
		CFrame.new(waterCenter),
		Vector3.new(size, 6, size),
		MATERIALS.Water
	)
end

local function createSpawn()
	local spawnPosition, normal = getGroundPosition(0, 0)

	if not spawnPosition then
		return
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IslandSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	-- Lifted by 1 stud so players don't spawn stuck inside terrain
	spawn.Position = spawnPosition + getSafeUp(normal) * 1
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Color = Color3.fromRGB(117, 78, 49)
	spawn.Anchored = true
	-- Neutral stops it acting like a team-only spawn point
	spawn.Neutral = true
	spawn.Parent = generatorFolder
end

local function generateIsland()
	Terrain:Clear()

	-- Heights are cached so decoration never recomputes noise twice
	local cellData = {}

	for gridX = -CONFIG.GridRadius, CONFIG.GridRadius do
		cellData[gridX] = {}

		for gridZ = -CONFIG.GridRadius, CONFIG.GridRadius do
			local x = gridX * CONFIG.CellSize
			local z = gridZ * CONFIG.CellSize
			local distance = getDistanceFromCenter(x, z)

			-- Circular island shape instead of a square terrain block
			if distance <= CONFIG.IslandRadius then
				local height, biome = createTerrainCell(x, z)

				cellData[gridX][gridZ] = {
					Height = height,
					Biome = biome,
				}
			end
		end

		-- Yielding every few rows keeps the server from freezing up
		if gridX % CONFIG.ChunkSize == 0 then
			RunService.Heartbeat:Wait()
		end
	end

	-- Decoration runs after all terrain exists, so raycasts always hit
	for gridX = -CONFIG.GridRadius, CONFIG.GridRadius do
		for gridZ = -CONFIG.GridRadius, CONFIG.GridRadius do
			local cell = cellData[gridX][gridZ]

			if cell then
				local x = gridX * CONFIG.CellSize
				local z = gridZ * CONFIG.CellSize
				local distance = getDistanceFromCenter(x, z)

				-- Shrunk radius keeps props off the crumbling coastline
				if distance <= CONFIG.IslandRadius * 0.92 then
					decorateCell(x, z, cell.Height, cell.Biome)
				end
			end
		end

		if gridX % CONFIG.ChunkSize == 0 then
			RunService.Heartbeat:Wait()
		end
	end

	createWater()
	createSpawn()
end

-- Applies movement tuning fresh each respawn, since a new Humanoid is made
local function welcomePlayer(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
	end)
end

Players.PlayerAdded:Connect(welcomePlayer)

-- Covers players already in-game before this script started running
for _, player in Players:GetPlayers() do
	welcomePlayer(player)
end

generateIsland()

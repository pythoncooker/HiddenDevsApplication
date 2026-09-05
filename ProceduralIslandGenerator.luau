-- Discord: big4kcrackin_4s | Roblox: THEDABLOL35

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Terrain = workspace.Terrain

local CONFIG = table.freeze({
	Seed = math.random(1, 2147483646),
	Terrain = table.freeze({
		CellSize = 8, GridRadius = 18, ChunkSize = 6,
		BaseHeight = 22, MaxHeight = 36, HeightFloor = -42,
		IslandRadius = 132, WaterLevel = 0, WaterSizeMultiplier = 2.6,
		WaterThickness = 6, WaterDepthOffset = 3, CoastlineDropoff = 74,
		RockColumnBase = 46, TopLayerMaxThickness = 5,
	}),
	Noise = table.freeze({
		BigScale = 0.018, MidScale = 0.052, SmallScale = 0.14,
		BigWeight = 0.62, MidWeight = 0.27, SmallWeight = 0.11,
		MidSeedOffset = 50, SmallSeedOffset = 100,
		MoistureScale = 0.03, MoistureSeedOffset = 200,
		TemperatureScale = 0.022, TemperatureSeedOffset = 400,
	}),
	Biome = table.freeze({
		BeachHeightMax = 7, SnowHeightMin = 46, RockHeightMin = 39,
		ForestMoistureMin = 0.35, DryTemperatureMin = 0.42,
	}),
	Decoration = table.freeze({
		TreeChance = 0.10, RockChance = 0.16, FlowerChance = 0.24,
		MinDecorationHeight = 4, EdgeExclusionFactor = 0.92,
		RaycastUpStart = 180, RaycastDownDistance = 300, MaxWalkableNormalY = 0.65,
	}),
})

-- this stops a bad number from breaking things later on
assert(CONFIG.Terrain.GridRadius > 0, "GridRadius must be positive")
assert(CONFIG.Terrain.IslandRadius > 0, "IslandRadius must be positive")

-- keeps all the materials in one spot
local MAT = table.freeze({
	Grass = Enum.Material.Grass, Ground = Enum.Material.Ground, Rock = Enum.Material.Rock,
	Sand = Enum.Material.Sand, Snow = Enum.Material.Snow, Water = Enum.Material.Water,
})

-- delete the old island first so we dont end up with two
local old = workspace:FindFirstChild("ProceduralIsland")
if old then old:Destroy() end

-- puts everything inside one folder so the whole island can move or get deleted as one thing
local genFolder = Instance.new("Folder")
genFolder.Name = "ProceduralIsland"
genFolder.Parent = workspace

-- this rng is just for props so it stays separate from the terrain noise
local rng = Random.new(CONFIG.Seed)
print("Island seed:", CONFIG.Seed)

-- makes the number curve nice instead of jumping straight from 0 to 1
local function smoothstep(v)
	v = math.clamp(v, 0, 1)
	return v * v * (3 - 2 * v)
end

local function distance2D(x, z)
	return math.sqrt(x * x + z * z)
end

-- makes the land fade out the closer it gets to the edge
local function islandMask(x, z)
	local edge = distance2D(x, z) / CONFIG.Terrain.IslandRadius
	return math.clamp(1 - smoothstep(edge), 0, 1)
end

-- mixes three layers of noise together big bumps and small bumps
local function heightNoise(x, z)
	local n = CONFIG.Noise
	local big = math.noise(x * n.BigScale, z * n.BigScale, CONFIG.Seed)
	local mid = math.noise(x * n.MidScale, z * n.MidScale, CONFIG.Seed + n.MidSeedOffset)
	local small = math.noise(x * n.SmallScale, z * n.SmallScale, CONFIG.Seed + n.SmallSeedOffset)
	return big * n.BigWeight + mid * n.MidWeight + small * n.SmallWeight
end

local function terrainHeight(x, z)
	local t = CONFIG.Terrain
	local mask = islandMask(x, z)
	-- the noise comes out small so we stretch it way up first
	local stretchedHeight = heightNoise(x, z) * (t.MaxHeight + 8) - 8
	local edgeDrop = (1 - mask) * t.CoastlineDropoff
	return math.max(t.BaseHeight + stretchedHeight * mask - edgeDrop, t.HeightFloor)
end

-- checks height first then checks how wet or hot it is for the rest
local function getBiome(height, x, z)
	local b, n = CONFIG.Biome, CONFIG.Noise
	if height < b.BeachHeightMax then return "Beach" end
	if height > b.SnowHeightMin then return "Snow" end

	local moisture = math.noise(x * n.MoistureScale, z * n.MoistureScale, CONFIG.Seed + n.MoistureSeedOffset)
	if moisture > b.ForestMoistureMin then return "Forest" end

	local temperature = math.noise(x * n.TemperatureScale, z * n.TemperatureScale, CONFIG.Seed + n.TemperatureSeedOffset)
	if temperature > b.DryTemperatureMin then return "Dry" end

	return "Plains"
end

local function surfaceMaterial(biome, height)
	if biome == "Beach" then return MAT.Sand end
	if biome == "Snow" then return MAT.Snow end
	if height > CONFIG.Biome.RockHeightMin then return MAT.Rock end
	if biome == "Dry" then return MAT.Ground end
	return MAT.Grass
end

-- this makes the ray only able to hit the terrain and nothing else
local terrainRaycastParams = RaycastParams.new()
terrainRaycastParams.FilterType = Enum.RaycastFilterType.Include
terrainRaycastParams.FilterDescendantsInstances = { Terrain }

-- shoots a ray straight down to find the ground spot
local function groundPos(x, z)
	local d = CONFIG.Decoration
	local hit = workspace:Raycast(Vector3.new(x, d.RaycastUpStart, z), Vector3.new(0, -d.RaycastDownDistance, 0), terrainRaycastParams)
	if not hit then return nil, nil end
	return hit.Position, hit.Normal
end

-- one class makes every prop type so rock tree and flower all share the same helpers
local Decoration = {}
Decoration.__index = Decoration

-- we only make one of these and it just remembers the folder and the rng to use
function Decoration.new(folder, decorationRng)
	return setmetatable({ Folder = folder, RNG = decorationRng }, Decoration)
end

function Decoration:CreatePart(name, size, cframe, material, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Material = material
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = self.Folder

	CollectionService:AddTag(part, name) -- lets other scripts find this part later
	part:SetAttribute("DecorationType", name)

	return part
end

-- stops stuff from leaning too far over on steep ground
function Decoration:SafeUp(normal)
	if normal.Y < CONFIG.Decoration.MaxWalkableNormalY then return Vector3.yAxis end
	return normal
end

function Decoration:SpawnRock(pos, normal)
	local up, rng = self:SafeUp(normal), self.RNG
	local scale = Vector3.new(rng:NextNumber(2, 5), rng:NextNumber(1.5, 4), rng:NextNumber(2, 5))
	local rotation = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * CFrame.fromAxisAngle(Vector3.xAxis, rng:NextNumber(-0.24, 0.24))
	local offset = up * (scale.Y * 0.33) -- lifts it up so it doesnt sink into the ground

	local rock = self:CreatePart("Rock", scale, CFrame.new(pos + offset) * rotation, MAT.Rock, Color3.fromRGB(91, 89, 83))
	rock.Shape = Enum.PartType.Ball
end

-- lives out here since every flower shares the same colors
local FLOWER_COLORS = table.freeze({ Color3.fromRGB(255, 99, 156), Color3.fromRGB(255, 225, 88), Color3.fromRGB(150, 119, 255) })

function Decoration:SpawnFlower(pos, normal)
	local up, rng = self:SafeUp(normal), self.RNG
	self:CreatePart("FlowerStem", Vector3.new(0.16, 1.2, 0.16), CFrame.new(pos + up * 0.6), MAT.Grass, Color3.fromRGB(45, 130, 54))

	-- neon makes the flower glow so it still shows up in the shade
	local bloom = self:CreatePart("FlowerBloom", Vector3.new(0.7, 0.7, 0.7), CFrame.new(pos + up * 1.25), Enum.Material.Neon, FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)])
	bloom.Shape = Enum.PartType.Ball
end

function Decoration:SpawnTree(pos, normal, scaleFactor)
	local up, rng = self:SafeUp(normal), self.RNG
	local trunkHeight = rng:NextNumber(7, 12) * scaleFactor
	local trunkWidth = rng:NextNumber(1.2, 1.8) * scaleFactor

	local trunk = self:CreatePart("TreeTrunk", Vector3.new(trunkWidth, trunkHeight, trunkWidth), CFrame.new(pos + up * (trunkHeight * 0.5)), Enum.Material.Wood, Color3.fromRGB(90, 57, 34))
	trunk.Shape = Enum.PartType.Cylinder
	trunk.CFrame *= CFrame.Angles(0, 0, math.rad(90)) -- the cylinder lies on its side so we stand it up

	local crownCenter = pos + up * (trunkHeight * 0.95)
	local crownSize = rng:NextNumber(6, 9) * scaleFactor

	-- three balls placed in a circle look like one bumpy tree top
	for i = 1, 3 do
		local angle = (i / 3) * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * crownSize * 0.25 + up * rng:NextNumber(-0.4, 1.2)
		local leafColor = Color3.fromRGB(rng:NextInteger(40, 64), rng:NextInteger(115, 155), rng:NextInteger(48, 72))
		local leaf = self:CreatePart("TreeLeaves", Vector3.new(crownSize, crownSize, crownSize), CFrame.new(crownCenter + offset), MAT.Grass, leafColor)
		leaf.Shape = Enum.PartType.Ball
	end
end

-- fills in rock first then adds a thin top layer for the biome
local function createTerrainCell(x, z)
	local t = CONFIG.Terrain
	local height = terrainHeight(x, z)
	local biome = getBiome(height, x, z)

	-- the rock always goes down deep enough so it still reaches under the water near the coast
	local blockHeight = math.max(height + t.RockColumnBase, 3)
	Terrain:FillBlock(CFrame.new(x, -t.RockColumnBase + blockHeight * 0.5, z), Vector3.new(t.CellSize, blockHeight, t.CellSize), MAT.Rock)

	local topThickness = math.min(t.TopLayerMaxThickness, blockHeight)
	Terrain:FillBlock(CFrame.new(x, height - topThickness * 0.5, z), Vector3.new(t.CellSize, topThickness, t.CellSize), surfaceMaterial(biome, height))

	return height, biome
end

local function decorateCell(x, z, height, biome, decoration, stats)
	local d = CONFIG.Decoration
	if height < d.MinDecorationHeight then return end

	local pos, normal = groundPos(x, z)
	if not pos then return end

	-- only one prop can spawn on each spot
	if biome == "Forest" and rng:NextNumber() <= d.TreeChance then
		decoration:SpawnTree(pos, normal, rng:NextNumber(0.8, 1.25))
		stats.DecorationCount += 1
	elseif rng:NextNumber() <= d.RockChance then
		decoration:SpawnRock(pos, normal)
		stats.DecorationCount += 1
	elseif biome == "Plains" and rng:NextNumber() <= d.FlowerChance then
		decoration:SpawnFlower(pos, normal)
		stats.DecorationCount += 1
	end
end

local function createWater()
	local t = CONFIG.Terrain
	local size = t.IslandRadius * t.WaterSizeMultiplier
	Terrain:FillBlock(CFrame.new(0, t.WaterLevel - t.WaterDepthOffset, 0), Vector3.new(size, t.WaterThickness, size), MAT.Water)
end

local function createSpawn()
	local pos, normal = groundPos(0, 0)
	if not pos then return nil end
	local up = normal.Y >= CONFIG.Decoration.MaxWalkableNormalY and normal or Vector3.yAxis

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IslandSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = pos + up * 1
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Color = Color3.fromRGB(117, 78, 49)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Parent = genFolder

	-- lets a player press e on the platform to see what seed made the island
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Reveal Seed"
	prompt.ObjectText = "Island Spawn"
	prompt.HoldDuration = 0.5
	prompt.Parent = spawn
	prompt.Triggered:Connect(function(player)
		print(("%s asked for the seed: %d"):format(player.Name, CONFIG.Seed))
	end)

	return spawn
end

-- terrain has to be built first so the ray has something to hit
local function generateIsland()
	Terrain:Clear()

	local t = CONFIG.Terrain
	local stats = { Biomes = {}, DecorationCount = 0 }
	local decoration = Decoration.new(genFolder, rng)
	-- saves the height and biome for each spot so we dont redo the math later
	local cellData = {}

	for gx = -t.GridRadius, t.GridRadius do
		cellData[gx] = {}
		for gz = -t.GridRadius, t.GridRadius do
			local x, z = gx * t.CellSize, gz * t.CellSize
			if distance2D(x, z) <= t.IslandRadius then
				local height, biome = createTerrainCell(x, z)
				cellData[gx][gz] = { Height = height, Biome = biome }
				stats.Biomes[biome] = (stats.Biomes[biome] or 0) + 1
			end
		end
		if gx % t.ChunkSize == 0 then RunService.Heartbeat:Wait() end
	end

	-- skips the edge so props dont spawn right where the land drops off the hardest
	for gx = -t.GridRadius, t.GridRadius do
		for gz = -t.GridRadius, t.GridRadius do
			local cell = cellData[gx][gz]
			if cell then
				local x, z = gx * t.CellSize, gz * t.CellSize
				if distance2D(x, z) <= t.IslandRadius * CONFIG.Decoration.EdgeExclusionFactor then
					decorateCell(x, z, cell.Height, cell.Biome, decoration, stats)
				end
			end
		end
		if gx % t.ChunkSize == 0 then RunService.Heartbeat:Wait() end
	end

	createWater()
	createSpawn()

	print(("Island generated with %d decorations"):format(stats.DecorationCount))
	for biome, count in pairs(stats.Biomes) do
		print(("  %s: %d cells"):format(biome, count))
	end
end

generateIsland()

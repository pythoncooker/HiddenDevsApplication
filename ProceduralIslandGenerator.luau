-- Discord: big4kcrackin_4s | Roblox: THEDABLOL35

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Terrain = Workspace.Terrain

local CONFIG = {
	Seed = math.random(1, 2147483646),
	CellSize = 8,
	GridRadius = 18,
	BaseHeight = 22,
	MaxHeight = 36,
	IslandRadius = 132,
	WaterLevel = 0,
	TreeChance = 0.10,
	RockChance = 0.16,
	DetailChance = 0.24,
	ChunkSize = 6, -- yield after 6 rows
}

local MAT = {
	Grass = Enum.Material.Grass,
	Ground = Enum.Material.Ground,
	Rock = Enum.Material.Rock,
	Sand = Enum.Material.Sand,
	Snow = Enum.Material.Snow,
	Water = Enum.Material.Water,
}

-- remove old island before building a new one
local old = Workspace:FindFirstChild("ProceduralIsland")
if old then
	old:Destroy()
end

local genFolder = Instance.new("Folder")
genFolder.Name = "ProceduralIsland"
genFolder.Parent = Workspace

-- changing the seed changes the terrain layout
local rng = Random.new(CONFIG.Seed)
print("Island seed:", CONFIG.Seed)

local function smoothstep(v)
	v = math.clamp(v, 0, 1)
	return v * v * (3 - 2 * v)
end

local function dist(x, z)
	return math.sqrt(x * x + z * z)
end

-- 1 in the middle 0 at the edge
-- this gives the island its shape
local function islandMask(x, z)
	local d = dist(x, z)
	local edge = d / CONFIG.IslandRadius
	return math.clamp(1 - smoothstep(edge), 0, 1)
end

-- each layer adds a different amount of detail
-- the big noise has the biggest effect on the final height
local function heightNoise(x, z)
	local big = math.noise(x * 0.018, z * 0.018, CONFIG.Seed)
	local mid = math.noise(x * 0.052, z * 0.052, CONFIG.Seed + 50)
	local small = math.noise(x * 0.14, z * 0.14, CONFIG.Seed + 100)
	return big * 0.62 + mid * 0.27 + small * 0.11
end

local function terrainHeight(x, z)
	local mask = islandMask(x, z)
	local n = heightNoise(x, z) -- -1 to 1
	local nh = n * (CONFIG.MaxHeight + 8) - 8 -- stretched into a usable height range
	local edgeDrop = (1 - mask) * 74 -- pulls coastline down toward the water
	local h = CONFIG.BaseHeight + nh * mask - edgeDrop
	return math.max(h, -42)
end

-- use the height first then noise for moisture and temperature
-- different places of the island get different biomes
local function getBiome(height, x, z)
	local moisture = math.noise(x * 0.03, z * 0.03, CONFIG.Seed + 200)
	local temp = math.noise(x * 0.022, z * 0.022, CONFIG.Seed + 400)

	if height < 7 then
		return "Beach"
	end
	if height > 46 then
		return "Snow"
	end
	if moisture > 0.35 then
		return "Forest"
	end
	if temp > 0.42 then
		return "Dry"
	end

	return "Plains"
end

local function surfaceMaterial(biome, height)
	if biome == "Beach" then return MAT.Sand end
	if biome == "Snow" then return MAT.Snow end
	if height > 39 then return MAT.Rock end -- steep high ground reads as rock no matter the biome
	if biome == "Dry" then return MAT.Ground end
	return MAT.Grass
end

local function createPart(name, size, cf, material, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Material = material
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = genFolder
	return p
end

-- get the real surface position instead of using the generated height
-- keeps trees rocks and flowers on the terrain
local function groundPos(x, z)
	local origin = Vector3.new(x, 180, z)
	local dir = Vector3.new(0, -300, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Terrain }

	local hit = Workspace:Raycast(origin, dir, params)
	if hit then
		return hit.Position, hit.Normal
	end
	return nil, nil
end

-- normal ground can use its surface normal
--steep ground gets straight-up direction instead
local function safeUp(normal)
	if normal.Y < 0.65 then
		return Vector3.yAxis
	end
	return normal
end

local function makeRock(pos, normal, scale)
	local up = safeUp(normal)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local tilt = CFrame.fromAxisAngle(Vector3.xAxis, rng:NextNumber(-0.24, 0.24))
	local rot = CFrame.Angles(0, yaw, 0) * tilt
	local offset = up * (scale.Y * 0.33)

	local rock = createPart("Rock", scale, CFrame.new(pos + offset) * rot, MAT.Rock, Color3.fromRGB(91, 89, 83))
	rock.Shape = Enum.PartType.Ball
	rock:SetAttribute("DecorationType", "Rock")
end

local function makeFlower(pos, normal)
	local up = safeUp(normal)
	local colors = {
		Color3.fromRGB(255, 99, 156),
		Color3.fromRGB(255, 225, 88),
		Color3.fromRGB(150, 119, 255),
	}

	local stem = createPart("FlowerStem", Vector3.new(0.16, 1.2, 0.16), CFrame.new(pos + up * 0.6), MAT.Grass, Color3.fromRGB(45, 130, 54))
	local bloom = createPart("FlowerBloom", Vector3.new(0.7, 0.7, 0.7), CFrame.new(pos + up * 1.25), Enum.Material.Neon, colors[rng:NextInteger(1, #colors)])
	bloom.Shape = Enum.PartType.Ball

	stem:SetAttribute("DecorationType", "Flower")
	bloom:SetAttribute("DecorationType", "Flower")
end

local function makeTree(pos, normal, scale)
	local up = safeUp(normal)
	local trunkH = rng:NextNumber(7, 12) * scale
	local trunkW = rng:NextNumber(1.2, 1.8) * scale
	local trunkCenter = pos + up * (trunkH * 0.5)

	local trunk = createPart("TreeTrunk", Vector3.new(trunkW, trunkH, trunkW), CFrame.new(trunkCenter), Enum.Material.Wood, Color3.fromRGB(90, 57, 34))
	trunk.Shape = Enum.PartType.Cylinder
	trunk.CFrame *= CFrame.Angles(0, 0, math.rad(90)) -- cylinder lays on its side default so rotate it upright

	local crownCenter = pos + up * (trunkH * 0.95)
	local crownSize = rng:NextNumber(6, 9) * scale

	--small offset spheres make one larger canopy
	for i = 1, 3 do
		local angle = (i / 3) * math.pi * 2
		local side = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local offset = side * crownSize * 0.25 + up * rng:NextNumber(-0.4, 1.2)

		local leaf = createPart(
			"TreeLeaves",
			Vector3.new(crownSize, crownSize, crownSize),
			CFrame.new(crownCenter + offset),
			MAT.Grass,
			Color3.fromRGB(rng:NextInteger(40, 64), rng:NextInteger(115, 155), rng:NextInteger(48, 72))
		)
		leaf.Shape = Enum.PartType.Ball
		leaf:SetAttribute("DecorationType", "Tree")
	end

	trunk:SetAttribute("DecorationType", "Tree")
end

--build the column with rock first
-- the top layer is changed to match the biome
local function createTerrainCell(x, z)
	local height = terrainHeight(x, z)
	local biome = getBiome(height, x, z)
	local material = surfaceMaterial(biome, height)

	local blockHeight = math.max(height + 46, 3)
	local blockCenter = Vector3.new(x, -46 + blockHeight * 0.5, z)
	Terrain:FillBlock(CFrame.new(blockCenter), Vector3.new(CONFIG.CellSize, blockHeight, CONFIG.CellSize), MAT.Rock)

	local topThickness = math.min(5, blockHeight)
	local topCenter = Vector3.new(x, height - topThickness * 0.5, z)
	Terrain:FillBlock(CFrame.new(topCenter), Vector3.new(CONFIG.CellSize, topThickness, CONFIG.CellSize), material)

	return height, biome
end

local function decorateCell(x, z, height, biome)
	if height < 4 then return end -- keep props off anything near or under the water

	local pos, normal = groundPos(x, z)
	if not pos then return end

	if biome == "Forest" and rng:NextNumber() <= CONFIG.TreeChance then
		makeTree(pos, normal, rng:NextNumber(0.8, 1.25))
		return
	end

	if rng:NextNumber() <= CONFIG.RockChance then
		local scale = Vector3.new(rng:NextNumber(2, 5), rng:NextNumber(1.5, 4), rng:NextNumber(2, 5))
		makeRock(pos, normal, scale)
		return
	end

	if biome == "Plains" and rng:NextNumber() <= CONFIG.DetailChance then
		makeFlower(pos, normal)
	end
end

local function createWater()
	local size = CONFIG.IslandRadius * 2.6
	local center = Vector3.new(0, CONFIG.WaterLevel - 3, 0)
	Terrain:FillBlock(CFrame.new(center), Vector3.new(size, 6, size), MAT.Water)
end

local function createSpawn()
	local pos, normal = groundPos(0, 0)
	if not pos then return end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IslandSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = pos + safeUp(normal) * 1
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Color = Color3.fromRGB(117, 78, 49)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Parent = genFolder
end

-- finish the terrain before placing decorations
-- or some raycasts could run before the ground exists
local function generateIsland()
	Terrain:Clear()

	local cellData = {}

	for gx = -CONFIG.GridRadius, CONFIG.GridRadius do
		cellData[gx] = {}

		for gz = -CONFIG.GridRadius, CONFIG.GridRadius do
			local x = gx * CONFIG.CellSize
			local z = gz * CONFIG.CellSize

			if dist(x, z) <= CONFIG.IslandRadius then
				local h, b = createTerrainCell(x, z)
				cellData[gx][gz] = { Height = h, Biome = b }
			end
		end

		if gx % CONFIG.ChunkSize == 0 then
			RunService.Heartbeat:Wait()
		end
	end

	for gx = -CONFIG.GridRadius, CONFIG.GridRadius do
		for gz = -CONFIG.GridRadius, CONFIG.GridRadius do
			local cell = cellData[gx][gz]
			if cell then
				local x = gx * CONFIG.CellSize
				local z = gz * CONFIG.CellSize
				-- doesnt place decorations right on the coastline
				if dist(x, z) <= CONFIG.IslandRadius * 0.92 then
					decorateCell(x, z, cell.Height, cell.Biome)
				end
			end
		end

		if gx % CONFIG.ChunkSize == 0 then
			RunService.Heartbeat:Wait()
		end
	end

	createWater()
	createSpawn()
end

generateIsland()

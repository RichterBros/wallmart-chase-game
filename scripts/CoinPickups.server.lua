-- CoinPickups
-- PASTE INTO: ServerScriptService (as a Script)
--
-- Spawns a collectible coin at every marker part inside Workspace.Map.CoinSpawns.
-- Shoppers walk into a coin to collect it; it respawns after a delay.
-- Coins are in-round only -- each player's total resets to 0 the moment
-- they're assigned to a team for a new round (RoundManager does this at
-- the start of every round), so no changes to RoundManager are needed.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local roundRoleAssignedEvent = ServerStorage:WaitForChild("RoundRoleAssigned")

-- ========================== CONFIG ==========================
local RESPAWN_DELAY = 20 -- seconds before a collected coin reappears
local COIN_VALUE = 1 -- coins awarded per pickup
local SPIN_SPEED = 60 -- degrees per second

local COIN_TAG = "Coin"

local shopperTeam = Teams:WaitForChild("Shoppers")
local securityTeam = Teams:WaitForChild("Security")

local coinSpawnFolder = workspace.Map:WaitForChild("CoinSpawns")

-- ========================= LEADERSTATS ==========================
-- Coins show in the default Roblox leaderboard (Tab key) -- no custom UI needed.
local function ensureLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local coins = leaderstats:FindFirstChild("Coins")
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Value = 0
		coins.Parent = leaderstats
	end

	return coins
end

Players.PlayerAdded:Connect(function(player)
	ensureLeaderstats(player)
end)

roundRoleAssignedEvent.Event:Connect(function(player)
	if player.Team ~= shopperTeam and player.Team ~= securityTeam then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins then
		coins.Value = 0
	end
end)

-- ========================= COIN SPAWNING ==========================
local function createCoin(spawnPart)
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.4, 2, 2)
	-- A Cylinder's flat faces sit on the local X-axis by default, which
	-- already stands it up like a coin (thickness horizontal, circular face
	-- vertical). Angled 45 degrees around the vertical axis so it reads
	-- better as players walk down an aisle instead of facing edge-on.
	coin.Orientation = Vector3.new(0, 45, 0)
	coin.Position = spawnPart.Position + Vector3.new(0, 1.5, 0)
	coin.Material = Enum.Material.Neon
	coin.Color = Color3.fromRGB(255, 215, 0)
	coin.Anchored = true
	coin.CanCollide = false
	coin:AddTag(COIN_TAG)
	coin.Parent = workspace

	local collected = false

	coin.Touched:Connect(function(hit)
		if collected then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player or player.Team ~= shopperTeam then
			return
		end
		if player:GetAttribute("Frozen") or player:GetAttribute("Out") then
			return -- frozen shoppers can't collect
		end

		collected = true

		local leaderstats = player:FindFirstChild("leaderstats")
		local coinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
		if coinsValue then
			coinsValue.Value += COIN_VALUE
		end

		coin:Destroy()

		task.delay(RESPAWN_DELAY, function()
			if spawnPart.Parent then -- only respawn if the marker still exists
				createCoin(spawnPart)
			end
		end)
	end)
end

for _, spawnPart in coinSpawnFolder:GetChildren() do
	if spawnPart:IsA("BasePart") then
		createCoin(spawnPart)
	end
end

-- ========================= SPIN ==========================
-- Coins only have a yaw (Y-axis) rotation applied, so their local Y axis
-- always matches world up -- spinning around local Y is a clean vertical spin.
RunService.Heartbeat:Connect(function(deltaTime)
	for _, coin in CollectionService:GetTagged(COIN_TAG) do
		coin.CFrame = coin.CFrame * CFrame.Angles(0, math.rad(SPIN_SPEED * deltaTime), 0)
	end
end)

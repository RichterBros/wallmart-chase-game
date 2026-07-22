-- FigurePickups
-- PASTE INTO: ServerScriptService (as a Script)
--
-- PASS 1: places a purchasable placeholder figure at every marker in
-- Workspace.Map.ItemSpawns. A Shopper with enough coins can walk up and
-- buy it -- coins are deducted. No shopping-list restriction yet; that's
-- Pass 2, along with hooking purchases into a per-player list and the exit.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")

local FIGURE_POOL = require(ServerStorage:WaitForChild("FigureData"))

-- ========================== CONFIG ==========================
local RESPAWN_DELAY = 20 -- seconds before a purchased figure reappears

local shopperTeam = Teams:WaitForChild("Shoppers")
local itemSpawnFolder = workspace.Map:WaitForChild("ItemSpawns")

-- ========================= COLLECT EFFECT ==========================
-- A quick poof of small glowing shards that fly outward and shrink away.
-- Built from plain Neon parts (same trick as the coins) instead of a
-- ParticleEmitter, so there's no texture asset to fail to load.
local SPARK_COUNT = 10
local SPARK_COLORS = { Color3.fromRGB(255, 235, 150), Color3.new(1, 1, 1) }

local function spawnSparklePoof(position)
	for i = 1, SPARK_COUNT do
		local spark = Instance.new("Part")
		spark.Shape = Enum.PartType.Ball
		spark.Size = Vector3.new(0.5, 0.5, 0.5)
		spark.Position = position
		spark.Anchored = true
		spark.CanCollide = false
		spark.CanQuery = false
		spark.Material = Enum.Material.Neon
		spark.Color = SPARK_COLORS[(i % #SPARK_COLORS) + 1]
		spark.Parent = workspace

		local direction = Vector3.new(
			math.random(-10, 10),
			math.random(2, 10),
			math.random(-10, 10)
		).Unit
		local targetPosition = position + direction * math.random(3, 6)

		local tween = TweenService:Create(
			spark,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPosition, Size = Vector3.new(0, 0, 0), Transparency = 1 }
		)
		tween.Completed:Connect(function()
			spark:Destroy()
		end)
		tween:Play()
	end
end

-- ========================= FIGURE SPAWNING ==========================
local function createFigure(spawnPart)
	local figureData = FIGURE_POOL[math.random(1, #FIGURE_POOL)]

	local display = Instance.new("Part")
	display.Name = "Figure_" .. figureData.name
	display.Size = Vector3.new(2, 2, 2)
	display.Position = spawnPart.Position + Vector3.new(0, 1.5, 0)
	display.Material = Enum.Material.SmoothPlastic
	display.Color = Color3.fromRGB(255, 105, 180)
	display.Anchored = true
	display.CanCollide = false
	display.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 150, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = display

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = figureData.name .. "\n" .. figureData.price .. " coins"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard

	local purchased = false

	display.Touched:Connect(function(hit)
		if purchased then
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
			return
		end

		local leaderstats = player:FindFirstChild("leaderstats")
		local coins = leaderstats and leaderstats:FindFirstChild("Coins")
		if not coins or coins.Value < figureData.price then
			return -- not enough coins
		end

		purchased = true
		coins.Value -= figureData.price

		-- Check this item off the shopper's list, if it's one they need
		local shoppingList = player:FindFirstChild("ShoppingList")
		local listEntry = shoppingList and shoppingList:FindFirstChild(figureData.name)
		if listEntry then
			listEntry:Destroy()
		end

		spawnSparklePoof(display.Position)
		display:Destroy()

		task.delay(RESPAWN_DELAY, function()
			if spawnPart.Parent then -- only respawn if the marker still exists
				createFigure(spawnPart)
			end
		end)
	end)
end

for _, spawnPart in itemSpawnFolder:GetChildren() do
	if spawnPart:IsA("BasePart") then
		createFigure(spawnPart)
	end
end

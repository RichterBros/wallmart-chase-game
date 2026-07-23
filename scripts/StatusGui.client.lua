-- StatusGui
-- PASTE INTO: StarterGui (as a LocalScript)
--
-- Shows the round status text (from RoundManager) at the top of the screen,
-- plus a firework celebration for the winning team when a round ends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local roundStatus = ReplicatedStorage:WaitForChild("RoundStatus")
local localPlayer = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RoundStatusGui"
screenGui.ResetOnSpawn = false

local label = Instance.new("TextLabel")
label.Name = "StatusLabel"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 8)
label.Size = UDim2.new(0, 420, 0, 40)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.4
label.TextColor3 = Color3.new(1, 1, 1)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.Text = roundStatus.Value
label.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = label

-- ========================= WIN CELEBRATION ==========================
-- Plain GUI circles tweened outward from a burst point (same trick as the
-- figure-purchase sparkle poof) instead of a ParticleEmitter -- no texture
-- asset to fail to load, and it reads fine as a flat firework burst on a 2D
-- screen overlay. Each spark gets a larger, more transparent halo behind it
-- (same color, same tween) to fake a glow/bloom without needing an image.
local BURST_PARTICLE_COUNT = 12
local BURST_COUNT = 8
local SPARK_SIZE = 80 -- pixels; 10x the original 8
local GLOW_SIZE_MULTIPLIER = 2.5 -- glow halo drawn behind each spark, this many times larger

local function spawnFireworkBurst(container)
	local originX = math.random(10, 90) / 100
	local originY = math.random(15, 60) / 100
	local color = Color3.fromHSV(math.random(), 0.85, 1)

	for i = 1, BURST_PARTICLE_COUNT do
		local glow = Instance.new("Frame")
		glow.Size = UDim2.new(0, SPARK_SIZE * GLOW_SIZE_MULTIPLIER, 0, SPARK_SIZE * GLOW_SIZE_MULTIPLIER)
		glow.Position = UDim2.new(originX, 0, originY, 0)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.BackgroundColor3 = color
		glow.BackgroundTransparency = 0.6
		glow.BorderSizePixel = 0
		glow.ZIndex = 1
		glow.Parent = container

		local glowCorner = Instance.new("UICorner")
		glowCorner.CornerRadius = UDim.new(1, 0)
		glowCorner.Parent = glow

		local spark = Instance.new("Frame")
		spark.Size = UDim2.new(0, SPARK_SIZE, 0, SPARK_SIZE)
		spark.Position = UDim2.new(originX, 0, originY, 0)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.BackgroundColor3 = color
		spark.BorderSizePixel = 0
		spark.ZIndex = 2
		spark.Parent = container

		local uiCorner = Instance.new("UICorner")
		uiCorner.CornerRadius = UDim.new(1, 0)
		uiCorner.Parent = spark

		local angle = (i / BURST_PARTICLE_COUNT) * math.pi * 2
		local distance = math.random(250, 450)
		local targetPosition = UDim2.new(
			originX, math.cos(angle) * distance,
			originY, math.sin(angle) * distance
		)

		local sparkTween = TweenService:Create(
			spark,
			TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPosition, Size = UDim2.new(0, SPARK_SIZE * 0.25, 0, SPARK_SIZE * 0.25), BackgroundTransparency = 1 }
		)
		local glowTween = TweenService:Create(
			glow,
			TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = targetPosition,
				Size = UDim2.new(0, SPARK_SIZE * GLOW_SIZE_MULTIPLIER * 0.25, 0, SPARK_SIZE * GLOW_SIZE_MULTIPLIER * 0.25),
				BackgroundTransparency = 1,
			}
		)
		sparkTween.Completed:Connect(function()
			spark:Destroy()
		end)
		glowTween.Completed:Connect(function()
			glow:Destroy()
		end)
		sparkTween:Play()
		glowTween:Play()
	end
end

local function celebrateWin()
	local container = Instance.new("Frame")
	container.Name = "FireworksContainer"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.ZIndex = 10
	container.Parent = screenGui

	task.spawn(function()
		for _ = 1, BURST_COUNT do
			spawnFireworkBurst(container)
			task.wait(math.random(3, 6) / 10)
		end
		task.wait(1)
		container:Destroy()
	end)
end

roundStatus.Changed:Connect(function(newValue)
	label.Text = newValue

	-- Only celebrate for the team that actually won -- e.g. "🛒 Shoppers
	-- win!" contains "Shoppers", which matches the Shoppers team's own name
	local myTeam = localPlayer.Team
	if myTeam and newValue:find("win") and newValue:find(myTeam.Name, 1, true) then
		celebrateWin()
	end
end)

screenGui.Parent = script.Parent -- StarterGui clones this into each player's PlayerGui

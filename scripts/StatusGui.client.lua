-- StatusGui
-- PASTE INTO: StarterGui (as a LocalScript)
--
-- Shows the round status text (from RoundManager) at the top of the screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local roundStatus = ReplicatedStorage:WaitForChild("RoundStatus")

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

roundStatus.Changed:Connect(function(newValue)
	label.Text = newValue
end)

screenGui.Parent = script.Parent -- StarterGui clones this into each player's PlayerGui

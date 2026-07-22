-- SecurityLabel
-- PASTE INTO: ServerScriptService (as a Script)
--
-- Shows a big red "SECURITY" label above the head of any player on the
-- Security team, visible to everyone, so it's easy to tell the chaser
-- apart from shoppers at a glance.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local securityTeam = Teams:WaitForChild("Security")

local function addLabel(character)
	local head = character:WaitForChild("Head")

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SecurityLabel"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "SECURITY"
	label.TextColor3 = Color3.fromRGB(255, 40, 40)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = billboard
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		if player.Team == securityTeam then
			addLabel(character)
		end
	end)
end)

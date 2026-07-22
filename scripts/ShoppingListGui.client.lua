-- ShoppingListGui
-- PASTE INTO: StarterGui (as a LocalScript)
--
-- Shows the local player's remaining shopping list on screen. Updates
-- automatically as items are checked off (their ShoppingList folder entries
-- get destroyed by FigurePickups on a matching purchase), and refreshes
-- cleanly each round when ShoppingList assigns a brand new list.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShoppingListGui"
screenGui.ResetOnSpawn = false

local frame = Instance.new("Frame")
frame.Position = UDim2.new(0, 12, 0, 60)
frame.Size = UDim2.new(0, 220, 0, 150)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BackgroundTransparency = 0.4
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundTransparency = 1
title.Text = "Shopping List"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.Parent = frame

local completeLabel = Instance.new("TextLabel")
completeLabel.Position = UDim2.new(0, 4, 0, 30)
completeLabel.Size = UDim2.new(1, -8, 0, 40)
completeLabel.BackgroundTransparency = 1
completeLabel.Text = "All done! Head to the exit!"
completeLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
completeLabel.Font = Enum.Font.GothamBold
completeLabel.TextScaled = true
completeLabel.TextWrapped = true
completeLabel.Visible = false
completeLabel.Parent = frame

local itemsHolder = Instance.new("Frame")
itemsHolder.Position = UDim2.new(0, 0, 0, 26)
itemsHolder.Size = UDim2.new(1, 0, 1, -26)
itemsHolder.BackgroundTransparency = 1
itemsHolder.Parent = frame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 2)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = itemsHolder

local function refreshCompleteState()
	local remaining = #itemsHolder:GetChildren() - 1 -- exclude the UIListLayout
	completeLabel.Visible = remaining <= 0
end

local function addItemLabel(item)
	local label = Instance.new("TextLabel")
	label.Name = item.Name
	label.Size = UDim2.new(1, -8, 0, 20)
	label.Position = UDim2.new(0, 4, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "- " .. item.Name
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = itemsHolder
	refreshCompleteState()
end

local function clearItemLabels()
	for _, label in itemsHolder:GetChildren() do
		if label:IsA("TextLabel") then
			label:Destroy()
		end
	end
end

local function watchList(list)
	clearItemLabels()
	for _, item in list:GetChildren() do
		addItemLabel(item)
	end
	refreshCompleteState()

	list.ChildAdded:Connect(addItemLabel)
	list.ChildRemoved:Connect(function(item)
		local label = itemsHolder:FindFirstChild(item.Name)
		if label then
			label:Destroy()
		end
		refreshCompleteState()
	end)
end

local existingList = player:FindFirstChild("ShoppingList")
if existingList then
	watchList(existingList)
end

player.ChildAdded:Connect(function(child)
	if child.Name == "ShoppingList" then
		watchList(child)
	end
end)

screenGui.Parent = player:WaitForChild("PlayerGui")

-- ShoppingList
-- PASTE INTO: ServerScriptService (as a Script)
--
-- Assigns each Shopper a random list of required figures at the start of
-- every round (the moment RoundManager puts them on the Shoppers team).
-- FigurePickups checks items off this list on a matching purchase.
-- ExitZone only lets a Shopper escape once the list is empty.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ServerStorage = game:GetService("ServerStorage")

local FigureData = require(ServerStorage:WaitForChild("FigureData"))
local roundRoleAssignedEvent = ServerStorage:WaitForChild("RoundRoleAssigned")

-- ========================== CONFIG ==========================
local LIST_SIZE = 3 -- items required per shopper per round

local shopperTeam = Teams:WaitForChild("Shoppers")

local function assignShoppingList(player)
	local existing = player:FindFirstChild("ShoppingList")
	if existing then
		existing:Destroy()
	end

	local list = Instance.new("Folder")
	list.Name = "ShoppingList"
	list.Parent = player

	-- Shuffle a copy of the pool, then take the first LIST_SIZE names
	local pool = table.clone(FigureData)
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	for i = 1, math.min(LIST_SIZE, #pool) do
		local marker = Instance.new("BoolValue")
		marker.Name = pool[i].name
		marker.Parent = list
	end
end

roundRoleAssignedEvent.Event:Connect(function(player)
	if player.Team == shopperTeam then
		assignShoppingList(player)
	end
end)

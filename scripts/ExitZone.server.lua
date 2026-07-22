-- ExitZone
-- PASTE INTO: ServerScriptService (as a Script)
--
-- When a Shopper with a completed shopping list touches the ExitZone part,
-- marks them Escaped (RoundManager already watches this attribute for the
-- win condition -- no changes needed there) and moves them to the lobby,
-- out of the chase.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local shopperTeam = Teams:WaitForChild("Shoppers")
local exitZone = workspace.Map:WaitForChild("ExitZone")
local lobbySpawn = workspace.Lobby:WaitForChild("LobbySpawn")

exitZone.Touched:Connect(function(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player or player.Team ~= shopperTeam then
		return
	end
	if player:GetAttribute("Frozen") or player:GetAttribute("Out") or player:GetAttribute("Escaped") then
		return
	end

	local shoppingList = player:FindFirstChild("ShoppingList")
	if shoppingList and #shoppingList:GetChildren() > 0 then
		return -- list not complete yet
	end

	player:SetAttribute("Escaped", true)

	if character.PrimaryPart then
		character:PivotTo(lobbySpawn.CFrame + Vector3.new(0, 4, 0))
	end
end)

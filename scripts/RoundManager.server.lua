-- RoundManager
-- PASTE INTO: ServerScriptService (as a Script)
--
-- Runs the core game loop: wait for players -> intermission -> assign roles
-- -> round -> announce winner -> back to lobby -> repeat.
--
-- Expects this Workspace structure (from the graybox step):
--   Workspace.Map.ShopperSpawns  (Folder of Parts)
--   Workspace.Map.ChaserSpawn    (Part — optional; falls back to shopper spawns)
--   Workspace.Lobby.LobbySpawn   (SpawnLocation, Neutral = true)
--
-- Later systems (freeze, collection) integrate via player attributes:
--   "Frozen"  (bool) — set by the tag/freeze script
--   "Out"     (bool) — set when a frozen player's rescue timer expires
--   "Escaped" (bool) — set by the checkout/exit script
-- ...or by firing ServerStorage.EndRound with "Shoppers" or "Security".

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- ========================== CONFIG ==========================
local MIN_PLAYERS = 1
local INTERMISSION_TIME = 15 -- seconds in lobby between rounds
local ROUND_TIME = 240 -- 4 minutes; tune in playtests
local WINNER_DISPLAY_TIME = 5

local function chaserCountFor(playerCount)
	-- 2-6 players -> 1 chaser, 7-10 -> 2 (see DESIGN.md)
	if playerCount >= 7 then
		return 2
	end
	return 1
end

-- ========================== SETUP ===========================
local function makeTeam(name, brickColor, autoAssignable)
	local team = Teams:FindFirstChild(name)
	if not team then
		team = Instance.new("Team")
		team.Name = name
		team.TeamColor = brickColor
		team.AutoAssignable = autoAssignable
		team.Parent = Teams
	end
	return team
end

local lobbyTeam = makeTeam("Lobby", BrickColor.new("Medium stone grey"), true)
local shopperTeam = makeTeam("Shoppers", BrickColor.new("Bright blue"), false)
local securityTeam = makeTeam("Security", BrickColor.new("Really red"), false)

-- Status text that the client GUI displays
local roundStatus = Instance.new("StringValue")
roundStatus.Name = "RoundStatus"
roundStatus.Value = "Waiting for players…"
roundStatus.Parent = ReplicatedStorage

-- Future systems fire this to end the round early:
--   ServerStorage.EndRound:Fire("Shoppers")  or  :Fire("Security")
local endRoundEvent = Instance.new("BindableEvent")
endRoundEvent.Name = "EndRound"
endRoundEvent.Parent = ServerStorage

-- AIChaser listens for these to spawn/despawn its NPC guard for solo rounds
local aiChaserSpawnEvent = Instance.new("BindableEvent")
aiChaserSpawnEvent.Name = "AIChaserSpawn"
aiChaserSpawnEvent.Parent = ServerStorage

local aiChaserDespawnEvent = Instance.new("BindableEvent")
aiChaserDespawnEvent.Name = "AIChaserDespawn"
aiChaserDespawnEvent.Parent = ServerStorage

-- Fired once per player every round, right after their Team is finalized.
-- Other systems (coins, shopping list) listen to this instead of a Team
-- "changed" signal, since a changed-signal never fires if a player happens
-- to already be on the same team as last round (e.g. Shoppers twice in a row)
local roundRoleAssignedEvent = Instance.new("BindableEvent")
roundRoleAssignedEvent.Name = "RoundRoleAssigned"
roundRoleAssignedEvent.Parent = ServerStorage

local map = workspace:WaitForChild("Map")
local shopperSpawnFolder = map:WaitForChild("ShopperSpawns")
local chaserSpawn = map:FindFirstChild("ChaserSpawn")

local rng = Random.new()

-- ========================= HELPERS ==========================
local function resetRoundAttributes(player)
	player:SetAttribute("Frozen", false)
	player:SetAttribute("Out", false)
	player:SetAttribute("Escaped", false)
end

local function spawnPlayerAt(player, spawnPart)
	task.spawn(function()
		player:LoadCharacter()
		local character = player.Character or player.CharacterAdded:Wait()
		character:PivotTo(spawnPart.CFrame + Vector3.new(0, 4, 0))
	end)
end

-- Returns (free shoppers, escaped shoppers). "Free" = still catchable.
local function getShopperStatus()
	local free, escaped = {}, {}
	for _, player in shopperTeam:GetPlayers() do
		if player:GetAttribute("Escaped") then
			table.insert(escaped, player)
		elseif not player:GetAttribute("Frozen") and not player:GetAttribute("Out") then
			table.insert(free, player)
		end
	end
	return free, escaped
end

-- ========================== ROUND ===========================
local function runRound()
	local players = Players:GetPlayers()

	-- Always start from a clean slate; despawning when nothing is active is a no-op
	aiChaserDespawnEvent:Fire()

	-- Solo play: the lone human is always the Shopper, chased by the AI --
	-- never assigned to Security themselves (see DESIGN.md's AI chaser fallback)
	local useAIChaser = (#players == 1)

	if useAIChaser then
		resetRoundAttributes(players[1])
		players[1].Team = shopperTeam
		aiChaserSpawnEvent:Fire()
	else
		-- Shuffle so chaser picks are random
		for i = #players, 2, -1 do
			local j = rng:NextInteger(1, i)
			players[i], players[j] = players[j], players[i]
		end

		local numChasers = chaserCountFor(#players)
		for i, player in players do
			resetRoundAttributes(player)
			if i <= numChasers then
				player.Team = securityTeam
			else
				player.Team = shopperTeam
			end
		end
	end

	-- Let coins/shopping-list/etc. know roles are final for this round
	for _, player in players do
		roundRoleAssignedEvent:Fire(player)
	end

	-- Spawn everyone into the store
	local shopperSpawns = shopperSpawnFolder:GetChildren()
	for _, player in players do
		local spawnPart
		if player.Team == securityTeam and chaserSpawn then
			spawnPart = chaserSpawn
		else
			spawnPart = shopperSpawns[rng:NextInteger(1, #shopperSpawns)]
		end
		spawnPlayerAt(player, spawnPart)
	end

	-- Round countdown + win checks (once per second)
	local winner = nil
	local earlyEndConn = endRoundEvent.Event:Connect(function(team)
		winner = team
	end)

	for t = ROUND_TIME, 1, -1 do
		local free, escaped = getShopperStatus()

		if winner then
			break -- another system ended the round early
		elseif not useAIChaser and #securityTeam:GetPlayers() == 0 then
			winner = "Shoppers" -- chaser(s) left the game
		elseif #shopperTeam:GetPlayers() == 0 then
			winner = "Security" -- all shoppers left the game
		elseif #free == 0 then
			-- Nobody left to catch: shoppers win if anyone escaped,
			-- otherwise Security froze them all
			winner = (#escaped > 0) and "Shoppers" or "Security"
		end
		if winner then
			break
		end

		roundStatus.Value = string.format(
			"🕒 %d:%02d  |  Shoppers free: %d",
			math.floor(t / 60), t % 60, #free
		)
		task.wait(1)
	end

	earlyEndConn:Disconnect()

	if useAIChaser then
		aiChaserDespawnEvent:Fire()
	end

	-- Timer ran out with shoppers still free -> shoppers survive -> they win
	return winner or "Shoppers"
end

-- ======================== MAIN LOOP =========================
while true do
	-- Wait until there are enough players
	while #Players:GetPlayers() < MIN_PLAYERS do
		roundStatus.Value = "Waiting for players…"
		task.wait(1)
	end

	-- Intermission countdown (bail back to waiting if someone leaves)
	local enoughPlayers = true
	for t = INTERMISSION_TIME, 1, -1 do
		if #Players:GetPlayers() < MIN_PLAYERS then
			enoughPlayers = false
			break
		end
		roundStatus.Value = "Round starting in " .. t .. "…"
		task.wait(1)
	end
	if not enoughPlayers then
		continue
	end

	local winner = runRound()

	if winner == "Shoppers" then
		roundStatus.Value = "🛒 Shoppers win!"
	else
		roundStatus.Value = "🚨 Security wins!"
	end
	task.wait(WINNER_DISPLAY_TIME)

	-- Everyone back to the lobby
	for _, player in Players:GetPlayers() do
		player.Team = lobbyTeam
		resetRoundAttributes(player)
		task.spawn(function()
			player:LoadCharacter() -- respawns at the neutral LobbySpawn
		end)
	end
end

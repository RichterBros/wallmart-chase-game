-- TagFreeze
-- PASTE INTO: ServerScriptService (as a Script)
--
-- Handles the core chase mechanic:
--   - Security touching a Shopper freezes them in place
--   - A frozen shopper has a rescue timer (25s) before they're marked "Out"
--   - A teammate can stand near a frozen shopper for a 3s channel to rescue them
--
-- Reads/writes the same player attributes RoundManager already watches:
--   Frozen (bool), Out (bool) -- set here, RoundManager reacts to them
--
-- Depends on RoundManager already existing (for the Teams and round loop).

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

-- ========================== CONFIG ==========================
local RESCUE_CHANNEL_TIME = 3 -- seconds a teammate must stand near a frozen shopper
local RESCUE_TIMEOUT = 25 -- seconds before a frozen shopper is marked "Out"
local RESCUE_RANGE = 6 -- studs; how close a rescuer must stay during the channel
local CART_SEAT_NAME = "HoverCartSeat" -- must match HoverCart.server.lua's SEAT_NAME -- riding it makes a shopper immune to tags

local shopperTeam = Teams:WaitForChild("Shoppers")
local securityTeam = Teams:WaitForChild("Security")

-- Per-frozen-player state, keyed by the frozen Player
-- { rescueDeadline = number, rescuer = Player | nil, rescueStarted = number | nil }
local frozenState = {}

-- ========================= HELPERS ==========================
local FROZEN_COLOR = Color3.fromRGB(150, 200, 255)

local function setFrozenLook(character, frozen)
	-- Simple visual cue: frozen shoppers turn completely pale blue and can't move
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = frozen and 0 or 16
		humanoid.JumpPower = frozen and 0 or 50
	end

	-- Body parts + accessories: remember each part's real color so it can be
	-- restored exactly on rescue, instead of staying tinted forever
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			if frozen then
				part:SetAttribute("OriginalColor", part.Color)
				part.Color = FROZEN_COLOR
			else
				local original = part:GetAttribute("OriginalColor")
				if original then
					part.Color = original
				end
			end
		end
	end

	-- Shirt/Pants are texture overlays, not part colors -- clear them while
	-- frozen so the tint actually shows, then restore the exact texture on rescue
	local shirt = character:FindFirstChildOfClass("Shirt")
	if shirt then
		if frozen then
			shirt:SetAttribute("OriginalTemplate", shirt.ShirtTemplate)
			shirt.ShirtTemplate = ""
		else
			shirt.ShirtTemplate = shirt:GetAttribute("OriginalTemplate") or shirt.ShirtTemplate
		end
	end

	local pants = character:FindFirstChildOfClass("Pants")
	if pants then
		if frozen then
			pants:SetAttribute("OriginalTemplate", pants.PantsTemplate)
			pants.PantsTemplate = ""
		else
			pants.PantsTemplate = pants:GetAttribute("OriginalTemplate") or pants.PantsTemplate
		end
	end
end

-- ==================== RAGDOLL (generic technique) ====================
-- Converts every Motor6D joint to a physics-driven BallSocketConstraint so
-- the character goes limp instead of staying rigidly upright -- the
-- standard Roblox ragdoll technique. PlatformStand disables the humanoid's
-- own upright-balancing controller so it doesn't fight the physics.
-- Exposed generically below (RagdollCharacterEvent) for AIChaser to ragdoll
-- a security guard that gets rammed by an occupied HoverCart.
local RAGDOLL_ATTACHMENT_NAME = "RagdollAttachment"
local RAGDOLL_SOCKET_NAME = "RagdollSocket"

local function ragdollCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
	end

	for _, joint in character:GetDescendants() do
		if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 and joint.Enabled then
			local a0 = Instance.new("Attachment")
			a0.Name = RAGDOLL_ATTACHMENT_NAME
			a0.CFrame = joint.C0
			a0.Parent = joint.Part0

			local a1 = Instance.new("Attachment")
			a1.Name = RAGDOLL_ATTACHMENT_NAME
			a1.CFrame = joint.C1
			a1.Parent = joint.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = RAGDOLL_SOCKET_NAME
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.Parent = joint.Part0

			joint.Enabled = false
		end
	end
end

local function unragdollCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end

	for _, joint in character:GetDescendants() do
		if joint:IsA("Motor6D") and not joint.Enabled then
			joint.Enabled = true
		end
	end

	for _, descendant in character:GetDescendants() do
		if descendant.Name == RAGDOLL_SOCKET_NAME or descendant.Name == RAGDOLL_ATTACHMENT_NAME then
			descendant:Destroy()
		end
	end
end

local ICE_SHELL_NAME = "IceShell"

local function setIceShell(character, frozen)
	local existing = character:FindFirstChild(ICE_SHELL_NAME)
	if existing then
		existing:Destroy()
	end
	if not frozen then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	-- Size/position the shell to the character's actual bounds so it fits
	-- regardless of avatar height/build
	local boundsCFrame, boundsSize = character:GetBoundingBox()

	local shell = Instance.new("Part")
	shell.Name = ICE_SHELL_NAME
	shell.Size = boundsSize + Vector3.new(1, 1, 1)
	shell.CFrame = boundsCFrame
	shell.Material = Enum.Material.Ice
	shell.Color = Color3.fromRGB(200, 230, 255)
	shell.Transparency = 0.35
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = shell
	weld.Part1 = humanoidRootPart
	weld.Parent = shell
end

local function freezeShopper(player)
	if player:GetAttribute("Frozen") or player:GetAttribute("Out") then
		return -- already frozen or already out; ignore repeat tags
	end
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart and humanoid.SeatPart.Name == CART_SEAT_NAME then
		return -- riding the HoverCart makes a shopper immune to being tagged
	end

	player:SetAttribute("Frozen", true)
	frozenState[player] = {
		rescueDeadline = os.clock() + RESCUE_TIMEOUT,
	}
	setFrozenLook(character, true)
	setIceShell(character, true)
end

local function unfreezeShopper(player)
	local character = player.Character
	if character then
		setFrozenLook(character, false)
		setIceShell(character, false)
	end
	player:SetAttribute("Frozen", false)
	frozenState[player] = nil
end

local function markOut(player)
	local character = player.Character
	if character then
		-- stays visually frozen
		setFrozenLook(character, true)
		setIceShell(character, true)
	end
	player:SetAttribute("Frozen", false)
	player:SetAttribute("Out", true)
	frozenState[player] = nil
end

-- ==================== TAG DETECTION (Security touch) ====================
local function onCharacterAdded(character, player)
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

	humanoidRootPart.Touched:Connect(function(hit)
		if player.Team ~= securityTeam then
			return -- only Security tags people
		end
		local otherCharacter = hit:FindFirstAncestorOfClass("Model")
		if not otherCharacter then
			return
		end
		local otherPlayer = Players:GetPlayerFromCharacter(otherCharacter)
		if not otherPlayer or otherPlayer.Team ~= shopperTeam then
			return
		end
		if otherPlayer:GetAttribute("Escaped") then
			return -- already escaped, can't be tagged
		end
		freezeShopper(otherPlayer)
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(character, player)
	end)
end)

-- ==================== ROUND RESET ====================
-- If a round ends (timeout, all shoppers escaped, etc.) while a player is
-- still frozen, their frozenState entry never gets cleared by unfreeze/markOut.
-- Its rescueDeadline is a stale os.clock() timestamp from the previous round,
-- which is already in the past by the time the next round starts. Left alone,
-- the very next Heartbeat tick below sees "deadline passed" and calls
-- markOut() on the player's brand-new character -- freezing them solid with
-- no chaser contact at all. Clearing here, once per player at the start of
-- every round, guarantees a clean slate no matter how the last round ended.
local roundRoleAssignedEvent = ServerStorage:WaitForChild("RoundRoleAssigned")
roundRoleAssignedEvent.Event:Connect(function(player)
	frozenState[player] = nil
end)

-- ==================== AI CHASER HOOK ====================
-- AIChaser isn't a real Player, so it can't go through onCharacterAdded
-- above. It fires this event instead, reusing the exact same freeze logic
-- (ice shell, color tint, rescue timer) rather than duplicating any of it.
local freezeShopperEvent = Instance.new("BindableEvent")
freezeShopperEvent.Name = "FreezeShopperEvent"
freezeShopperEvent.Parent = ServerStorage

freezeShopperEvent.Event:Connect(function(player)
	freezeShopper(player)
end)

-- ==================== GENERIC RAGDOLL HOOK ====================
-- Lets other systems (e.g. AIChaser, when a security guard gets bumped by an
-- occupied HoverCart) reuse this same ragdoll technique on ANY character --
-- player or NPC alike -- without duplicating the Motor6D/BallSocketConstraint
-- conversion code.
local ragdollCharacterEvent = Instance.new("BindableEvent")
ragdollCharacterEvent.Name = "RagdollCharacterEvent"
ragdollCharacterEvent.Parent = ServerStorage

ragdollCharacterEvent.Event:Connect(function(character, duration)
	ragdollCharacter(character)
	task.delay(duration, function()
		if character.Parent then
			unragdollCharacter(character)
		end
	end)
end)

-- ==================== RESCUE CHANNEL (proximity-based) ====================
-- Every heartbeat: for each frozen shopper, check if a teammate is standing
-- close enough to keep channeling the rescue. If the channel completes,
-- unfreeze. If the rescuer leaves range, the channel resets (must restart).
RunService.Heartbeat:Connect(function()
	for frozenPlayer, state in frozenState do
		local frozenCharacter = frozenPlayer.Character
		if not frozenCharacter or not frozenCharacter.PrimaryPart then
			continue
		end

		-- Rescue timeout check first -- guarantees chaser progress
		if os.clock() >= state.rescueDeadline then
			markOut(frozenPlayer)
			continue
		end

		-- Find a nearby, free shopper teammate to act as rescuer
		local rescuer = nil
		for _, other in shopperTeam:GetPlayers() do
			if other == frozenPlayer then
				continue
			end
			if other:GetAttribute("Frozen") or other:GetAttribute("Out") or other:GetAttribute("Escaped") then
				continue
			end
			local otherCharacter = other.Character
			if not otherCharacter or not otherCharacter.PrimaryPart then
				continue
			end
			local distance = (otherCharacter.PrimaryPart.Position - frozenCharacter.PrimaryPart.Position).Magnitude
			if distance <= RESCUE_RANGE then
				rescuer = other
				break
			end
		end

		if rescuer then
			if state.rescuer ~= rescuer then
				-- New or restarted channel
				state.rescuer = rescuer
				state.rescueStarted = os.clock()
			elseif os.clock() - state.rescueStarted >= RESCUE_CHANNEL_TIME then
				unfreezeShopper(frozenPlayer)
			end
		else
			-- No one in range; channel resets
			state.rescuer = nil
			state.rescueStarted = nil
		end
	end
end)

-- ==================== CLEANUP ====================
Players.PlayerRemoving:Connect(function(player)
	frozenState[player] = nil
end)

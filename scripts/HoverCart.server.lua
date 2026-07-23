-- HoverCart
-- PASTE INTO: ServerScriptService (as a Script)
--
-- Shopper-only "hoveround" cart: press E to hop in, press E again to hop out
-- (ProximityPrompt's default key is already E). Hovers at a fixed height
-- above the floor and drives off the VehicleSeat's Throttle/Steer, which
-- Roblox fills in automatically from the seated player's WASD input. Getting
-- tagged while riding hands off to TagFreeze's cart-eject/ragdoll path
-- instead of the normal standing freeze (see TagFreeze.server.lua).
--
-- SETUP: put your cart model(s) anywhere under Workspace.Map, each with an
-- unanchored VehicleSeat renamed to "HoverCartSeat". Any decorative body
-- parts should be WeldConstraint'd to that seat so they move together with it.

local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

-- ========================== CONFIG ==========================
local CART_SPEED = 35 -- studs/sec top speed
local TURN_SPEED = 3 -- radians/sec at full steer
local HOVER_HEIGHT = 6 -- studs the cart floats above the floor (tall enough to clear a seated character's dangling legs, not just the chassis)
local HOVER_RAY_LENGTH = 20 -- studs; how far down to look for the floor
local HOVER_SPRING = 8 -- higher = firmer air cushion, lower = softer/sinkier
local HOVER_DAMPING = 4 -- higher = settles faster, lower = more bounce/cushion feel
local TURN_SMOOTHING = 6 -- higher = reaches full turn rate faster, lower = floatier/smoother
local ACCEL_SMOOTHING = 3 -- higher = reaches top speed faster, lower = more momentum/coasting
local SEAT_NAME = "HoverCartSeat"

local shopperTeam = Teams:WaitForChild("Shoppers")
local roundRoleAssignedEvent = ServerStorage:WaitForChild("RoundRoleAssigned")

-- ========================= PER-CART SETUP ==========================
local function setupCart(vehicleSeat)
	-- Roblox normally auto-assigns physics ownership of a seat to whoever's
	-- riding it, for responsiveness. But this script also drives the cart's
	-- velocity from the SERVER every frame -- with both the rider's client
	-- and the server fighting over the same physics, they periodically
	-- reconcile/correct each other, which is the split-second stutter.
	-- Locking ownership to the server (nil) makes the server the sole
	-- authority, eliminating that tug-of-war.
	vehicleSeat:SetNetworkOwner(nil)

	-- Carts are unanchored physics objects with no idea a round even exists --
	-- left alone, one just stays wherever it was last driven/knocked to
	-- forever. RoundManager fires this once per player at the start of every
	-- round (the same signal coins/shopping lists reset from), so snap the
	-- cart back to its original spot then too.
	local homeCFrame = vehicleSeat.CFrame
	roundRoleAssignedEvent.Event:Connect(function()
		if vehicleSeat.Occupant then
			vehicleSeat.Occupant.Sit = false
		end
		vehicleSeat.CFrame = homeCFrame
		vehicleSeat.AssemblyLinearVelocity = Vector3.new()
		vehicleSeat.AssemblyAngularVelocity = Vector3.new()
	end)

	local prompt = vehicleSeat:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Enter Cart"
		prompt.ObjectText = "Hover Cart"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 8
		prompt.Parent = vehicleSeat
	end

	prompt.Triggered:Connect(function(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		if humanoid.SeatPart == vehicleSeat then
			humanoid.Sit = false -- already riding this cart -- E exits
			return
		end

		if player.Team ~= shopperTeam then
			return -- Security/Lobby can't ride
		end
		if player:GetAttribute("Frozen") or player:GetAttribute("Out") then
			return -- can't hop in while frozen/out
		end

		vehicleSeat:Sit(humanoid)
	end)

	-- Defense in depth: if anyone that isn't a Shopper ends up seated anyway
	-- (edge case, e.g. a mid-round team change), kick them off immediately.
	vehicleSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = vehicleSeat.Occupant
		if not occupant then
			return
		end
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		if not player or player.Team ~= shopperTeam then
			occupant.Sit = false
		end
	end)

	-- Hover runs ALL the time (empty or occupied) -- otherwise an empty cart
	-- has nothing counteracting gravity and just falls to the floor and sits
	-- there until someone hops in. Only the actual driving (Throttle/Steer)
	-- needs an occupant; with nobody seated they ease back down to 0 instead
	-- of cutting off abruptly, so the cart settles rather than jerking to a stop.
	local currentTurnRate = 0
	local currentSpeed = 0
	local currentVerticalVelocity = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		local cframe = vehicleSeat.CFrame
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { vehicleSeat.Parent }

		local result = workspace:Raycast(cframe.Position, Vector3.new(0, -HOVER_RAY_LENGTH, 0), raycastParams)
		local targetVerticalVelocity = 0
		if result then
			local currentHeight = cframe.Position.Y - result.Position.Y
			targetVerticalVelocity = (HOVER_HEIGHT - currentHeight) * HOVER_SPRING
		end
		-- Damping: ease toward the spring's target instead of snapping straight
		-- to it every frame -- that instant snap is what made it feel like a
		-- rigid mechanical lock instead of a cushion of air.
		currentVerticalVelocity += (targetVerticalVelocity - currentVerticalVelocity) * math.min(HOVER_DAMPING * deltaTime, 1)
		local verticalVelocity = currentVerticalVelocity

		-- Ease toward the target speed/turn rate instead of snapping to them
		-- instantly -- that instant snap on press/release is what made the
		-- cart feel weightless. Easing gives it momentum: it ramps up to
		-- speed, coasts a bit on release, and turns don't happen on a dime.
		local occupant = vehicleSeat.Occupant
		local targetSpeed = occupant and (vehicleSeat.Throttle * CART_SPEED) or 0
		currentSpeed += (targetSpeed - currentSpeed) * math.min(ACCEL_SMOOTHING * deltaTime, 1)

		local targetTurnRate = occupant and (-vehicleSeat.Steer * TURN_SPEED) or 0
		currentTurnRate += (targetTurnRate - currentTurnRate) * math.min(TURN_SMOOTHING * deltaTime, 1)

		local horizontalVelocity = cframe.LookVector * currentSpeed

		vehicleSeat.AssemblyLinearVelocity = Vector3.new(horizontalVelocity.X, verticalVelocity, horizontalVelocity.Z)
		vehicleSeat.AssemblyAngularVelocity = Vector3.new(0, currentTurnRate, 0)
	end)
end

for _, descendant in workspace.Map:GetDescendants() do
	if descendant:IsA("VehicleSeat") and descendant.Name == SEAT_NAME then
		setupCart(descendant)
	end
end

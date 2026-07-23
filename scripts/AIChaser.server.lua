-- AIChaser
-- PASTE INTO: ServerScriptService (as a Script)
--
-- Computer-controlled Security guard(s) for solo play. RoundManager fires
-- AIChaserSpawn at the start of any round with exactly one human player
-- (that player becomes the lone Shopper) and AIChaserDespawn once the round
-- ends. Movement is intentionally simple -- wander until a free shopper
-- comes within range, then path toward them and freeze on contact.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

-- ========================== CONFIG ==========================
-- Number of AI guards is NOT set here -- it's however many Parts you put
-- inside Workspace.Map.AIChaserSpawns, each guard spawning at its own point.
local DETECT_RANGE = 65 -- larger awareness radius for more aggressive detection
local LOSE_RANGE = 110 -- stay committed after spotting a shopper
local WALK_SPEED = 18
local CHASE_RETARGET_INTERVAL = 0.15 -- frequent steering updates while chasing
local PATROL_RETARGET_INTERVAL = 0.55 -- slower updates while wandering
local DIRECT_CHASE_RANGE = 45 -- use smooth direct pursuit when the shopper is visible
local PREDICTION_TIME = 0.35 -- aim ahead of a moving shopper
local PATH_TARGET_MOVE_THRESHOLD = 5 -- do not rebuild nearly identical paths
local WAYPOINT_REACHED_DISTANCE = 3.5 -- change waypoints before fully stopping
local STUCK_DISTANCE_THRESHOLD = 0.75
local STUCK_TICKS_THRESHOLD = 8
local CART_SEAT_NAME = "HoverCartSeat" -- must match HoverCart.server.lua's SEAT_NAME
local CART_RAM_DISTANCE = 12 -- studs; how close an occupied cart must get to a guard to ragdoll them
local CART_RAGDOLL_DURATION = 10 -- seconds a guard ragdolls after being hit by an occupied HoverCart
local CART_LAUNCH_VELOCITY_MULTIPLIER = 1.75 -- how much of the cart's own velocity carries into the launch
local CART_LAUNCH_UPWARD_POP = { 25, 40 } -- studs/sec; random upward pop range for a dramatic launch

local shopperTeam = Teams:WaitForChild("Shoppers")

-- Wander radius auto-scales to the Map's footprint (computed once at server
-- start) instead of a hardcoded stud value -- previously a fixed 40 studs,
-- which silently kept guards boxed into the old floor's dimensions after
-- resizing the map. Clamped to a sane range: each guard only needs a LOCAL
-- patrol area around its own AIChaserSpawns point -- map-wide coverage
-- already comes from spreading multiple spawn points around the map, not
-- from any single guard wandering the entire store (that made guards spend
-- most of their time far from wherever the player actually was, and long
-- cross-map routes gave pathfinding more chances to hit trouble spots).
-- Computed by hand (rather than Model:GetExtentsSize()) since Map is a
-- Folder, not a Model, and Folders don't have that method.
local function getContainerRadius(container)
	local minPoint, maxPoint
	for _, part in container:GetDescendants() do
		if part:IsA("BasePart") then
			local half = part.Size / 2
			local partMin = part.Position - half
			local partMax = part.Position + half
			if not minPoint then
				minPoint, maxPoint = partMin, partMax
			else
				minPoint = Vector3.new(
					math.min(minPoint.X, partMin.X),
					math.min(minPoint.Y, partMin.Y),
					math.min(minPoint.Z, partMin.Z)
				)
				maxPoint = Vector3.new(
					math.max(maxPoint.X, partMax.X),
					math.max(maxPoint.Y, partMax.Y),
					math.max(maxPoint.Z, partMax.Z)
				)
			end
		end
	end
	if not minPoint then
		return 40 -- fallback if the map somehow has no parts yet
	end
	local size = maxPoint - minPoint
	return math.max(size.X, size.Z) / 2
end

local WANDER_RADIUS = math.clamp(getContainerRadius(workspace.Map), 20, 35)

-- Prefer a dedicated AIChaserSpawns folder (Parts) so each guard gets its own
-- starting point -- falls back to the single human-Security ChaserSpawn part
-- (still used by RoundManager for human Security) if that folder doesn't
-- exist yet, so this keeps working before it's added.
local chaserSpawnPoints = {}
local aiChaserSpawnFolder = workspace.Map:FindFirstChild("AIChaserSpawns")
if aiChaserSpawnFolder then
	for _, part in aiChaserSpawnFolder:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(chaserSpawnPoints, part)
		end
	end
end
if #chaserSpawnPoints == 0 then
	table.insert(chaserSpawnPoints, workspace.Map:WaitForChild("ChaserSpawn"))
end

-- Collected once at server start -- carts are static level geometry, same
-- assumption as chaserSpawnPoints above. Used for the distance-based cart-ram
-- check (see ragdollGuardFromCart) instead of a physics Touched event, which
-- has inherent timing slop (contact generation, step size) that made the
-- guard visibly clip into the cart before the launch kicked in.
local cartSeats = {}
for _, descendant in workspace.Map:GetDescendants() do
	if descendant:IsA("VehicleSeat") and descendant.Name == CART_SEAT_NAME then
		table.insert(cartSeats, descendant)
	end
end

local spawnEvent = ServerStorage:WaitForChild("AIChaserSpawn")
local despawnEvent = ServerStorage:WaitForChild("AIChaserDespawn")
local freezeShopperEvent = ServerStorage:WaitForChild("FreezeShopperEvent")
local ragdollCharacterEvent = ServerStorage:WaitForChild("RagdollCharacterEvent")

local activeNPCs = {}
local activeToken = 0 -- bumped on despawn so any running wander loop stops itself

-- ========================= HELPERS ==========================
-- Horizontal-only distance: guards can spawn on elevated platforms, and a
-- straight-line 3D distance would let that height gap silently eat most of
-- DETECT_RANGE, making a guard "barely" notice a shopper standing right below it.
local function horizontalDistance(a, b)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function hasLineOfSight(npc, targetCharacter)
	local rootPart = npc.PrimaryPart
	local targetRoot = targetCharacter and targetCharacter.PrimaryPart
	if not rootPart or not targetRoot then
		return false
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { npc }
	rayParams.IgnoreWater = true

	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local destination = targetRoot.Position + Vector3.new(0, 1.5, 0)
	local result = workspace:Raycast(origin, destination - origin, rayParams)

	return not result or result.Instance:IsDescendantOf(targetCharacter)
end

local function getPredictedPosition(targetRoot)
	local velocity = targetRoot.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	return targetRoot.Position + horizontalVelocity * PREDICTION_TIME
end

local function getNearestFreeShopper(fromPosition)
	local nearest, nearestDistance = nil, math.huge
	for _, shopper in shopperTeam:GetPlayers() do
		if shopper:GetAttribute("Frozen") or shopper:GetAttribute("Out") or shopper:GetAttribute("Escaped") then
			continue
		end
		local character = shopper.Character
		if not character or not character.PrimaryPart then
			continue
		end
		local distance = horizontalDistance(character.PrimaryPart.Position, fromPosition)
		if distance < nearestDistance then
			nearest = shopper
			nearestDistance = distance
		end
	end
	return nearest, nearestDistance
end

-- Picks a random point within WANDER_RADIUS of the guard's own spawn point,
-- then raycasts straight down to confirm it actually lands on flat floor --
-- rejects points that miss the floor entirely or hit a steep slope/wall, so
-- a generous wander radius never sends a guard wandering into a void off the
-- edge of the map. Falls back to the spawn point itself if nothing valid is
-- found nearby (e.g. a very cramped map).
local function randomWanderPoint(spawnPart)
	for _attempt = 1, 8 do
		local angle = math.random() * math.pi * 2
		-- sqrt: radius sampled uniformly by AREA, not by distance -- otherwise
		-- points cluster near the center instead of covering the full map
		local radius = math.sqrt(math.random()) * WANDER_RADIUS
		local candidate = spawnPart.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

		local origin = Vector3.new(candidate.X, spawnPart.Position.Y + 20, candidate.Z)
		local result = workspace:Raycast(origin, Vector3.new(0, -200, 0))
		if result and result.Normal:Dot(Vector3.new(0, 1, 0)) > 0.7 then
			return result.Position
		end
	end
	return spawnPart.Position
end

-- Drives one NPC's movement. Recomputes a fresh path toward the (possibly
-- moving) target every RETARGET_INTERVAL. Waypoint-to-waypoint, it switches
-- targets as soon as it gets *close* to the current one (WAYPOINT_REACHED_DISTANCE)
-- rather than waiting for MoveToFinished -- that event only fires once the
-- humanoid fully decelerates to a stop, and re-accelerating from a dead stop
-- at every waypoint is what caused the visible stutter.
-- `token` mirrors activeToken so this NPC's Heartbeat connection disconnects
-- itself once the NPC is despawned, instead of leaking forever.
local function attachMovement(humanoid, rootPart, token, state)
	local waypoints = {}
	local waypointIndex = 1
	local lastPathTarget = nil
	local directTarget = nil

	local function moveToCurrentWaypoint()
		local waypoint = waypoints[waypointIndex]
		if waypoint then
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			humanoid:MoveTo(waypoint.Position)
		end
	end

	local function setTarget(targetPosition, useDirectMovement, forceRepath)
		if useDirectMovement then
			directTarget = targetPosition
			waypoints = {}
			waypointIndex = 1
			humanoid:MoveTo(targetPosition)
			return
		end

		directTarget = nil

		if not forceRepath
			and lastPathTarget
			and horizontalDistance(lastPathTarget, targetPosition) < PATH_TARGET_MOVE_THRESHOLD
			and waypoints[waypointIndex]
		then
			return
		end

		lastPathTarget = targetPosition

		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 5,
		})

		local success = pcall(function()
			path:ComputeAsync(rootPart.Position, targetPosition)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
			waypointIndex = waypoints[2] and 2 or 1
		else
			waypoints = { PathWaypoint.new(targetPosition, Enum.PathWaypointAction.Walk) }
			waypointIndex = 1
		end

		moveToCurrentWaypoint()
	end

	local heartbeatConn
	heartbeatConn = RunService.Heartbeat:Connect(function()
		if activeToken ~= token or not rootPart.Parent then
			heartbeatConn:Disconnect()
			return
		end

		if state.isRagdolled then
			return -- don't fight the ragdoll launch with MoveTo calls
		end

		if directTarget then
			-- Re-issuing MoveTo keeps the humanoid steering continuously instead
			-- of braking between short chase updates.
			humanoid:MoveTo(directTarget)
			return
		end

		local waypoint = waypoints[waypointIndex]
		if not waypoint then
			return
		end

		if (waypoint.Position - rootPart.Position).Magnitude <= WAYPOINT_REACHED_DISTANCE then
			waypointIndex += 1
			moveToCurrentWaypoint()
		end
	end)

	return setTarget
end

-- Ragdolls + launches a guard rammed by an occupied cart. Called from a
-- per-frame distance check (see spawnOneChaser) rather than a Touched event,
-- so it fires the instant the cart gets close enough -- no waiting on the
-- physics engine to generate a contact.
local function ragdollGuardFromCart(character, rootPart, state, cartSeat)
	if state.isRagdolled then
		return
	end
	state.isRagdolled = true
	ragdollCharacterEvent:Fire(character, CART_RAGDOLL_DURATION)

	-- Launch dramatically: inherit the cart's own momentum (scaled up) plus
	-- a strong random upward pop and spin, so it reads as getting flung, not
	-- just going limp in place.
	local cartVelocity = cartSeat.AssemblyLinearVelocity
	local upwardPop = math.random(CART_LAUNCH_UPWARD_POP[1], CART_LAUNCH_UPWARD_POP[2])
	rootPart.AssemblyLinearVelocity = cartVelocity * CART_LAUNCH_VELOCITY_MULTIPLIER
		+ Vector3.new(math.random(-15, 15), upwardPop, math.random(-15, 15))
	rootPart.AssemblyAngularVelocity = Vector3.new(
		math.random(-10, 10), math.random(-10, 10), math.random(-10, 10)
	)

	task.delay(CART_RAGDOLL_DURATION, function()
		state.isRagdolled = false
	end)
end

local function attachTagDetection(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	rootPart.Touched:Connect(function(hit)
		local otherCharacter = hit:FindFirstAncestorOfClass("Model")
		if not otherCharacter then
			return
		end
		local otherPlayer = Players:GetPlayerFromCharacter(otherCharacter)
		if not otherPlayer or otherPlayer.Team ~= shopperTeam then
			return
		end
		if otherPlayer:GetAttribute("Frozen")
			or otherPlayer:GetAttribute("Out")
			or otherPlayer:GetAttribute("Escaped")
		then
			return
		end
		freezeShopperEvent:Fire(otherPlayer)
	end)
end

-- ========================= SPAWN / DESPAWN ==========================
local function spawnOneChaser(myToken, spawnPart, spawnIndex)
	-- Blank HumanoidDescription = default placeholder avatar look; no
	-- network dependency on a real user's avatar
	local description = Instance.new("HumanoidDescription")
	local npc = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	npc.Name = "SecurityBot" .. spawnIndex
	npc:PivotTo(spawnPart.CFrame + Vector3.new(0, 4, 0))
	npc.Parent = workspace

	local humanoid = npc:WaitForChild("Humanoid")
	humanoid.WalkSpeed = WALK_SPEED

	local guardState = { isRagdolled = false }
	attachTagDetection(npc)
	table.insert(activeNPCs, npc)

	local rootPart = npc.PrimaryPart
	local setTarget = attachMovement(humanoid, rootPart, myToken, guardState)

	-- Distance-based cart-ram check, every frame -- see ragdollGuardFromCart
	-- for why this replaced a Touched-event approach.
	local ramCheckConn
	ramCheckConn = RunService.Heartbeat:Connect(function()
		if activeToken ~= myToken or not npc.Parent then
			ramCheckConn:Disconnect()
			return
		end
		if guardState.isRagdolled then
			return
		end
		for _, cartSeat in cartSeats do
			if cartSeat.Occupant and (cartSeat.Position - rootPart.Position).Magnitude <= CART_RAM_DISTANCE then
				ragdollGuardFromCart(npc, rootPart, guardState, cartSeat)
				break
			end
		end
	end)

	-- Per-guard chase/patrol state. lockedTarget persists across ticks so a
	-- guard commits to a chase (with LOSE_RANGE hysteresis) instead of
	-- forgetting a shopper the instant they blip outside DETECT_RANGE.
	-- wanderTarget likewise persists until actually reached, so patrolling
	-- reads as purposeful walking instead of re-rolling direction every tick.
	local lockedTarget = nil
	local wanderTarget = nil

	local function isShopperCatchable(shopper)
		return shopper.Character
			and shopper.Character.PrimaryPart
			and not shopper:GetAttribute("Frozen")
			and not shopper:GetAttribute("Out")
			and not shopper:GetAttribute("Escaped")
	end

	local lastPosition = rootPart.Position
	local stuckTicks = 0

	task.spawn(function()
		while activeToken == myToken and npc.Parent do
			if guardState.isRagdolled then
				-- Pause all decision-making while ragdolled -- MoveTo calls
				-- don't do anything useful against a PlatformStand humanoid
				-- anyway, and the stuck-watchdog nudging a limp ragdoll body
				-- would look wrong. Resumes automatically once it settles.
				task.wait(0.2)
				continue
			end

			local currentPosition = rootPart.Position

			-- Stuck watchdog: pathfinding can produce a technically-valid route
			-- that still clips a wall corner physically (character collision
			-- isn't perfectly represented by the navmesh). If the guard barely
			-- moves for a few ticks straight, force a small nudge + a fresh
			-- wander target instead of letting it grind against the wall forever.
			if horizontalDistance(currentPosition, lastPosition) < STUCK_DISTANCE_THRESHOLD then
				stuckTicks += 1
			else
				stuckTicks = 0
			end
			lastPosition = currentPosition

			if stuckTicks >= STUCK_TICKS_THRESHOLD then
				stuckTicks = 0
				wanderTarget = nil
				rootPart.CFrame = rootPart.CFrame + Vector3.new(math.random(-4, 4), 2, math.random(-4, 4))
			end

			if lockedTarget then
				if not isShopperCatchable(lockedTarget) then
					lockedTarget = nil
				elseif horizontalDistance(lockedTarget.Character.PrimaryPart.Position, currentPosition) > LOSE_RANGE then
					lockedTarget = nil -- got away
				end
			end

			if not lockedTarget then
				local candidate, distance = getNearestFreeShopper(currentPosition)
				if candidate and distance <= DETECT_RANGE then
					lockedTarget = candidate
				end
			end

			if lockedTarget then
				local targetCharacter = lockedTarget.Character
				local targetRoot = targetCharacter and targetCharacter.PrimaryPart
				if targetRoot then
					local distance = horizontalDistance(currentPosition, targetRoot.Position)
					local visible = hasLineOfSight(npc, targetCharacter)
					local predictedPosition = getPredictedPosition(targetRoot)
					local useDirectMovement = visible and distance <= DIRECT_CHASE_RANGE

					wanderTarget = nil
					setTarget(predictedPosition, useDirectMovement, false)
				end
				task.wait(CHASE_RETARGET_INTERVAL)
			else
				if not wanderTarget or horizontalDistance(currentPosition, wanderTarget) <= WAYPOINT_REACHED_DISTANCE then
					wanderTarget = randomWanderPoint(spawnPart)
					setTarget(wanderTarget, false, true)
				else
					setTarget(wanderTarget, false, false)
				end
				task.wait(PATROL_RETARGET_INTERVAL)
			end
		end
	end)
end

local function spawnAI()
	if #activeNPCs > 0 then
		return -- already active
	end

	activeToken += 1
	local myToken = activeToken

	for i, spawnPart in chaserSpawnPoints do
		spawnOneChaser(myToken, spawnPart, i)
	end
end

local function despawnAI()
	activeToken += 1 -- invalidate any running wander/chase loops
	for _, npc in activeNPCs do
		npc:Destroy()
	end
	table.clear(activeNPCs)
end

spawnEvent.Event:Connect(spawnAI)
despawnEvent.Event:Connect(despawnAI)

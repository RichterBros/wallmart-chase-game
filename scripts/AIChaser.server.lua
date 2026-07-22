-- AIChaser
-- PASTE INTO: ServerScriptService (as a Script)
--
-- Computer-controlled Security guard for solo play. RoundManager fires
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
local DETECT_RANGE = 18 -- studs; how far the AI can "see" a free shopper
local WALK_SPEED = 10
local RETARGET_INTERVAL = 0.5 -- seconds between path recalculations
local WANDER_RADIUS = 40 -- studs from ChaserSpawn to pick random wander points
local WAYPOINT_REACHED_DISTANCE = 4 -- studs; switch to the next waypoint on approach

local shopperTeam = Teams:WaitForChild("Shoppers")

local chaserSpawn = workspace.Map:WaitForChild("ChaserSpawn")

local spawnEvent = ServerStorage:WaitForChild("AIChaserSpawn")
local despawnEvent = ServerStorage:WaitForChild("AIChaserDespawn")
local freezeShopperEvent = ServerStorage:WaitForChild("FreezeShopperEvent")

local activeNPC = nil
local activeToken = 0 -- bumped on despawn so any running wander loop stops itself

-- ========================= HELPERS ==========================
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
		local distance = (character.PrimaryPart.Position - fromPosition).Magnitude
		if distance < nearestDistance then
			nearest = shopper
			nearestDistance = distance
		end
	end
	return nearest, nearestDistance
end

local function randomWanderPoint()
	local angle = math.random() * math.pi * 2
	local radius = math.random() * WANDER_RADIUS
	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	return chaserSpawn.Position + offset
end

-- Drives one NPC's movement. Recomputes a fresh path toward the (possibly
-- moving) target every RETARGET_INTERVAL. Waypoint-to-waypoint, it switches
-- targets as soon as it gets *close* to the current one (WAYPOINT_REACHED_DISTANCE)
-- rather than waiting for MoveToFinished -- that event only fires once the
-- humanoid fully decelerates to a stop, and re-accelerating from a dead stop
-- at every waypoint is what caused the visible stutter.
-- `token` mirrors activeToken so this NPC's Heartbeat connection disconnects
-- itself once the NPC is despawned, instead of leaking forever.
local function attachMovement(humanoid, rootPart, token)
	local waypoints = {}
	local waypointIndex = 1

	local function setTarget(targetPosition)
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = false,
		})

		local success = pcall(function()
			path:ComputeAsync(rootPart.Position, targetPosition)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
			waypointIndex = waypoints[2] and 2 or 1 -- [1] is just the start position
		else
			waypoints = { PathWaypoint.new(targetPosition, Enum.PathWaypointAction.Walk) }
			waypointIndex = 1
		end

		local waypoint = waypoints[waypointIndex]
		if waypoint then
			humanoid:MoveTo(waypoint.Position)
		end
	end

	local heartbeatConn
	heartbeatConn = RunService.Heartbeat:Connect(function()
		if activeToken ~= token then
			heartbeatConn:Disconnect()
			return
		end

		local waypoint = waypoints[waypointIndex]
		if not waypoint then
			return
		end

		local nextWaypoint = waypoints[waypointIndex + 1]
		if nextWaypoint and (waypoint.Position - rootPart.Position).Magnitude <= WAYPOINT_REACHED_DISTANCE then
			waypointIndex += 1
			humanoid:MoveTo(waypoints[waypointIndex].Position)
		end
	end)

	return setTarget
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
		if otherPlayer:GetAttribute("Escaped") then
			return
		end
		freezeShopperEvent:Fire(otherPlayer)
	end)
end

-- ========================= SPAWN / DESPAWN ==========================
local function spawnAI()
	if activeNPC then
		return -- already active
	end

	activeToken += 1
	local myToken = activeToken

	-- Blank HumanoidDescription = default placeholder avatar look; no
	-- network dependency on a real user's avatar
	local description = Instance.new("HumanoidDescription")
	local npc = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	npc.Name = "SecurityBot"
	npc:PivotTo(chaserSpawn.CFrame + Vector3.new(0, 4, 0))
	npc.Parent = workspace

	local humanoid = npc:WaitForChild("Humanoid")
	humanoid.WalkSpeed = WALK_SPEED

	attachTagDetection(npc)
	activeNPC = npc

	local rootPart = npc.PrimaryPart
	local setTarget = attachMovement(humanoid, rootPart, myToken)

	task.spawn(function()
		while activeToken == myToken and npc.Parent do
			local targetShopper, distance = getNearestFreeShopper(rootPart.Position)
			local targetPosition
			if targetShopper and distance <= DETECT_RANGE then
				targetPosition = targetShopper.Character.PrimaryPart.Position
			else
				targetPosition = randomWanderPoint()
			end

			setTarget(targetPosition)
			task.wait(RETARGET_INTERVAL)
		end
	end)
end

local function despawnAI()
	activeToken += 1 -- invalidate any running wander/chase loop
	if activeNPC then
		activeNPC:Destroy()
		activeNPC = nil
	end
end

spawnEvent.Event:Connect(spawnAI)
despawnEvent.Event:Connect(despawnAI)

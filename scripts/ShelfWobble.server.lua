-- ShelfWobble
-- PASTE INTO: ServerScriptService (as a Script)
--
-- Purely cosmetic: shelves in Workspace.Map.Shelves give a small decaying
-- shake whenever a player touches/stands on them. Scripted rotation, not
-- real physics -- an actually unanchored shelf risks toppling over or
-- confusing the AI chaser's pathfinding navmesh, which this avoids entirely.

local Players = game:GetService("Players")

-- ========================== CONFIG ==========================
local WOBBLE_AMPLITUDE = 3 -- degrees; max tilt at the start of a wobble
local WOBBLE_FREQUENCY = 1.5 -- oscillations per second (higher looks like a violent buzz, not a wobble)
local WOBBLE_DECAY = 3 -- higher = settles back to level faster
local WOBBLE_COOLDOWN = 1 -- seconds after settling before it can be triggered again

local shelvesFolder = workspace.Map:WaitForChild("Shelves")

-- ========================= HELPERS ==========================
-- Shelves might be single Parts or grouped Models -- collect whichever
-- BaseParts actually need a Touched connection either way.
local function getTouchableParts(instance)
	if instance:IsA("BasePart") then
		return { instance }
	end
	local parts = {}
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function setupWobble(instance)
	if not (instance:IsA("BasePart") or instance:IsA("Model")) then
		return
	end

	local homePivot = instance:GetPivot()
	local isWobbling = false
	local cooldownUntil = 0

	-- The wobble itself shifts the shelf's collision geometry every frame,
	-- which makes standing characters register fresh contact points and
	-- re-fire Touched almost continuously. Two guards are needed, not just
	-- one: isWobbling stops a wobble from restarting its own decay clock
	-- mid-cycle, and cooldownUntil stops it from immediately chaining into
	-- ANOTHER fresh wobble the instant it settles while still being stood on
	-- -- without that second guard it reads as one continuous spasm.
	local function triggerWobble()
		if isWobbling or os.clock() < cooldownUntil then
			return
		end
		isWobbling = true

		task.spawn(function()
			local startTime = os.clock()
			while true do
				local elapsed = os.clock() - startTime
				local decay = math.exp(-WOBBLE_DECAY * elapsed)
				if decay < 0.02 then
					break
				end

				local wobble = math.sin(elapsed * WOBBLE_FREQUENCY * math.pi * 2) * WOBBLE_AMPLITUDE * decay
				instance:PivotTo(homePivot * CFrame.Angles(math.rad(wobble), 0, math.rad(wobble * 0.6)))
				task.wait()
			end

			instance:PivotTo(homePivot) -- settle back to exactly level
			isWobbling = false
			cooldownUntil = os.clock() + WOBBLE_COOLDOWN
		end)
	end

	for _, part in getTouchableParts(instance) do
		part.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			if not character then
				return
			end
			if not Players:GetPlayerFromCharacter(character) then
				return -- only real players trigger it, not coins/props/etc.
			end
			triggerWobble()
		end)
	end
end

for _, shelf in shelvesFolder:GetChildren() do
	setupWobble(shelf)
end

-- Alphabetical
require "Actor.lua"
require "Const.lua"
require "Debug.lua"
require "History.lua"
require "Table.lua"
require "Timeout.lua"
require "Utils.lua"

-- Dependency
require "Commands.lua"	-- depends on Table.lua at load time

-- TODO: Config
local SightRange = 14

-- TODO: Detect movement speeds automatically
--	(from http://forums.roempire.com/archive/index.php/t-137959.html)
--	0.15 sec per cell at regular speed
--	0.11 sec per cell w/ agi up
--	0.06 sec per cell w/ Lif's emergency avoid
local MsecPerCell = 150

function AI(id)
	-- Get Owner and Self
	RAIL.Owner = Actors[GetV(V_OWNER,id)]
	RAIL.Self  = Actors[id]

	-- Get our attack range
	RAIL.Self.AttackRange = GetV(V_ATTACKRANGE,id)

	-- Get our longest skill range
	-- TODO
	RAIL.Self.SkillRange = 0

	-- Never show up as either enemies or friends
	RAIL.Owner.IsEnemy  = function() return false end
	RAIL.Owner.IsFriend = function() return false end
	RAIL.Self.IsEnemy   = function() return false end
	RAIL.Self.IsFriend  = function() return false end

	if RAIL.Mercenary then
		RAIL.Self.AI_Type = GetV(V_MERTYPE,id)
	else
		RAIL.Self.AI_Type = GetV(V_HOMUNTYPE,id)
	end

	AI = RAIL.AI
	AI(id)
end

function RAIL.AI(id)
	-- Potential targets
	local Potential = {
		Attack = {},
		Skill = {},
		Chase = {},
	}

	-- Decided targets
	local Target = {
		Skill = nil,
		Attack = nil,
		Chase = nil,
	}

	local Friends = {}

	-- Flag to terminate after data collection
	local terminate = false

	-- Update actor information
	do
		-- Update both owner and self before every other actor
		RAIL.Owner:Update()
		RAIL.Self:Update()

		-- Determine if we need to chase our owner
		if RAIL.Self:BlocksTo(0)(
			-- 2.5 tiles ahead, to start moving before off screen
			RAIL.Owner.X[-2.5*MsecPerCell],
			RAIL.Owner.Y[-2.5*MsecPerCell]
		) >= SightRange then
			Target.Chase = RAIL.Owner
		end

		-- Update all the on-screen actors
		local i,actor
		for i,actor in ipairs(GetActors()) do
			-- Don't double-update the owner or self
			if RAIL.Owner.ID ~= actor and RAIL.Self.ID ~= actor then
				-- Indexing non-existant actors will auto-create them
				local actor = Actors[actor]

				-- Update the information about it
				actor:Update()

				-- If the actor that was just updated is a portal
				if actor.Type == 45 and not terminate then
					-- Get the block distances between the portal and the owner
						-- roughly 2.5 tiles from now
					local inFuture = RAIL.Owner:BlocksTo(-2.5*MsecPerCell)(actor)
						-- and now
					local now = RAIL.Owner:BlocksTo(actor)

					if inFuture < 3 and inFuture < now then
						RAIL.Log(0,"Owner approaching portal; cycle terminating after data collection.")
						terminate = true
					end
				end

				-- If we're chasing owner, we won't be doing anything else
				if Target.Chase ~= RAIL.Owner then

					if actor:IsEnemy() then
						local dist = RAIL.Self:DistanceTo(actor)

						-- Is the actor in range of attack?
						if dist <= RAIL.Self.AttackRange then
							Potential.Attack[actor.ID] = actor
						end

						-- Is the actor in range of skills?
						if dist <= RAIL.Self.SkillRange then
							Potential.Skill[actor.ID] = actor
						end

						Potential.Chase[actor.ID] = actor
					end

					if actor:IsFriend() then
						Friends[actor.ID] = actor
					end

				end -- Target.Chase ~= RAIL.Owner
			end -- RAIL.Owner.ID ~= actor
		end -- i,actor in ipairs(GetActor())
	end

	-- Iterate through the timeouts
	RAIL.Timeouts:Iterate()

	-- Process commands
	do
		-- Check for a regular command
		local shift = false
		local msg = GetMsg(RAIL.Self.ID)

		if msg[1] == NONE_CMD then
			-- Check for a shift+command
			shift = true
			msg = GetResMsg(RAIL.Self.ID)
		end

		-- Process any command
		RAIL.Cmd.Process[msg[1]](shift,msg)

	end

	-- Check if the cycle should terminate early
	if terminate then return end

	-- Pre-decision cmd queue evaluation
	do
		while RAIL.Cmd.Queue:Size() > 0 do
			local msg = RAIL.Cmd.Queue[RAIL.Cmd.Queue.first]

			if msg[1] == MOVE_CMD then
				Target.Chase = msg
				break
			elseif msg[1] == ATTACK_OBJECT_CMD then
				-- Check for valid actor
				local actor = Actors[msg[2]]
				if math.abs(GetTick() - actor.LastUpdate) < 100 then
					-- Chase it
					Target.Chase = actor

					-- And if close enough, attack it
					if RAIL.Self:DistanceTo(actor) <= RAIL.Self.AttackRange then
						Target.Attack = actor
					end
				end
				break
			else
				-- Skill commands are only thing left over
				if Target.Skill == nil then
					Target.Skill = msg
				else
					break
				end
			end
		end
	end

	-- Decision Making
	do
		-- Skill
		if Target.Skill == nil and Target.Chase ~= RAIL.Owner then
		end

		-- Attack
		if Target.Attack == nil and Target.Chase ~= RAIL.Owner then
		end

		-- Move
		if Target.Chase == nil then
		end
	end

	-- Action
	do
		-- Skill
		if Target.Skill ~= nil then
			if Target.Skill[1] == SKILL_OBJECT_CMD then
				-- Actor-targeted skill
				SkillObject(
					RAIL.Self.ID,
					Target.Skill[2],	-- level
					Target.Skill[3],	-- skill
					Target.Skill[4]		-- target
				)
			else
				-- Ground-targeted skill
				SkillGround(
					RAIL.Self.ID,
					Target.Skill[2],	-- level
					Target.Skill[3],	-- skill
					Target.Skill[4],	-- x
					Target.Skill[5]		-- y
				)
			end
		end

		-- Attack
		if Target.Attack ~= nil then
			Attack(RAIL.Self.ID,Target.Attack.ID)
		end

		-- Move
		if Target.Chase ~= nil then
			local x,y

			if RAIL.IsActor(Target.Chase) then
				-- Move to actor
				-- TODO: Predict location
				x,y = Target.Chase.X[0],Target.Chase.Y[0]
			else
				-- Move to ground
				x,y = Target.Chase[2],Target.Chase[3]
			end

			-- TODO: Alter move such that repeated moves to same location
			--		aren't ignored

			Move(RAIL.Self.ID,x,y)
		end
	end
end

--[[ Connected Discord-GitHub; Roblox: SeaTheSauce; Discord: seaxz
Dash - LocalScript in StarterPlayerScripts
Features:
- Directional
- Client sided for responsiveness
- Independent cooldowns
- Dynamic dash rotation
- Ground colored VFX
- Trails
- Animation system
- Sound system
]]

local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = game.Players.LocalPlayer
local CAS = game:GetService("ContextActionService") -- superior cuz you can set binds to all devices compared to uis

-- Set up the variables
local frontCooldown = false
local sidebackCooldown = false
local frontTime = 0.55
local sidebackTime = 0.55
local frontSpeed = 100
local sidebackSpeed = 80

local frictionPower = 2
local dashInProgress = false

local char, animator, hrp, hum, anims
local function setupCharacter(newCharacter) -- this is needed to prevent outdated character data which can lead to the script using old hrp or hum
	char = newCharacter
	hrp = char:WaitForChild("HumanoidRootPart")
	hum = char:WaitForChild("Humanoid")
	
	animator = char:WaitForChild("Humanoid"):FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	animator.Parent = hum
	
	anims = {}
	local animObjects = {"Front", "Back", "Left", "Right"}

	for _, name in animObjects do
		local obj = script:WaitForChild(name)
		local track = animator:LoadAnimation(obj) -- load the animation
		anims[name] = track -- store the track
		track.Looped = false -- make sure it's not looped
		track.Priority = Enum.AnimationPriority.Action4 -- prioritise it
	end
	
	-- reset cooldowns
	frontCooldown = false
	sidebackCooldown = false
	dashInProgress = false
end

player.CharacterAdded:Connect(setupCharacter) -- set up the function above
if player.Character then
	setupCharacter(player.Character)
end

local function playDashSound()
	local soundSource = (hum.FloorMaterial == Enum.Material.Grass or hum.FloorMaterial == Enum.Material.Sand)
		and script:FindFirstChild("GrassySound") -- checks if the floor is grassy or sandy and uses a special sound
		or script:FindFirstChild("NormalSound") -- if the floor is any other material it falls back to the normal sound

	if soundSource then -- check first to prevent errors
		local sound = soundSource:Clone() -- clone it from the script 
		sound.Parent = hrp -- and parent it to hrp so that it exists in physical space
		sound.PlaybackSpeed = math.random(90, 110) / 100 -- little detail that makes the same sound feel different
		sound:Play()

		Debris:AddItem(sound, 2) -- cleanup
	end
end

local function handleTrails(char)
	local trail = game.ReplicatedStorage.VFX.Trails:Clone() -- folder with the trails
	trail.Parent = char

	for _, v in trail:GetDescendants() do
		if v:IsA("Attachment") then
			local bpart = v:GetAttribute("BodyPart") -- get the body part it's supposed to be on from an attribute
			local targetPart = char[bpart] -- find the part in the character
			if not targetPart then return end
			v.Parent = targetPart -- if it exists parent the attachment to it
			v.WorldPosition = targetPart.Position -- and set the position to the part's position
			game.Debris:AddItem(v, 0.4) -- cleanup
		end
	end

	for _, v in trail:GetDescendants() do -- after the attachments are set up search for the trails
		if v:IsA("Trail") then
			local targetPart = char:FindFirstChild(v.Name) -- get the body part from the name

			if targetPart then 
				v.Parent = targetPart -- if the part exists parent it to the part

				local att0 = targetPart:FindFirstChild("Att0") -- get the attachment from the part
				local att1 = targetPart:FindFirstChild("Att1")

				att0.Position = Vector3.new(0, 0.5, 0) -- set the attachment positions
				att1.Position = Vector3.new(0, -0.5, 0)

				v.Attachment0 = att0 -- connect the attachments so the trail is attached to the 
				v.Attachment1 = att1 -- ^

				v.Enabled = true
				game.Debris:AddItem(v, 0.4) -- cleanup
			end
		end
	end
	trail:Destroy() -- folder is not needed anymore
end

local function handleVFX(char)
	local smokeInterval = 0.1
	local elapsed = 0
	local feetParts = { char:FindFirstChild("Left Leg"), char:FindFirstChild("Right Leg") }
	local smokeConnection -- variable for later cleanup
	smokeConnection = game:GetService("RunService").Heartbeat:Connect(function(dt)
		elapsed += dt -- make a timer by adding the delta time taken from the connection
		if elapsed >= smokeInterval then -- when the timer reaches the smoke interval spawn the vfx
			elapsed -= smokeInterval -- reset the timer
			for _, foot in feetParts do -- switch feet for variety
				if foot then
					local smoke = game.ReplicatedStorage.VFX.DashSmoke:Clone()
					smoke.CFrame = CFrame.new(foot.Position - Vector3.new(0, foot.Size.Y / 2, 0)) -- teleport it under the foot
					smoke.Parent = workspace -- add it to real space
					
					local color = nil
					local params = RaycastParams.new() -- raycast to find the floor
					params.FilterDescendantsInstances = {char} -- add the player's character to the filter
					params.FilterType = Enum.RaycastFilterType.Exclude -- and exclude the parts so they get ignored, only the floor is important
					local raycastResult = workspace:Raycast(hrp.Position, Vector3.new(0, -5, 0), params) -- shoot the ray downward
					if raycastResult then -- if the ray hits a floor
						color = raycastResult.Instance.Color -- we take the floor's color
					end

					for _, v in smoke:GetDescendants() do -- search descendants
						if v:IsA("ParticleEmitter") then -- for particles
							if color then -- to switch the color to.. 
								v.Color = ColorSequence.new(color) -- you guessed it, the floor's color we took
								v:Emit(1)
							end
						end
					end

					Debris:AddItem(smoke, 0.5) -- cleanup ofc
				end
			end
		end
		if not char:IsDescendantOf(workspace) then -- in case the player dies or something
			smokeConnection:Disconnect() -- we clean up the vfx
		end
	end)
	task.delay(0.5, function() -- how long the connection will run
		smokeConnection:Disconnect() -- cleanup after the 0.5s
	end)
end

local function onDashAction(actionName, inputState, inputObject)
	if inputState ~= Enum.UserInputState.Begin then return end -- ignores input if its not a press
	if not player then return end
	if not (hrp and hum) then return end -- make sure the player is still alive and that the character is updated
	if dashInProgress then return end -- prevents double dashing
	if frontCooldown and sidebackCooldown then return end 
	-- ^initial cooldown check if neither cooldowns are ready

	dashInProgress = true
	
	local rootLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z) -- we get the look vector of the hrp cframe and set the Y level to 0
	local rootRight = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z) -- ^ same as here but with the right vector
	if rootLook.Magnitude <= 0.001 or rootRight.Magnitude <= 0.001 then 
		-- ^ now since the vectors are flattened we make sure we have horizontal magnitude values to prevent people from looking up or down to dash
		dashInProgress = false
		return 
	end 
	
	rootLook = rootLook.Unit -- simplify to only the unit since the vertical checks are over and we need this later
	rootRight = rootRight.Unit -- ^

	local inputForward = 0
	local inputRight = 0
	if UIS:IsKeyDown(Enum.KeyCode.W) then inputForward += 1 end -- we check the inputs first
	if UIS:IsKeyDown(Enum.KeyCode.S) then inputForward -= 1 end
	if UIS:IsKeyDown(Enum.KeyCode.D) then inputRight += 1 end
	if UIS:IsKeyDown(Enum.KeyCode.A) then inputRight -= 1 end

	local dashKind, localDashDir
	if inputForward ~= 0 or inputRight ~= 0 then
		if math.abs(inputForward) >= math.abs(inputRight) then 
			-- ^ check if the absolute value (so that negative/backwards inputs are turned positive) of the forward input is higher than the right input
			if inputForward > 0 then -- and then check if it's a forward dash
				dashKind = "Front" -- this sets the dash kind so we have a key for later use in animation, cooldown, etc.
				localDashDir = Vector3.new(0, 0, -1) -- this sets the direction for later yaw calculation
			else -- or fall back to the backward dash
				dashKind = "Back"
				localDashDir = Vector3.new(0, 0, 1)
			end
		else -- and if it's not higher, it's
			if inputRight > 0 then -- right
				dashKind = "Right"
				localDashDir = Vector3.new(1, 0, 0)
			else -- or left
				dashKind = "Left"
				localDashDir = Vector3.new(-1, 0, 0)
			end
		end
	else -- fallback in case input variables are 0
		local rawMoveDir = hum.MoveDirection
		local moveDir = Vector3.new(rawMoveDir.X, 0, rawMoveDir.Z) -- flatten the vectors to the XZ plane again
		local dashUnit = moveDir.Magnitude > 0.05 and moveDir.Unit or rootLook 
		-- ^ we get the direction the chararcter wants to move in from either the humanoid or the hrp look we calculated earlier as a fallback if the player is not moving
		local forwardDot = dashUnit:Dot(rootLook) 
		-- ^ we get the dot product (so we have one number we can compare) between the dash unit and the look vector of the player
		local rightDot = dashUnit:Dot(rootRight) -- and between the dash unit and right vector of the player

		if math.abs(forwardDot) >= math.abs(rightDot) then -- now we do the same things we did for the input checks
			if forwardDot >= 0 then
				dashKind = "Front"
				localDashDir = Vector3.new(0, 0, -1)
			else
				dashKind = "Back"
				localDashDir = Vector3.new(0, 0, 1)
			end
		else
			if rightDot >= 0 then
				dashKind = "Right"
				localDashDir = Vector3.new(1, 0, 0)
			else
				dashKind = "Left"
				localDashDir = Vector3.new(-1, 0, 0)
			end
		end
	end

	local isFrontDash = dashKind == "Front" 
	local dashTime = isFrontDash and frontTime or sidebackTime    -- Make front dashes stronger
	local dashSpeed = isFrontDash and frontSpeed or sidebackSpeed -- ^
	
	--
	if isFrontDash and frontCooldown then -- checks the specific cooldown and returns if it's still on cooldown
		dashInProgress = false
		return
	elseif not isFrontDash and sidebackCooldown then
		dashInProgress = false
		return
	end

	if isFrontDash then -- sets the cooldown for the specific dash
		frontCooldown = true
		task.delay(2, function()
			frontCooldown = false
		end)
	else
		sidebackCooldown = true
		task.delay(2, function()
			sidebackCooldown = false
		end)
	end
	task.delay(dashTime, function()
		dashInProgress = false
	end)
	-- ^ We set different cooldown keys so you can chain front and side dashes

	playDashSound() -- set up the functions we made earlier
	handleTrails(char) -- ^
	handleVFX(char)    -- ^
	hum.JumpPower = 0 -- prevent jumping during dash
	hum.JumpHeight = 0 -- ^
	task.delay(dashTime, function() -- and after the dash is done
		hum.JumpPower = 50 -- restore it
		hum.JumpHeight = 7.2 -- ^
	end)
	
	anims[dashKind]:Play() -- now we play an animation based on the player's dash direction

	local attachment = Instance.new("Attachment", hrp) -- now we make an attachment
	attachment.Name = "DashAttachment"
	local lv = Instance.new("LinearVelocity") 
	-- ^ LinearVelocity is the choice here cuz we can control the axis and its also more optimised than body velocity
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis -- we limit per axis so that
	lv.MaxAxesForce = Vector3.new(100000, 0, 100000) -- we can be sure it doesn't go up or down at all
	lv.RelativeTo = Enum.ActuatorRelativeTo.World -- ignores the character's rotation and uses the world space instead
	lv.Attachment0 = attachment -- apply velocity to the attachment
	lv.Parent = hrp -- and attach it to the character's hrp

	local startTime = tick() -- timer
	local RunService = game:GetService("RunService")

	local function getCharacterYaw() -- returns the current character's yaw
		local look = hrp.CFrame.LookVector -- get the character's forward direction
		return math.atan2(-look.X, -look.Z) -- and calculates the yaw based on it
	end

	local function buildDirFromYaw(yaw, localDir)
		local yawCF = CFrame.Angles(0, yaw, 0) -- convert yaw to a CFrame
		local worldDir = yawCF:VectorToWorldSpace(localDir) -- convert the local direction to world space
		local flat = Vector3.new(worldDir.X, 0, worldDir.Z) -- flatten it
		return flat.Magnitude > 0 and flat.Unit or flat -- return the world space direction
	end

	local currentDir = buildDirFromYaw(getCharacterYaw(), localDashDir) -- get the world space dash direction
	local lastYaw = getCharacterYaw() -- initialise lastYaw

	local connection
	connection = RunService.Heartbeat:Connect(function(dt) -- heartbeat connection to update every frame
		if not lv.Parent then -- stop if the attachment is gone
			connection:Disconnect()
			if attachment then attachment:Destroy() end
			return
		end
		
		local elapsed = tick() - startTime -- timer
		local t = math.clamp(elapsed / dashTime, 0, 1) -- time as a 0 to 1 ratio

		if t >= 1 then -- stop if dash is over
			connection:Disconnect()
			lv:Destroy()
			attachment:Destroy()
			return
		end

		local ease = math.pow(1 - t, frictionPower) -- calculate the easing, we use power to make the friction weaker relative to the time elapsed

		local currentForce = 100000 * ease -- apply the easing to the force
		lv.MaxAxesForce = Vector3.new(currentForce, 0, currentForce) -- we only need to apply force to X and Z, Y is ignored
		
		-- this is the best part: now we rotate the dash direction to match the character's rotation, this makes the dash directional and cool
		local currentYaw = getCharacterYaw() -- get the current yaw
		local deltaYaw = currentYaw - lastYaw -- we calculate the difference in yaws
		if deltaYaw > math.pi then deltaYaw -= 2 * math.pi end
		-- ^ now we normalise the angle by making it between -pi and pi (-180 and 180 degrees) to make sure the rotation is the shortest way
		if deltaYaw < -math.pi then deltaYaw += 2 * math.pi end -- ^
		lastYaw = currentYaw

		local rotated = CFrame.Angles(0, deltaYaw, 0):VectorToWorldSpace(currentDir) -- convert the yaw difference to a world space direction
		local newDir = Vector3.new(rotated.X, 0, rotated.Z) -- now we get the new direction and
		if newDir.Magnitude > 0 then currentDir = newDir.Unit end -- update the current direction if it's valid

		lv.VectorVelocity = currentDir * (dashSpeed * ease) -- update the velocity and apply the easing to the speed
		-- now we have directional dashing that works with both shift lock movement and WASD/joystick movement
	end)
end

CAS:BindAction("Dash", onDashAction, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX) 
-- ^ now we bind the action to the dash function, create a button for mobile, and set the keys to Q on PC and to X on console

local dashButton = CAS:GetButton("Dash") -- create the button for mobile
if dashButton then
	dashButton.Size = UDim2.new(0, 60, 0, 60)
	dashButton.Position = UDim2.new(1, -220, 0, -100)
end

CAS:SetTitle("Dash", "DASH") -- set the text
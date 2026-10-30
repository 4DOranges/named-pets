local renamedPets = PersistentDB:GetStructuredData("renamedPets") or {}
local lastUsedNames = PersistentDB:GetStructuredData("lastUsedNames") or {}
local renameEnabled = PersistentDB:GetBool("renameEnabled") ~= false
local labelsEnabled = PersistentDB:GetBool("labelsEnabled") ~= false
local labelColour = PersistentDB:GetInt("labelColour") or 0x00FF00FF
labelColour = labelColour % 0x100000000

local renameWindow
function renamePet(currentName, petID, oldPetName)
	local parent = ui.Interfaces:GetComponent(id.Component.CHATDEFAULT__CHAT_CONTAINER)
	renameWindow = prettyui.Window.new(parent, {
		x = parent.x,
		y = parent.y,
		width = parent.width,
		height = parent.height
	})
	local nameInput = renameWindow:AddTextField({
		placeholder = currentName,
		maxLength = 38,
		onSubmit = function(field, text)
			renamedPets[petID] = {}
			renamedPets[petID][1] = text
			renamedPets[petID][2] = oldPetName
			insertLastUsedName(text)
			renameWindow:Destroy()
		end
	})

	local lastNamesLabel = renameWindow:AddText("Last used names:")
	local lastNames = renameWindow:AddComboBox({
		entries = lastUsedNames,
		onChange = function(combo, id, label)
			nameInput:SetText(label)
		end,
		inline = true
	})

	local confirmButton = renameWindow:AddFancyButton("Confirm", function()
		local name = nameInput:GetText()
		if name ~= "" then
			renamedPets[petID] = {}
			renamedPets[petID][1] = name
			renamedPets[petID][2] = oldPetName
			insertLastUsedName(name)
		end
		renameWindow:Destroy()
	end,{
		variant = "positive"
	})

	local resetButton = renameWindow:AddSpriteButton("UNDO", function()
		renamedPets[petID] = nil
		renameWindow:Destroy()
	end, {
		inline = true,
		tooltip = "Reset name",
		x = parent.width - 56
	})
end

-- Keep track of the 5 last names we used
function insertLastUsedName(name)
	local found = false
	for _, val in ipairs(lastUsedNames) do
		if val == name then found = true end
	end
	if found then return end
 	table.insert(lastUsedNames, 1, name)
	if #lastUsedNames > 5 then
		table.remove(lastUsedNames, #lastUsedNames)
	end
end

-- Replace the pet's name in minimenus
function miniMenuEvent(event)
	local isPet = false
	local petName, petID, oldPetName
	for _, entry in ipairs(event.miniMenu.entries) do
		if entry.npcData then
			npc = entry.npcData.entity.config
			oldPetName = npc.name
			if renamedPets[npc.id] then
				entry.overrideText = entry.fullText:gsub(npc.name, renamedPets[npc.id][1])
				petName = renamedPets[npc.id][1]
			end
			if isValidPet(npc.params) then
				isPet = true
				if not petName then petName = npc.name end
				petID = npc.id
			end
		end
	end
	ops = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__OPTEXT_PROPS)
	ops_bg = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__OPTEXT_BUBBLE)
	if ops then
		local labelText = ops:GetChild(0, 0)
		if labelText and petName and oldPetName then
			labelText.content = labelText.content:gsub(oldPetName, petName)
			local font = config.Font.FromID(labelText.font)
			local width = font:GetStringWidth(labelText.content, false)
			ops_bg:SetWidth(width + 20)
		end
	end
	
	-- Show Rename option
	if isPet and renameEnabled then
		event.miniMenu:Add("<sprite=20984><col=ceab64>Rename</col> <col=ffff00>" .. petName .. "</col>", renamePet, petName, petID, oldPetName)
		menuLength = #event.miniMenu.entries
		event.miniMenu:Swap(1, 2)
	end
end

-- An NPC is a "pet" if it's a follower or quest follower
function isValidPet(npcParams)
	for i=1, #npc.params do
		local followerObj = npc.params[i].configName == "FOLLOWER_OBJ"
		local questFollower = npc.params[i].configName == "GENERAL_USE_FOLLOWER_QUEST"
		if followerObj or questFollower then return true end
	end
	return false
end

-- Replace the pet's name in dialogue windows
function dialogueEvent(event)
	local head = ui.Interfaces:GetComponent(id.Component.CHAT_V2_LEFT__CHATHEAD_1)
	if head and head.type == ui.ComponentType.MODEL and head.modelType == ui.ModelType.NPC_HEAD then
		if renamedPets[head.modelID1] then
			nameLabel = ui.Interfaces:GetComponent(id.Component.CHAT_V2_LEFT__TITLE_TEXT)
			nameLabel.content = renamedPets[head.modelID1][1]
		end
	end
end

-- Replace the pet's name in the pets interface
function petInterfaceEvent(event)
	local petUI = ui.Interfaces:GetComponent(id.Component.MTXMGT__PREVIEW_PANE)
	if petUI then
		selectedPet = ui.Interfaces:GetComponent(id.Component.MTXMGT__PREVIEW_PANE):GetChild(0, 0)
		if selectedPet then
			if renamedPets[selectedPet.modelID1] then
				local puppyName = ui.Interfaces:GetComponent(id.Component.MTXMGT__PET_NAME)
				local nameLayer = ui.Interfaces:GetComponent(id.Component.MTXMGT__PETS_NAME_LAYER)
				puppyName.content = renamedPets[selectedPet.modelID1][1]
				local font = config.Font.FromID(puppyName.font)
				local width = font:GetStringWidth(puppyName.content, false)
				nameLayer:SetWidth(width + 20)
			end
		end
		local petLists = ui.Interfaces:GetComponent(id.Component.MTXMGT__LIST_CONTENTS)
		petLists:IterateStaticComponents(function(petListsComp,_)
			if petListsComp.GetChild then -- We found the open pet list!
				petListsComp:IterateDynamicComponents(function(pet,_)
					local newName = isRenamedPet(pet.content)
					if newName and pet.content then
						pet.content = newName
					end
				end)
			end
		end)
	end
end

function isRenamedPet(tester)
	for x,v in pairs(renamedPets) do
		if v[2] == tester then return v[1] end
	end
	return nil
end

--[[
===================
DRAW OVERHEAD NAMES
===================
]]--
local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
local petLabels = {}

local function createPetLabel()
	local label = ui.Text.new(parent)
	label:SetSize(350, 50)
	label.clickthrough = true
	label.hidden = true
	label.font = id.Font.MUSEO_SANS_15PT_BOLD
	label.isShadowed = true
	label:AlignTo(ui.AlignMode.CENTRE)
	return label
end

local function updatePetLabels(event)
	 -- Hide labels if player has disabled them OR the world map is open
	if not labelsEnabled or var.VarClient.WORLDMAP_FOCUS.value.x > 0 then
		for _, label in pairs(petLabels) do
			label.hidden = true
		end
		return
	end
	local active = {}
	local origin = parent.xyGlobal

	for _, pet in ipairs(NPCList.All()) do
		if not pet.isValid then	return end

		local renamed = renamedPets[pet.configID]
		if renamed and renamed[1] then
			local uid = pet.uid
			active[uid] = true

			local label = petLabels[uid]
			if not label then
				label = createPetLabel()
				petLabels[uid] = label
			end

			label.content = renamed[1]
			label.rgba = labelColour
			label.hidden = true

			local position = pet.position
			local labelY = pet.aabb.maximum.y
			local npcConfig = pet.config
			if npcConfig and npcConfig.overlayHeight >= 0 then
				labelY = position.y + npcConfig.overlayHeight
			end
			local headPosition = Vector3.new(position.x, labelY, position.z)

			local screen = ScreenConvert.Vector3ToScreen(headPosition)
			if not screen then return end

			local x = screen.x - origin.x
			local y = screen.y - origin.y

			if x >= 0 and y >= 0
				and x < parent.width and y < parent.height then
				label:SetPos(
					math.floor(x - label.width / 2),
					math.floor(y - label.height - 4)
				)
				label.hidden = false
			end
		end
	end

	-- Remove labels for NPCs that disappeared or are no longer renamed.
	local expired = {}

	for uid, label in pairs(petLabels) do
		if not active[uid] then
			label:Destroy()
			expired[#expired + 1] = uid
		end
	end

	for _, uid in ipairs(expired) do
		petLabels[uid] = nil
	end
end

Event.MiniMenuReady.Subscribe("petHoverEvent", miniMenuEvent)
Event.Logic.Subscribe("dialogueWatcher", dialogueEvent)
Event.Logic.Subscribe("petIntWatcher", petInterfaceEvent)
Event.Draw.Subscribe("updatePetLabels", updatePetLabels)

--[[
=============
SETTINGS MENU
=============
]]
local settingsView
Event.SettingsLayerReady.Subscribe("named-pets-settings", function(event)
	if settingsView then settingsView:Destroy() end
	local statusText = "Testing testing this is a test!"
	local parent = event.component
	settingsView = prettyui.SimpleView.new(parent, {width = parent.width, height = parent.height})

	settingsView:AddText("Changes are saved immediately.")
	settingsView:AddCheckboxButton({{text = "Show Rename option on pets", value = "renameEnabled", selected = renameEnabled},
	}, {
		onChange = function(_, _, _, selected)
			renameEnabled = selected
			PersistentDB:SetBool("renameEnabled", selected)
		end,
	})

	local showLabels = settingsView:AddCheckboxButton({
		{
			text = "Show names above pets?",
			value = "showNames",
			selected = labelsEnabled,
		},
	}, {
		onChange = function(_, _, _, selected)
			labelsEnabled = selected
			PersistentDB:SetBool("labelsEnabled", selected)
		end,
	})

	local labelColourPicker = settingsView:AddColourPicker({
		value = labelColour,
		windowTitle = "Pet label colour",
		tooltip = "Which colour for your overhead pet names?",
		inline = true,
		onChange = function(_, colour)
			-- Force full opacity.
			colour = colour - (colour % 256) + 255
			labelColour = colour

			local storedColour = colour
			if storedColour >= 0x80000000 then
				storedColour = storedColour - 0x100000000
			end

			PersistentDB:SetInt("labelColour", storedColour)
		end,
	})

	settingsView:AddFancyButton("RESET ALL PET NAMES", function()
		local confirm = prettyui.Confirm.new(parent, {
			title = "RESET PET NAMES",
			body = "This will reset all your pets back to their default names. Are you sure?",
			confirmLabel = "Reset names",
			confirmVariant = "negative",
			onConfirm = function()
				renamedPets = {}
				status = "All pet names have been reset!"
				statusText.content = status
			end,
		})
	end, {variant = "negative", marginTop = 15})
	statusText = settingsView:AddText({
		colour = 0x00ff00ff,
		inline = true
	})

end)

function PluginShutdown()
	Event.SettingsLayerReady.Unsubscribe("named-pets-settings")
	if renameWindow then
		renameWindow:Destroy()
		renameWindow = nil
	end

	PersistentDB:SetStructuredData("renamedPets", renamedPets)
	PersistentDB:SetStructuredData("lastUsedNames", lastUsedNames)
end
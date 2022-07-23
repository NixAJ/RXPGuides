﻿local addonName, addon = ...

local _G = _G

addon = LibStub("AceAddon-3.0"):NewAddon(addon, addonName, "AceEvent-3.0")

addon.versionText = "Version " .. GetAddOnMetadata(addonName, "Version")
addon.version = 40000
local gameVersion = select(4, GetBuildInfo())
addon.gameVersion = gameVersion

if gameVersion < 20000 then
    addon.game = "CLASSIC"
elseif gameVersion > 20000 and gameVersion < 30000 then
    addon.game = "TBC"
else
    addon.game = "WOTLK"
end

addon.questQueryList = {}
addon.itemQueryList = {}
addon.questAccept = {}
addon.questTurnIn = {}
addon.activeItems = {}
addon.RXPG = {}
addon.functions = {}

BINDING_HEADER_RXPGuides = "RXPGuides"
_G["BINDING_NAME_" .. "CLICK RXPItemFrameButton1:LeftButton"] =
    "Quest Item Button 1"
_G["BINDING_NAME_" .. "CLICK RXPItemFrameButton2:LeftButton"] =
    "Quest Item Button 2"
_G["BINDING_NAME_" .. "CLICK RXPItemFrameButton3:LeftButton"] =
    "Quest Item Button 3"
_G["BINDING_NAME_" .. "CLICK RXPItemFrameButton4:LeftButton"] =
    "Quest Item Button 4"

local questFrame = CreateFrame("Frame");

local buffCheckTimer
local function SoMCheck()
    local function CheckBuff(buffId,key)
        if GetTime() - buffCheckTimer < 300 and RXPCData and
                            type(RXPCData[key]) ~= "boolean" then

            local id = 0
            local n = 1
            while id do
                id = select(10, UnitBuff("player", n))
                n = n + 1
                if id == buffId then
                    RXPCData[key] = true
                    if addon.currentGuide and addon.currentGuide.name then
                        addon:LoadGuide(addon.currentGuide)
                    end
                    addon.RXPFrame.GenerateMenuTable()
                    break
                end
            end
            if id ~= buffId and RXPCData[key] then
                RXPCData[key] = nil
                addon.ReloadGuide()
                addon.RXPFrame.GenerateMenuTable()
            end
        end
    end

    if not buffCheckTimer then
        buffCheckTimer = GetTime()
    end

    if gameVersion < 20000 then
        CheckBuff(362859,"SoM")
    end

end

function RXPG_init()
    RXPData = RXPData or {}
    RXPCData = RXPCData or {}

    RXPCData.completedWaypoints = RXPCData.completedWaypoints or {}
    RXPCData.hardcore = (addon.game == "CLASSIC") and RXPCData.hardcore
    if not RXPData.addonVersion or RXPData.addonVersion < addon.version then
        RXPData.addonVersion = addon.version
        RXPCData.phase = 6
    end
    RXPCData.phase = RXPCData.phase or 6
    RXPCData.SoM = RXPCData.SoM or 1
    SoMCheck()
    addon.RenderFrame()
    RXPCData.stepSkip = RXPCData.stepSkip or {}
    RXPCData.xprate = RXPCData.xprate or 1
    RXPData.numMapPins = RXPData.numMapPins or 7
    RXPData.worldMapPinScale = RXPData.worldMapPinScale or 1
    RXPData.distanceBetweenPins = RXPData.distanceBetweenPins or 1
    RXPData.worldMapPinBackgroundOpacity =
        RXPData.worldMapPinBackgroundOpacity or 0.35
    RXPData.arrowSize = RXPData.arrowSize or 1
    RXPData.windowSize = RXPData.windowSize or 1
    RXPData.arrowText = RXPData.arrowText or 9
    RXPData.skipMissingPreReqs = false
    if not RXPCData.flightPaths or UnitLevel("player") <= 6 then
        RXPCData.flightPaths = {}
    end
    RXPData.batchSize = RXPData.batchSize or 5
    if RXPData.disableTrainerAutomation == nil then
        RXPData.disableTrainerAutomation = true
    end
    if RXPData.trainGenericSpells == nil then
        RXPData.trainGenericSpells = true
    end

    RXPData.anchorOrientation = RXPData.anchorOrientation or 1
    addon.RXPFrame:SetShown(not RXPCData.hideWindow)
    C_Timer.After(0.5, function()
        if addon.errorCount == addon.guideErrorCount then
            addon.errorCount = -1
            _G.ScriptErrorsFrame:Hide()
        end
    end)
end

addon.errorCount = 0
addon.guideErrorCount = 0

hooksecurefunc(_G.ScriptErrorsFrame, "DisplayMessage",
               function(self, msg, warnType, keepHidden, messageType)
    if _G.ScriptErrorsFrame:IsForbidden() then return end
    if addon.errorCount >= 0 then
        if warnType == 0 and keepHidden == false and messageType == 1 and
            type(msg) == "string" and msg:match(addonName .. "\\Guides") then
            addon.guideErrorCount = addon.guideErrorCount + 1
        end
        addon.errorCount = addon.errorCount + 1
    end
end)

local startTime = GetTime()

function addon.QuestAutoAccept(title)
    if title then
        local element
        for k, v in pairs(addon.questAccept) do
            if k == title or addon.GetQuestName(k) == title then
                element = v
            end
        end
        return element and element.step.active
    end
end

function addon.QuestAutoTurnIn(title)
    if title then
        local element
        for k, v in pairs(addon.questTurnIn) do
            if k == title or addon.GetQuestName(k) == title then
                element = v
            end
        end
        return (element and element.step.active) and element.reward >= 0 and element.reward
    end
end

local currrentSkillLevel = {}
local maxSkillLevel = {}
local professionNames

function addon.GetProfessionNames()
    if not professionNames then professionNames = {} end

    for profession, ids in pairs(addon.professionID) do
        for i, id in ipairs(ids) do
            if IsSpellKnown(id) then
                if id == 2656 then
                    professionNames[profession] = GetSpellInfo(2575)
                elseif id == 2383 then
                    professionNames[profession] = GetSpellInfo(9134)
                else
                    professionNames[profession] = GetSpellInfo(id)
                end
                break
            end
        end
    end
    professionNames.riding = GetSpellInfo(33388)
    return professionNames
end

function addon.GetProfessionLevel()
    local names
    if not (professionNames and professionNames.riding) then
        addon.GetProfessionNames()
    end
    names = professionNames

    if IsPlayerSpell(33388) then
        currrentSkillLevel["riding"] = 75
    elseif IsPlayerSpell(33391) then
        currrentSkillLevel["riding"] = 150
    elseif IsPlayerSpell(34090) then
        currrentSkillLevel["riding"] = 225
    elseif IsPlayerSpell(34091) then
        currrentSkillLevel["riding"] = 300
    elseif IsPlayerSpell(90265) then
        currrentSkillLevel["riding"] = 375
    end
    if not _G.GetSkillLineInfo then
        return
    end
    if not names.riding then names.riding = GetSpellInfo(33388) end
    for i = 1, _G.GetNumSkillLines() do
        local skillName, _, _, skillRank, _, _, skillMaxRank =
            _G.GetSkillLineInfo(i)
        if skillRank then
            for profession, name in pairs(names) do
                -- print(name,skillName,name == skillName)
                if name == skillName then
                    currrentSkillLevel[profession] = skillRank
                    maxSkillLevel[profession] = skillMaxRank
                end
            end
        end
    end
end

function addon.UpdateSkillData()
    addon.GetProfessionNames()
    addon.GetProfessionLevel()
end

function addon.GetSkillLevel(skill, useMaxValue)
    addon.UpdateSkillData()
    if skill then
        if useMaxValue then
            return maxSkillLevel[skill] or -1
        else
            return currrentSkillLevel[skill] or -1
        end
    else
        if useMaxValue then
            return maxSkillLevel
        else
            return currrentSkillLevel
        end
    end
end

addon.skillList = {}
local spellRequest = {}

local trainerUpdate = 0

local function ProcessSpells(names, rank)
    if gameVersion > 90000 then return end
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    local level = UnitLevel("player")
    local entries = {race, class}
    for _, entry in pairs(entries) do
        if addon.defaultSpellList[entry] then
            for spellLvl, spells in pairs(addon.defaultSpellList[entry]) do
                if spellLvl <= level then
                    for i, spellId in ipairs(spells) do
                        if not (spellRequest[spellId] or
                            C_Spell.IsSpellDataCached(spellId)) then
                            C_Spell.RequestLoadSpellData(spellId)
                            spellRequest[spellId] = true
                        end
                        if names and rank and
                            not (RXPCData.hardcore and addon.HCSpellList and
                                addon.HCSpellList[spellId]) then
                            spellRequest[spellId] = nil
                            local sName = GetSpellInfo(spellId)
                            local sRank = GetSpellSubtext(spellId)
                            for id, name in pairs(names) do
                                if sName == name and sRank == rank[id] then
                                    BuyTrainerService(id)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function OnTrainer()

    if not RXPData.disableTrainerAutomation then
        local level = UnitLevel("player")
        local i = GetNumTrainerServices()

        if not i or i == 0 or GetTime() - trainerUpdate > 15 then return end

        local names = {}
        local rank = {}

        for id = 1, i do
            local n, r, cat = GetTrainerServiceInfo(id)
            if cat == "available" then
                names[id] = n
                rank[id] = r
            end
        end

        ProcessSpells(names, rank)

        for spellName, spellRank in pairs(addon.skillList) do
            for id, name in pairs(names) do
                if name == spellName then
                    local r = rank[id]
                    r = r and tonumber(r:match("(%d+)")) or 0
                    if (r <= spellRank or spellRank == 0) then
                        BuyTrainerService(id)
                        return
                    end
                end
            end
        end
    end

end

local tTimer = 0
local function trainerFrameUpdate(self, t)
    tTimer = tTimer + t
    if tTimer >= 0.2 then
        tTimer = 0
        if GetTime() - trainerUpdate > 15 then
            self:SetScript("OnUpdate", nil)
        end
        OnTrainer()
    end
end

local GossipGetNumActiveQuests = C_GossipInfo.GetNumActiveQuests or
                                     _G.GetNumGossipActiveQuests
local GossipGetNumAvailableQuests = C_GossipInfo.GetNumAvailableQuests or
                                        _G.GetNumGossipAvailableQuests
local GossipGetNumOptions = C_GossipInfo.GetNumOptions or _G.GetNumGossipOptions
local GossipSelectAvailableQuest = C_GossipInfo.SelectAvailableQuest or
                                       _G.SelectGossipAvailableQuest
local GossipGetActiveQuests = C_GossipInfo.GetActiveQuests or
                                  _G.GetGossipActiveQuests
local GossipSelectActiveQuest = C_GossipInfo.SelectActiveQuest or
                                    _G.SelectGossipActiveQuest
local GossipGetAvailableQuests = C_GossipInfo.GetAvailableQuests or
                                     _G.GetGossipAvailableQuests

function addon:QuestAutomation(event, arg1, arg2, arg3)
    if IsControlKeyDown() == not (RXPData and RXPData.disableQuestAutomation) then
        return
    end

    if not event then
        if _G.GossipFrame and _G.GossipFrame:IsShown() then
            event = "GOSSIP_SHOW"
        elseif _G.QuestFrameGreetingPanel and
            _G.QuestFrameGreetingPanel:IsShown() then
            event = "QUEST_GREETING"
        elseif _G.QuestFrameProgressPanel and
            _G.QuestFrameProgressPanel:IsShown() then
            event = "QUEST_PROGRESS"
        elseif _G.QuestFrameRewardPanel and _G.QuestFrameRewardPanel:IsShown() or
            _G.QuestFrameCompleteButton and
            _G.QuestFrameCompleteButton:IsShown() then
            event = "QUEST_COMPLETE"
        else
            return
        end
    end

    if event == "QUEST_ACCEPT_CONFIRM" and addon.QuestAutoAccept(arg2) then
        ConfirmAcceptQuest()
    elseif event == "QUEST_COMPLETE" then
        local id = GetQuestID()
        local reward = addon.QuestAutoTurnIn(id)
        local choices = GetNumQuestChoices()
        if reward then
            if choices <= 1 then
                GetQuestReward(1)
            elseif reward and reward > 0 then
                GetQuestReward(reward)
            end
        end

    elseif event == "QUEST_PROGRESS" and IsQuestCompletable() then
        CompleteQuest()
        -- questProgressTimer = GetTime()

    elseif event == "QUEST_DETAIL" then
        local id = GetQuestID()
        if addon.QuestAutoAccept(id) then
            AcceptQuest()
            HideUIPanel(_G.QuestFrame)
        end

    elseif event == "QUEST_GREETING" then
        local nActive = GetNumActiveQuests()
        local nAvailable = GetNumAvailableQuests()

        for i = 1, nActive do
            local title, isComplete = GetActiveTitle(i)
            if addon.QuestAutoTurnIn(title) and isComplete then
                return SelectActiveQuest(i)
            end
        end

        if GossipGetNumOptions() == 0 and nAvailable == 1 and nActive == 0 then
            SelectAvailableQuest(1)
        else
            for i = 1, nAvailable do
                local title, isComplete = GetAvailableTitle(i)
                if addon.QuestAutoAccept(title) then
                    return SelectAvailableQuest(i)
                end
            end
        end
    elseif event == "GOSSIP_SHOW" then
        local nActive = GossipGetNumActiveQuests()
        local nAvailable = GossipGetNumAvailableQuests()
        local quests
        if C_GossipInfo.GetActiveQuests then
            quests = C_GossipInfo.GetActiveQuests()
        end
        for i = 1, nActive do
            local title, level, isTrivial, isComplete
            if type(quests) == "table" then
                title = quests[i].questID
                isComplete = quests[i].isComplete
            else
                title, level, isTrivial, isComplete = select(i * 6 - 5,
                                                             GossipGetActiveQuests())
            end
            -- print(title)
            -- print(quests[i])
            if addon.QuestAutoTurnIn(title) and isComplete then
                return GossipSelectActiveQuest(i)
            end
        end

        if GossipGetNumOptions() == 0 and nAvailable == 1 and nActive == 0 then
            GossipSelectAvailableQuest(1)
        else
            local availableQuests
            if C_GossipInfo.GetAvailableQuests then
                availableQuests = C_GossipInfo.GetAvailableQuests()
            end
            for i = 1, nAvailable do
                local quest
                if type(availableQuests) == "table" then
                    quest = availableQuests[i].questID
                else
                    quest = select(i * 7 - 6, GossipGetAvailableQuests())
                end
                if addon.QuestAutoAccept(quest) then
                    return GossipSelectAvailableQuest(i)
                end
            end
        end
    end
end

function addon:OnInitialize()
    RXPG_init()
    local importGuidesDefault = {profile = {guides = {}}}
    addon.db = LibStub("AceDB-3.0"):New("RXPDB", importGuidesDefault, 'global')
    addon.RXPG.LoadEmbeddedGuides()
    addon.RXPG.LoadCachedGuides()

    -- TODO setting
    addon.enableTracker = true
    addon.enableTrackerReport = false

    addon.RXPFrame.GenerateMenuTable()
    addon.CreateOptionsPanel()
    ProcessSpells()
    addon.GetProfessionLevel()
    local guide = addon.GetGuideTable(RXPCData.currentGuideGroup,
                                      RXPCData.currentGuideName)
    if not guide and RXPData.autoLoadGuides then
        guide = addon.defaultGuide
        if addon.game == "TBC" and
            (UnitLevel("player") == 58 and not guide.boost58) then
            guide = nil
        end
    end
    addon:LoadGuide(guide, true)
    if not addon.currentGuide then
        addon.RXPFrame:SetHeight(20)
        addon.RXPFrame.BottomFrame.UpdateFrame()
        addon.noGuide = true
    end

    if addon.enableTracker then addon.tracker.SetupTracker() end
end

function addon:OnEnable()
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("QUEST_TURNED_IN")
    -- self:RegisterEvent("SKILL_LINES_CHANGED")
    self:RegisterEvent("TRAINER_CLOSED")
    self:RegisterEvent("TAXIMAP_OPENED")
    self:RegisterEvent("PLAYER_LEVEL_UP")
    self:RegisterEvent("TRAINER_SHOW")
    self:RegisterEvent("UNIT_PET")
    self:RegisterEvent("PLAYER_CONTROL_LOST")
    self:RegisterEvent("PLAYER_CONTROL_GAINED")
    -- self:RegisterEvent("QUEST_LOG_UPDATE")

    questFrame:RegisterEvent("QUEST_COMPLETE")
    questFrame:RegisterEvent("QUEST_PROGRESS")
    questFrame:RegisterEvent("QUEST_ACCEPT_CONFIRM")
    questFrame:RegisterEvent("QUEST_GREETING")
    questFrame:RegisterEvent("GOSSIP_SHOW")
    questFrame:RegisterEvent("QUEST_DETAIL")
    questFrame:RegisterEvent("QUEST_TURNED_IN")

    if C_QuestLog.RequestLoadQuestByID then
        self:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    end

    if _G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC then
        self:RegisterEvent("UNIT_AURA")
    end
end

function addon:GET_ITEM_INFO_RECEIVED(_, itemNumber, success)
    if not success then return end

    if addon.itemQueryList[itemNumber] then
        addon.itemQueryList[itemNumber] = nil
        addon.updateStepText = true
    elseif GetTime() - startTime < 15 then
        addon.updateStepText = true
    end
end

function addon:BAG_UPDATE_DELAYED(...) addon.UpdateItemFrame() end

function addon:PLAYER_REGEN_ENABLED(...) addon.UpdateItemFrame() end

function addon:QUEST_TURNED_IN(_, questId, xpReward)
    if questId == 10551 or questId == 10552 then
        C_Timer.After(1, function() addon.ReloadGuide() end) -- scryer/aldor quest
    end
end

function addon:SKILL_LINES_CHANGED(...) addon.UpdateSkillData() end

function addon:TRAINER_SHOW(...)
    trainerUpdate = GetTime()
    OnTrainer()
    if not addon.trainerFrame then
        addon.trainerFrame = CreateFrame("Frame", "RXPGuidesTrainerFrame",
                                         UIParent)
    end

    addon.trainerFrame:SetScript("OnUpdate", trainerFrameUpdate)
end

function addon:TRAINER_CLOSED(...) addon.trainerFrame:SetScript("OnUpdate", nil) end

function addon:PLAYER_LEVEL_UP(_, level)
    if not addon.currentGuide then return end

    level = level
    local stepn = RXPCData.currentStep
    ProcessSpells()
    -- addon:LoadGuide(addon.currentGuide)
    addon.SetStep(1)
    addon.SetStep(stepn)
end

function addon:UNIT_AURA(_, unit)
    if unit ~= "player" then return end
    SoMCheck()
end

function addon:UNIT_PET(_, unit)
    if unit ~= "player" then return end
    addon.petFamily = GetPetIcon() or addon.petFamily
end

function addon:QUEST_DATA_LOAD_RESULT(_, questId, success)
    if not success then return end

    addon.requestQuestInfo[questId] = 0
    addon.updateStepText = true
end

questFrame:SetScript("OnEvent", addon.QuestAutomation)

function addon.GetGuideTable(guideGroup, guideName)
    if guideGroup and addon.guideList[guideGroup] and guideName and
        addon.guideList[guideGroup][guideName] then
        return addon.guides[addon.guideList[guideGroup][guideName]]
    end
end

function addon.UnitScanUpdate()
    local unitscanList = addon.currentGuide.unitscan
    if _G.unitscan_targets and unitscanList and not RXPData.disableUnitscan then
        for unit, elements in pairs(unitscanList) do
            local enabled
            for _, element in pairs(elements) do
                if element.step.active then
                    enabled = true
                    break
                end
            end

            if enabled then
                if not _G.unitscan_targets[unit] then
                    _G.DEFAULT_CHAT_FRAME:AddMessage(
                        _G.LIGHTYELLOW_FONT_COLOR_CODE .. '<unitscan> +' .. unit)
                end
                _G.unitscan_targets[unit] = true
            else
                if _G.unitscan_targets[unit] then
                    _G.DEFAULT_CHAT_FRAME:AddMessage(
                        _G.LIGHTYELLOW_FONT_COLOR_CODE .. '<unitscan> -' .. unit)
                end
                _G.unitscan_targets[unit] = nil
            end

        end
    end
end

addon.scheduledTasks = {}

function addon.UpdateScheduledTasks()
    local cTime = GetTime()
    for ref, time in pairs(addon.scheduledTasks) do
        if cTime > time then
            local group = addon.currentGuide.group
            local element = ref.element or ref
            RXPGuides[group][element.tag](ref)
            addon.scheduledTasks[ref] = nil
            return
        end
    end
end

function addon.ScheduleTask(ref, time)
    if type(ref) == "table" and type(time) == "number" then
        addon.scheduledTasks[ref] = time
    end
end

addon.updateActiveQuest = {}
addon.updateInactiveQuest = {}

addon.tickTimer = 0

local updateFrame = CreateFrame("Frame")

local eventType
local updateTick = 0
local updateStart = 0

local skip = 0
updateFrame:SetScript("OnUpdate", function(self, diff)

    updateTick = updateTick + diff
    if updateTick > (0.05+math.random()/128) then
        local currentTime = GetTime()
        updateTick = 0
        updateStart = currentTime
        local activeQuestUpdate = 0
        skip = skip + 1
        local event = ""

        if not addon.loadNextStep then
            for ref, func in pairs(addon.updateActiveQuest) do
                func(ref)
                addon.updateActiveQuest[ref] = nil
                activeQuestUpdate = activeQuestUpdate + 1
            end
            if activeQuestUpdate > 0 then event = event .. "/activeQ" end
        end
        if addon.nextStep then
            skip = 1
            addon.SetStep(addon.nextStep)
            addon.questAutoAccept = true
            addon.updateBottomFrame = true
            addon.nextStep = false
        elseif addon.loadNextStep then
            addon.loadNextStep = false
            addon.SetStep(RXPCData.currentStep + 1)
            addon.questAutoAccept = true
            skip = 1
            addon.updateBottomFrame = true
            event = event .. "/loadNext"
        elseif activeQuestUpdate == 0 then
            if addon.updateSteps then
                addon.UpdateStepCompletion()
                event = event .. "/stepComplete"
            elseif addon.updateStepText and addon.currentGuide and skip % 2 == 1 then
                addon.updateStepText = false
                local updateText
                local steps = addon.currentGuide.steps
                for n in pairs(addon.stepUpdateList) do
                    if steps[n] then
                        if not updateText and steps[n].active then
                            updateText = true
                        end
                        addon.RXPFrame.BottomFrame.UpdateFrame(nil, nil, n)
                        if not addon.updateStepText then
                            addon.stepUpdateList[n] = nil
                        end
                    end
                end
                if updateText then
                    addon.RXPFrame.CurrentStepFrame.UpdateText()
                end
                event = event .. "/updateText"
            elseif addon.updateBottomFrame or currentTime - addon.tickTimer > 5 then
                addon.RXPFrame.BottomFrame.UpdateFrame()
                addon.RXPFrame.CurrentStepFrame.UpdateText()
                addon.RXPFrame.SetStepFrameAnchor()
                addon.tickTimer = currentTime
                event = event .. "/bottomFrame"
                skip = 1
            end
        else
            addon.UpdateItemCooldown()
        end

        if skip % 4 == 2 then
            if addon.questAutoAccept then
                addon.questAutoAccept = false
                addon.QuestAutomation()
            end
            if addon.updateMap then
                addon.UpdateMap()
                event = event .. "/map"
            elseif activeQuestUpdate == 0 then
                for ref, func in pairs(addon.updateInactiveQuest) do
                    activeQuestUpdate = activeQuestUpdate + 1
                    if activeQuestUpdate > 4 then
                        break
                    else
                        func(ref)
                        addon.updateInactiveQuest[ref] = nil
                    end
                end
                if activeQuestUpdate > 0 then
                    event = event .. "/inactiveQ"
                end
            end
        elseif skip % 4 == 0 then
            addon.UpdateGotoSteps()
            --event = event .. "/updateGoto"
        elseif skip % 4 == 3 then
            addon.UpdateScheduledTasks()
        end
        --[[if event ~= "" then
            eventType = event
            print(event)
        end]]
    end
end)

function addon.HardcoreToggle()
    if RXPCData and addon.game == "CLASSIC" then
        RXPCData.hardcore = not RXPCData.hardcore
        addon.RenderFrame()
        if addon.hardcoreButton then
            addon.hardcoreButton:SetChecked(RXPCData.hardcore)
        end
    end
end

function addon.GAToggle()
    if RXPCData and addon.farmGuides > 0 then
        RXPCData.GA = not RXPCData.GA
        addon.RenderFrame()
    end
end

function addon.AldorScryerCheck(faction)
    if addon.game == "CLASSIC" then return true end
    local _, _, _, _, _, aldorRep = GetFactionInfoByID(932)
    local _, _, _, _, _, scryerRep = GetFactionInfoByID(934)

    if aldorRep and scryerRep then
        if type(faction) == "table" then
            if faction.aldor then
                faction = "Aldor"
            elseif faction.scryer then
                faction = "Scryer"
            end
        end
        if faction == "Aldor" then
            return (aldorRep > scryerRep)
        elseif faction == "Scryer" then
            return (aldorRep < scryerRep)
        end
    end
    return true
end

function addon.PhaseCheck(phase)

    if type(phase) == "table" then
        phase = phase.phase
    end

    if phase and RXPCData and RXPCData.phase then
        local pmin, pmax
        pmin, pmax = phase:match("(%d+)%-(%d+)")
        if pmax then
            pmin = tonumber(pmin)
            pmax = tonumber(pmax)
        else
            pmin = tonumber(phase)
            pmax = 0xffff
        end
        if pmin and RXPCData.phase >= pmin and RXPCData.phase <= pmax then
            return true
        else
            return false
        end
    end

    return true
end

function addon.IsStepShown(step)
    return not(step.daily and RXPCData.skipDailies) and
            (RXPCData.northrendLM or not step.questguide) and
             addon.AldorScryerCheck(step) and
             addon.PhaseCheck(step) and addon.HardcoreCheck(step) and
             addon.SeasonCheck(step) and addon.XpRateCheck(step)
end

function addon.SeasonCheck(step)
    if RXPCData.SoM and step.era or step.som and not RXPCData.SoM or
        RXPCData.SoM and RXPCData.phase > 2 and step["era/som"] then
        return false
    end
    return true
end

function addon.HardcoreCheck(step)
    local hc = RXPCData.hardcore
    if step.softcore and hc or step.hardcore and not hc then return false end
    return true
end

function addon.XpRateCheck(step)
    if step.xprate then
        local xpmin,xpmax = 1,0xfff

        step.xprate:gsub("^([<>]?)%s*(%d+%.?%d*)%-?(%d*%.?%d*)",function(op,arg1,arg2)
            if op == "<" then
                xpmin = 0
                xpmax = tonumber(arg1) - 1e-4
            elseif op == ">" then
                xpmin = tonumber(arg1) + 1e-4
                xpmax = 0xfff
            else
                xpmin = tonumber(arg1) or xpmin
                xpmax = tonumber(arg2) or 0xfff
            end
        end)
        if RXPCData.xprate < xpmin or RXPCData.xprate > xpmax then
            return false
        end
    end
    return true
end
RXP = addon --debug purposes

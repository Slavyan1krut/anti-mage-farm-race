local config = require("race_config")
local LaneWaves = require("lane_waves")
local heroName = "npc_dota_hero_antimage"
local startingItems = {"item_bfury", "item_power_treads"}
local raceAbilities = {"antimage_mana_break", "antimage_blink"}
local runeModels = {
    "rune_arcane", "rune_doubledamage01", "rune_goldxp", "rune_haste01", "rune_illusion01",
    "rune_invisibility01", "rune_point001", "rune_regeneration01", "rune_shield01", "rune_water", "rune_xp",
}
local disabledAbilities = {"antimage_counterspell_ally", "antimage_counterspell", "antimage_mana_overload", "antimage_mana_void", "antimage_persecutor"}
-- Radiant and Dire are reserved for the map so every racer can attack both waves.
local teams = {
    DOTA_TEAM_CUSTOM_1, DOTA_TEAM_CUSTOM_2, DOTA_TEAM_CUSTOM_3,
    DOTA_TEAM_CUSTOM_4, DOTA_TEAM_CUSTOM_5,
}
local colors = {
    {85, 210, 160}, {240, 110, 105}, {100, 165, 255}, {240, 195, 80}, {200, 135, 240},
}
local packs = {
    {"npc_dota_neutral_kobold_taskmaster", "npc_dota_neutral_kobold_tunneler", "npc_dota_neutral_kobold", "npc_dota_neutral_kobold"},
    {"npc_dota_neutral_forest_troll_berserker", "npc_dota_neutral_forest_troll_berserker", "npc_dota_neutral_forest_troll_high_priest", "npc_dota_neutral_kobold"},
    {"npc_dota_neutral_satyr_trickster", "npc_dota_neutral_satyr_trickster", "npc_dota_neutral_satyr_soulstealer", "npc_dota_neutral_kobold"},
}
local goldPack = {"npc_dota_neutral_kobold", "npc_dota_neutral_kobold", "npc_dota_neutral_kobold", "npc_dota_neutral_kobold"}
local goldLocations = {
    {x = -1720, y = 1110, name = "верхняя часть реки"},
    {x = 1450, y = -1260, name = "нижняя часть реки"},
}
local botPreferences = {"lane", "gold", "forest", "balanced", "forest"}
local fallbackCamps = {
    {-4650, -480}, {-3250, -780}, {-1450, -1600}, {280, -2750}, {1080, -4400},
    {2520, -3070}, {4150, -2070}, {5500, -1130}, {4500, 1210}, {2840, 1110},
    {2500, 3250}, {860, 4270}, {-860, 2530}, {-2720, 3520}, {-4180, 2330},
}

local Race = {}

function Precache(context)
    PrecacheUnitByNameSync(heroName, context)
    for _, item in ipairs(startingItems) do PrecacheItemByNameSync(item, context) end
    for _, model in ipairs(runeModels) do
        PrecacheResource("model", "models/props_gameplay/" .. model .. ".vmdl", context)
    end
    LaneWaves.Precache(context)
    local cached = {}
    for _, pack in ipairs(packs) do
        for _, name in ipairs(pack) do
            if not cached[name] then
                PrecacheUnitByNameSync(name, context)
                cached[name] = true
            end
        end
    end
end

function Activate()
    GameRules.FarmRace = setmetatable({}, {__index = Race})
    GameRules.FarmRace:Init()
end

function Race:Init()
    self.slots = {}
    self.heroSlots = {}
    self.creeps = {}
    self.camps = {}
    self.laneWaves = {}
    self.goldCamps = {}
    for index, team in ipairs(teams) do
        self.slots[index] = {index = index, team = team, score = 0, reached = 0, farm = {lane = 0, forest = 0, gold = 0}}
        GameRules:SetCustomGameTeamMaxPlayers(team, 1)
        SetTeamCustomHealthbarColor(team, unpack(colors[index]))
    end
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 0)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
    for team = DOTA_TEAM_CUSTOM_6, DOTA_TEAM_CUSTOM_8 do
        GameRules:SetCustomGameTeamMaxPlayers(team, 0)
    end

    GameRules:SetIgnoreLobbyTeamsInCustomGame(true)
    self.lan = Convars:GetBool("sv_lan")
    GameRules:EnableCustomGameSetupAutoLaunch(not self.lan)
    GameRules:SetCustomGameSetupTimeout(self.lan and -1 or 0)
    GameRules:SetCustomGameSetupAutoLaunchDelay(0)
    GameRules:SetSameHeroSelectionEnabled(true)
    GameRules:SetHeroSelectionTime(8)
    GameRules:SetStrategyTime(0)
    GameRules:SetShowcaseTime(0)
    GameRules:SetPreGameTime(8)
    GameRules:SetStartingGold(0)
    GameRules:SetGoldPerTick(0)
    GameRules:SetCreepSpawningEnabled(false)
    GameRules:SetCustomVictoryMessageDuration(4)

    local mode = GameRules:GetGameModeEntity()
    mode:SetCustomGameForceHero(heroName)
    mode:SetAnnouncerDisabled(true)
    mode:SetDamageFilter(function(_, event) return self:DamageAllowed(event) end, self)
    mode:SetExecuteOrderFilter(function(_, event) return self:OrderAllowed(event) end, self)
    mode:SetModifyGoldFilter(function() return false end, self)
    mode:SetModifyExperienceFilter(function() return false end, self)
    mode:SetThink(function() return self:Think() end, "FarmRaceThink", 0.25)

    ListenToGameEvent("game_rules_state_change", function() self:OnStateChange() end, nil)
    ListenToGameEvent("entity_killed", function(event) self:OnKilled(event) end, nil)
    ListenToGameEvent("player_chat", function(event) self:OnChat(event) end, nil)
    print("[Farm Race] Addon loaded, LAN=" .. tostring(self.lan))
end

local function Tell(message)
    GameRules:SendCustomMessage(message, 0, -1)
    print("[Farm Race] " .. message)
end

local function Announce(message, duration)
    FireGameEvent("show_center_message", {message = message, duration = duration})
end

local function FlatDistance(first, second)
    return (first - second):Length2D()
end

local function WalkableNear(origin)
    for radius = 0, 384, 64 do
        for direction = 0, 7 do
            local angle = direction * math.pi / 4
            local point = GetGroundPosition(origin + Vector(math.cos(angle) * radius, math.sin(angle) * radius, 0), nil)
            if GridNav:IsTraversable(point) and not GridNav:IsBlocked(point) then
                return point
            end
        end
    end
end

function Race:FindCamps()
    local anchors = {}
    for _, spawner in ipairs(Entities:FindAllByClassname("npc_dota_neutral_spawner")) do
        table.insert(anchors, spawner:GetAbsOrigin())
        spawner:RemoveSelf()
    end
    if #anchors < #teams then
        for _, point in ipairs(fallbackCamps) do
            table.insert(anchors, Vector(point[1], point[2], 0))
        end
    end
    table.sort(anchors, function(a, b)
        if a.x == b.x then return a.y < b.y end
        return a.x < b.x
    end)
    local center = WalkableNear(Vector(0, 0, 0))
    for _, anchor in ipairs(anchors) do
        local point = WalkableNear(anchor)
        if point and (not center or GridNav:CanFindPath(center, point)) then
            local distinct = true
            for _, camp in ipairs(self.camps) do
                if FlatDistance(camp.point, point) < 375 then distinct = false break end
            end
            if distinct then
                table.insert(self.camps, {point = point, units = {}, alive = 0, nextSpawn = 0})
            end
        end
    end
    print(string.format("[Farm Race] %d camps from %d anchors", #self.camps, #anchors))
end

function Race:SpawnCamp(camp, pack)
    camp.units = {}
    for offset, name in ipairs(pack) do
        local angle = offset * math.pi / 2
        local point = WalkableNear(camp.point + Vector(math.cos(angle) * 66, math.sin(angle) * 66, 0)) or camp.point
        local creep = CreateUnitByName(name, point, true, nil, nil, DOTA_TEAM_NEUTRALS)
        if creep then
            if camp.gold then creep:SetCustomHealthLabel("+2", 255, 211, 99) end
            local id = creep:entindex()
            camp.units[id] = creep
            self.creeps[id] = camp
            camp.alive = camp.alive + 1
        end
    end
    if not camp.gold then camp.nextSpawn = GameRules:GetGameTime() + config.campRespawn end
end

function Race:SetupGoldCamps(now)
    local center = WalkableNear(Vector(0, 0, 0))
    for index, time in ipairs(config.goldCampTimes) do
        local location = goldLocations[index]
        if location and time < config.duration then
            local anchor = Vector(location.x, location.y, 0)
            local point
            for radius = 0, 960, 160 do
                for direction = 0, 7 do
                    local angle = direction * math.pi / 4
                    local candidate = WalkableNear(anchor + Vector(math.cos(angle) * radius, math.sin(angle) * radius, 0))
                    if candidate then
                        local clear = true
                        for _, camp in ipairs(self.camps) do
                            if FlatDistance(candidate, camp.point) < 380 then clear = false break end
                        end
                        if clear and (not center or GridNav:CanFindPath(center, candidate)) then point = candidate break end
                    end
                end
                if point then break end
            end
            if point then
                local spawnAt = now + time
                self.goldCamps[#self.goldCamps + 1] = {
                    point = point, name = location.name, gold = true, alive = 0,
                    spawnAt = spawnAt, warnAt = math.max(now, spawnAt - config.goldCampWarning),
                }
            else
                print("[Farm Race] Could not place gold camp: " .. location.name)
            end
        end
    end
end

function Race:MarkGoldCamp(camp, duration)
    for _, slot in ipairs(self.slots) do
        if slot.hero then
            MinimapEvent(slot.team, slot.hero, camp.point.x, camp.point.y, DOTA_MINIMAP_EVENT_HINT_LOCATION, duration)
        end
    end
end

function Race:UpdateGoldCamps(now)
    for _, camp in ipairs(self.goldCamps) do
        if camp.warnAt and now >= camp.warnAt then
            camp.warnAt = nil
            local remaining = math.max(1, math.ceil(camp.spawnAt - now))
            local message = string.format("Золотой лагерь через %d сек. · %s", remaining, camp.name)
            Announce(message, 4)
            Tell(message)
            self:MarkGoldCamp(camp, remaining)
        end
        if camp.spawnAt and now >= camp.spawnAt then
            camp.spawnAt = nil
            self:SpawnCamp(camp, goldPack)
            self:MarkGoldCamp(camp, 6)
            local message = "Золотой лагерь открыт · " .. camp.name
            Announce(message, 4)
            Tell(message)
        end
    end
end

function Race:OnStateChange()
    local state = GameRules:State_Get()
    if state == DOTA_GAMERULES_STATE_HERO_SELECTION then
        self:AssignParticipants()
    elseif state == DOTA_GAMERULES_STATE_PRE_GAME then
        self:FindCamps()
        self.laneRoutes = LaneWaves.GetRoutes()
    elseif state == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        self:Start()
    end
end

function Race:AssignParticipants()
    local index = 1
    for id = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(id) and PlayerResource:GetPlayer(id)
            and PlayerResource:GetConnectionState(id) == DOTA_CONNECTION_STATE_CONNECTED then
            local team = teams[index]
            if not team then break end
            if PlayerResource:GetCustomTeamAssignment(id) ~= team then
                PlayerResource:SetCustomTeamAssignment(id, team)
                print(string.format("[Farm Race] Player %d assigned to team %d", id, team))
            end
            index = index + 1
        end
    end
end

function Race:Start()
    self:SetupGoldCamps(GameRules:GetGameTime())
    local occupied = {}
    for id = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(id) then
            local hero = PlayerResource:GetSelectedHeroEntity(id)
            if hero and hero:GetUnitName() == heroName then occupied[hero:GetTeamNumber()] = hero end
        end
    end

    local previousSpawns = {}
    local center = Vector(0, 0, 0)
    local botCount = 0
    for _, slot in ipairs(self.slots) do
        local spawn = center
        local bestDistance = -math.huge
        for _, camp in ipairs(self.camps) do
            local separation = #previousSpawns == 0 and -FlatDistance(camp.point, center) or math.huge
            for _, other in ipairs(previousSpawns) do
                separation = math.min(separation, FlatDistance(camp.point, other))
            end
            if separation > bestDistance then
                bestDistance = separation
                spawn = camp.point
            end
        end
        table.insert(previousSpawns, spawn)
        slot.spawn = WalkableNear(spawn + Vector(240, 0, 0)) or spawn
        slot.hero = occupied[slot.team]
        slot.bot = slot.hero == nil
        if slot.bot then
            botCount = botCount + 1
            slot.preference = botPreferences[botCount]
            slot.hero = CreateUnitByName(heroName, slot.spawn, true, nil, nil, slot.team)
        else
            FindClearSpaceForUnit(slot.hero, slot.spawn, true)
            PlayerResource:SetCameraTarget(slot.hero:GetPlayerOwnerID(), slot.hero)
        end
        if slot.hero then
            self:PrepareHero(slot)
        else
            print("[Farm Race] Could not create Anti-Mage for slot " .. slot.index)
        end
    end

    for index, camp in ipairs(self.camps) do self:SpawnCamp(camp, packs[(index - 1) % #packs + 1]) end
    local now = GameRules:GetGameTime()
    self.endsAt = now + config.duration
    self.nextLaneWaveAt = now + config.laneWaveInterval
    LaneWaves.Spawn(self.laneRoutes, self.creeps, self.laneWaves)
    self.nextUpdate = now + config.scoreboardInterval
    self.releaseCameraAt = now + 0.6
    self:PublishStandings(self:Standings())
    local duration = string.format("%d:%02d", math.floor(config.duration / 60), config.duration % 60)
    Announce("Гонка началась! " .. duration, 3)
    Tell("Крипы на линии и в лесу — 1 очко, золотые — 2. Счёт и таймер: -score")
end

function Race:PrepareHero(slot)
    local hero = slot.hero
    self.heroSlots[hero:entindex()] = slot
    for _, item in ipairs(startingItems) do
        if not hero:HasItemInInventory(item) then hero:AddItemByName(item) end
    end
    for level = hero:GetLevel(), 7 do hero:HeroLevelUp(false) end
    for _, name in ipairs(disabledAbilities) do
        if hero:FindAbilityByName(name) then hero:RemoveAbility(name) end
    end
    local ranks = {}
    for _, name in ipairs(raceAbilities) do
        local ability = hero:FindAbilityByName(name)
        if ability then ability:SetLevel(ability:GetMaxLevel()) end
        table.insert(ranks, ability and ability:GetLevel() or 0)
    end
    if slot.bot then
        hero:SetIdleAcquire(false)
        hero:SetAcquisitionRange(0)
    end
    hero:SetAbilityPoints(0)
    hero:SetHealth(hero:GetMaxHealth())
    hero:SetMana(hero:GetMaxMana())
    print(string.format("[Farm Race] slot=%d team=%d bot=%s battlefury=%s treads=%s mana_break=%d blink=%d",
        slot.index, slot.team, tostring(slot.bot), tostring(hero:HasItemInInventory("item_bfury")),
        tostring(hero:HasItemInInventory("item_power_treads")), ranks[1], ranks[2]))
end

function Race:OrderAllowed(event)
    if event.order_type ~= DOTA_UNIT_ORDER_ATTACK_TARGET then return true end
    local target = event.entindex_target
    for _, unit in pairs(event.units or {}) do
        local slot = self.heroSlots[unit]
        if slot and (self.heroSlots[target] or (slot.bot and not self.creeps[target])) then return false end
    end
    return true
end

function Race:DamageAllowed(event)
    local attacker = event.entindex_attacker_const and EntIndexToHScript(event.entindex_attacker_const)
    local victim = event.entindex_victim_const and EntIndexToHScript(event.entindex_victim_const)
    if not attacker or not victim then return true end
    if victim:IsBuilding() then return false end
    if attacker:IsBuilding() then
        local wave = self.creeps[victim:entindex()]
        return attacker:IsTower() and self.endsAt ~= nil and not self.finished
            and wave ~= nil and wave.point == nil and attacker:GetTeamNumber() ~= victim:GetTeamNumber()
    end
    local racer = self.heroSlots[attacker:entindex()]
    if racer then return self.endsAt ~= nil and not self.finished and self.creeps[victim:entindex()] ~= nil end
    if self.heroSlots[victim:entindex()] then
        return self.endsAt ~= nil and not self.finished and self.creeps[attacker:entindex()] ~= nil
    end
    return true
end

function Race:OnKilled(event)
    local now = GameRules:GetGameTime()
    local group = self.creeps[event.entindex_killed]
    if group then
        self.creeps[event.entindex_killed] = nil
        group.units[event.entindex_killed] = nil
        group.alive = group.alive - 1
        if group.alive == 0 and group.point and not group.gold then group.nextSpawn = now + config.campRespawn end
        local slot = self.heroSlots[event.entindex_attacker]
        if slot and self.endsAt and now < self.endsAt and not self.finished then
            local kind = group.gold and "gold" or (group.point and "forest" or "lane")
            local points = group.gold and 2 or 1
            slot.farm[kind] = slot.farm[kind] + points
            slot.score = slot.score + points
            slot.reached = now
            self.standingsChanged = true
        end
    end
    local slot = self.heroSlots[event.entindex_killed]
    if slot and not self.finished then
        slot.respawnAt = now + config.heroRespawn
        slot.hero:SetTimeUntilRespawn(9999)
    end
end

local function FarmPosition(group)
    if group.point then return group.point end
    for _, creep in pairs(group.units) do
        if not creep:IsNull() and creep:IsAlive() then return creep:GetAbsOrigin() end
    end
end

local function TryBotBlink(slot, origin, point, now)
    local hero = slot.hero
    local direction = point - origin
    local distance = direction:Length2D()
    if distance < 700 then return false end
    local blink = hero:FindAbilityByName("antimage_blink")
    if not blink or not blink:IsFullyCastable() or hero:IsRooted() or hero:IsSilenced() then return false end
    local range = blink:GetSpecialValueFor("AbilityCastRange")
    if range <= 0 then range = 1000 end

    local approach = WalkableNear(point) or point
    local walkDistance = GridNav:FindPathLength(origin, approach)
    for _, fraction in ipairs({1, 0.75, 0.5}) do
        local step = math.min(range - 30, distance - 130) * fraction
        local landing = WalkableNear(origin + direction * (step / distance))
        if landing and FlatDistance(origin, landing) <= range - 15 then
            local remaining = GridNav:FindPathLength(landing, approach)
            local savesTime = remaining >= 0 and (walkDistance <= 0 or walkDistance - remaining > 350)
            if savesTime then
                ExecuteOrderFromTable({
                    UnitIndex = hero:entindex(), OrderType = DOTA_UNIT_ORDER_CAST_POSITION,
                    AbilityIndex = blink:entindex(), Position = landing, Queue = false,
                })
                slot.blinkUntil = now + 0.9
                slot.repeatOrderAt = slot.blinkUntil
                return true
            end
        end
    end
    return false
end

function Race:DriveBot(slot, now)
    if now < (slot.blinkUntil or 0) then return end
    local hero = slot.hero
    local origin = hero:GetAbsOrigin()
    local camp = slot.targetCamp
    if camp and slot.checkProgressAt and now >= slot.checkProgressAt then
        local moved = FlatDistance(origin, slot.lastPosition) >= 90
        if not moved and slot.score == slot.lastScore then
            slot.skippedCamp = camp
            slot.skipUntil = now + 12
            camp = nil
        end
        slot.checkProgressAt = nil
    end
    local seekGold = false
    if slot.preference == "gold" and (not camp or not camp.gold) then
        for _, gold in ipairs(self.goldCamps) do
            if gold.alive > 0 and (gold ~= slot.skippedCamp or now >= slot.skipUntil) then seekGold = true break end
        end
    end
    if not camp or camp.alive == 0 or seekGold then
        local bestDistance = math.huge
        camp = nil
        for kind, groups in pairs({forest = self.camps, lane = self.laneWaves, gold = self.goldCamps}) do
            for _, candidate in ipairs(groups) do
                if candidate.alive > 0 and (candidate ~= slot.skippedCamp or now >= slot.skipUntil) then
                    local point = FarmPosition(candidate)
                    if point then
                        local distance = GridNav:FindPathLength(origin, point)
                        if distance <= 0 then distance = 15000 + FlatDistance(origin, point) end
                        if kind == slot.preference then distance = distance * 0.65 end
                        if kind == "gold" then distance = distance * 0.8 end
                        if seekGold and kind ~= "gold" then distance = distance + 20000 end
                        if distance < bestDistance then
                            bestDistance = distance
                            camp = candidate
                        end
                    end
                end
            end
        end
        if slot.targetCamp ~= camp then slot.checkProgressAt = nil end
        slot.targetCamp = camp
    end

    if not camp then return end
    if not slot.checkProgressAt then
        slot.lastPosition = origin
        slot.lastScore = slot.score
        slot.checkProgressAt = now + 12
    end
    local target
    local closest = 475
    local ordered = slot.orderedTarget
    if slot.orderedCamp == camp and ordered and not ordered:IsNull() and ordered:IsAlive()
        and self.creeps[ordered:entindex()] == camp and hero:CanEntityBeSeenByMyTeam(ordered) then
        target = ordered
        closest = 0
    end
    for _, creep in pairs(camp.units) do
        if not creep:IsNull() and creep:IsAlive() then
            local distance = FlatDistance(origin, creep:GetAbsOrigin())
            if distance < closest and hero:CanEntityBeSeenByMyTeam(creep) then
                closest = distance
                target = creep
            end
        end
    end
    if slot.orderedCamp == camp and slot.orderedTarget == target and now < slot.repeatOrderAt then return end
    slot.orderedCamp = camp
    slot.orderedTarget = target
    slot.repeatOrderAt = now + (camp.point and 4 or 1.5)
    if target then
        ExecuteOrderFromTable({
            UnitIndex = hero:entindex(), OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
            TargetIndex = target:entindex(), Queue = false,
        })
    else
        local point = FarmPosition(camp)
        if not point then return end
        if TryBotBlink(slot, origin, point, now) then return end
        ExecuteOrderFromTable({
            UnitIndex = hero:entindex(), OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
            Position = point, Queue = false,
        })
    end
end

function Race:Standings()
    local ranked = {unpack(self.slots)}
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.reached ~= b.reached then return a.reached < b.reached end
        return a.index < b.index
    end)
    return ranked
end

function Race:Label(slot)
    if slot.bot or not slot.hero then return "Бот " .. slot.index end
    local name = PlayerResource:GetPlayerName(slot.hero:GetPlayerOwnerID()) or ""
    name = name:gsub("[<>&]", "")
    if name == "" then return "AM " .. slot.index end
    return name
end

function Race:Report(now)
    local lines = {}
    for _, slot in ipairs(self:Standings()) do
        table.insert(lines, self:Label(slot) .. " — " .. slot.score)
    end
    local remaining = math.max(0, math.ceil(self.endsAt - now))
    Tell(string.format("%d:%02d | %s", math.floor(remaining / 60), remaining % 60, table.concat(lines, "  /  ")))
end

function Race:PublishStandings(ranked)
    local rows = {}
    for place, slot in ipairs(ranked) do
        rows[place] = {name = self:Label(slot), score = slot.score, farm = slot.farm, playerId = slot.bot and -1 or slot.hero:GetPlayerOwnerID()}
    end
    CustomNetTables:SetTableValue("farm_race", "standings", {rows = rows, finished = self.finished and 1 or 0})
    self.standingsChanged = false
end

function Race:OnChat(event)
    local command = event.text and event.text:lower()
    if self.lan and command == "-start" and GameRules:State_Get() == DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
        local id = event.playerid or event.PlayerID
        local player = id and PlayerResource:GetPlayer(id)
        if player and (id == 0 or GameRules:PlayerHasCustomGameHostPrivileges(player)) then
            self:AssignParticipants()
            GameRules:FinishCustomGameSetup()
        end
        return
    end
    local now = GameRules:GetGameTime()
    if self.endsAt and (command == "-score" or command == "-time") and now >= (self.nextChatReport or 0) then
        self.nextChatReport = now + 2
        self:Report(now)
    end
end

function Race:Finish(now)
    self.finished = true
    self:Report(now)
    local ranked = self:Standings()
    local winner = ranked[1]
    local result = string.format("Победитель: %s — %d очк.", self:Label(winner), winner.score)
    Tell(result)
    Announce(result, 5)
    self:PublishStandings(ranked)
    GameRules:SetCustomVictoryMessage("#farm_race_results")
    GameRules:GetGameModeEntity():SetContextThink("FarmRacePostGame", function()
        GameRules:SetGameWinner(winner.team)
        return nil
    end, 12)
end

function Race:Think()
    if self.finished then return nil end
    if not self.endsAt then
        if self.lan and GameRules:State_Get() == DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
            self:AssignParticipants()
            return 1
        end
        return 0.25
    end
    local now = GameRules:GetGameTime()
    if now >= self.endsAt then
        self:Finish(now)
        return nil
    end
    if now >= self.nextLaneWaveAt then
        LaneWaves.Spawn(self.laneRoutes, self.creeps, self.laneWaves)
        self.nextLaneWaveAt = self.nextLaneWaveAt + config.laneWaveInterval
    end
    self:UpdateGoldCamps(now)
    if self.standingsChanged then self:PublishStandings(self:Standings()) end
    if self.releaseCameraAt and now >= self.releaseCameraAt then
        for _, slot in ipairs(self.slots) do
            if not slot.bot then PlayerResource:SetCameraTarget(slot.hero:GetPlayerOwnerID(), nil) end
        end
        self.releaseCameraAt = nil
    end
    if now >= self.nextUpdate then
        self:Report(now)
        self.nextUpdate = now + config.scoreboardInterval
    end
    if not self.closingWarning and now >= self.endsAt - 10 then
        self.closingWarning = true
        Announce("До финиша 10 секунд", 3)
    end
    for index, camp in ipairs(self.camps) do
        if camp.alive == 0 and now >= camp.nextSpawn then self:SpawnCamp(camp, packs[(index - 1) % #packs + 1]) end
    end
    for _, slot in ipairs(self.slots) do
        if slot.respawnAt and now >= slot.respawnAt then
            slot.hero:RespawnHero(false, false)
            FindClearSpaceForUnit(slot.hero, slot.spawn, true)
            slot.respawnAt = nil
            slot.targetCamp = nil
            slot.orderedCamp = nil
            slot.checkProgressAt = nil
        end
        if slot.bot and slot.hero and slot.hero:IsAlive() and now >= (slot.nextOrder or 0) then
            self:DriveBot(slot, now)
            slot.nextOrder = now + 0.6
        end
    end
    return 0.25
end

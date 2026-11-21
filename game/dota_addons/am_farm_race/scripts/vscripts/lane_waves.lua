local LaneWaves = {}

local sides = {
    {name = "good", team = DOTA_TEAM_GOODGUYS},
    {name = "bad", team = DOTA_TEAM_BADGUYS},
}
local lanes = {"top", "mid", "bot"}
local meleeCount = 4

local function UnitName(side, role)
    return "npc_dota_creep_" .. side.name .. "guys_" .. role
end

function LaneWaves.Precache(context)
    for _, side in ipairs(sides) do
        PrecacheUnitByNameSync(UnitName(side, "melee"), context)
        PrecacheUnitByNameSync(UnitName(side, "ranged"), context)
    end
end

function LaneWaves.GetRoutes()
    local routes = {}
    for _, lane in ipairs(lanes) do
        for _, side in ipairs(sides) do
            local spawner = Entities:FindByClassname(nil, "npc_dota_spawner_" .. side.name .. "_" .. lane)
            local goal = Entities:FindByName(nil, "lane_" .. lane .. "_pathcorner_" .. side.name .. "guys_1")
            if spawner and goal then
                routes[#routes + 1] = {origin = spawner:GetAbsOrigin(), goal = goal, side = side}
            else
                print("[Farm Race] Missing lane route: " .. side.name .. " " .. lane)
            end
        end
    end
    return routes
end

function LaneWaves.Spawn(routes, trackedCreeps, activeWaves)
    for index = #activeWaves, 1, -1 do
        if activeWaves[index].alive == 0 then table.remove(activeWaves, index) end
    end

    local melee, ranged = 0, 0
    for _, route in ipairs(routes) do
        local wave = {units = {}, alive = 0}
        for index = 1, meleeCount + 1 do
            local role = index <= meleeCount and "melee" or "ranged"
            local creep = CreateUnitByName(UnitName(route.side, role), route.origin, true, nil, nil, route.side.team)
            if creep then
                creep:SetInitialGoalEntity(route.goal)
                creep:SetMustReachEachGoalEntity(true)
                local id = creep:entindex()
                wave.units[id] = creep
                trackedCreeps[id] = wave
                wave.alive = wave.alive + 1
                if role == "melee" then melee = melee + 1 else ranged = ranged + 1 end
            end
        end
        if wave.alive > 0 then activeWaves[#activeWaves + 1] = wave end
    end
    print(string.format("[Farm Race] Lane waves spawned: %d routes, %d melee, %d ranged", #routes, melee, ranged))
end

return LaneWaves

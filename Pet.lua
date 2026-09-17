-- Wick's Beasts and Things
-- Pet.lua: pet state and one-key feeding.
--
-- Forever moved the hunter pet reads under C_PetInfo. Happiness, loyalty,
-- training points and diet are all there, and CanPetEatItem answers the
-- question the old UI made players answer by hand: will my pet eat this?
-- The feed key is a secure button whose macro is rewritten out of combat
-- to "/cast Feed Pet" followed by "/use" of the chosen food.

local ADDON, ns = ...
local Core = WickCore
local D, R = Core.Dialect, Core.Restrict

local Pet = {}
ns.Pet = Pet

local getHappiness = (C_PetInfo and C_PetInfo.GetPetHappiness)      or rawget(_G, "GetPetHappiness")
local getLoyalty   = (C_PetInfo and C_PetInfo.GetPetLoyalty)        or rawget(_G, "GetPetLoyalty")
local getTraining  = (C_PetInfo and C_PetInfo.GetPetTrainingPoints) or rawget(_G, "GetPetTrainingPoints")
local getFoodTypes = (C_PetInfo and C_PetInfo.GetPetFoodTypes)      or rawget(_G, "GetPetFoodTypes")
local canEat       = C_PetInfo and C_PetInfo.CanPetEatItem

-- A pet refuses food more than thirty levels below it, and the happiness
-- per bite falls off in ten-level steps above that floor.
local FOOD_LEVEL_FLOOR = 30

Pet.HAPPINESS_TEXT = { [1] = "Unhappy", [2] = "Content", [3] = "Happy" }

local function plain(v)
    if v == nil or R:IsSecret(v) then return nil end
    return v
end

-- Diet as a list of strings on either API shape.
function Pet:Diet()
    if not getFoodTypes then return {} end
    local r = { pcall(getFoodTypes) }
    if not r[1] then return {} end
    if type(r[2]) == "table" then return r[2] end
    local diet = {}
    for i = 2, #r do if type(r[i]) == "string" then diet[#diet + 1] = r[i] end end
    return diet
end

-- Snapshot of the active pet. Nil fields mean the client would not say.
function Pet:State()
    local exists = UnitExists("pet") and true or false
    local s = { exists = exists }
    if not exists then return s end
    s.dead   = (UnitIsDead and UnitIsDead("pet")) and true or false
    s.name   = UnitName("pet")
    s.family = UnitCreatureFamily and UnitCreatureFamily("pet") or nil
    s.level  = plain(UnitLevel("pet"))
    if getHappiness then
        local ok, h, dmg, rate = pcall(getHappiness)
        if ok then
            s.happiness   = plain(h)
            s.damagePct   = plain(dmg)
            s.loyaltyRate = plain(rate)
        end
    end
    if getLoyalty then
        local ok, l = pcall(getLoyalty)
        if ok and type(l) == "string" then s.loyalty = l end
    end
    if getTraining then
        local ok, total, used = pcall(getTraining)
        if ok and type(total) == "number" then s.trainingTotal, s.trainingUsed = total, used end
    end
    s.diet = self:Diet()
    return s
end

-- ============================================================
-- Food
-- ============================================================

-- Every stack in the bags the pet will eat, with the level rule applied.
function Pet:Foods()
    local petLevel = plain(UnitLevel("pet")) or 1
    local seen, list = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = D.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = D.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] then
                local eats = false
                if canEat then
                    local ok, v = pcall(canEat, id)
                    eats = ok and v == true
                end
                if eats then
                    local it = D.GetItemInfo(id)
                    local ilvl = it and it.itemLevel or 0
                    if ilvl >= petLevel - FOOD_LEVEL_FLOOR then
                        seen[id] = true
                        list[#list + 1] = {
                            itemID = id, name = it and it.name or ("item " .. id), icon = it and it.icon,
                            itemLevel = ilvl, count = D.GetItemCount(id, false) or (info.stackCount or 1),
                        }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
        if a.count ~= b.count then return a.count > b.count end
        return a.itemID < b.itemID
    end)
    return list
end

-- The stack the feed key will use: the pinned item when it is in the bags,
-- otherwise the highest (or cheapest) eligible food.
function Pet:BestFood()
    local foods = self:Foods()
    if #foods == 0 then return nil end
    local db = ns.db and ns.db.profile
    if db and db.foodItem then
        for _, f in ipairs(foods) do if f.itemID == db.foodItem then f.pinned = true; return f end end
    end
    if db and db.preferCheap then return foods[#foods] end
    return foods[1]
end

-- ============================================================
-- Feed button
-- ============================================================

local buttons = {}
local pending = false

local function newSecure(name, parent)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    buttons[#buttons + 1] = b
    return b
end

-- Any secure button that should feed the pet registers here; the panel's
-- visible Feed button is one, the keybind's hidden button is another.
function Pet:RegisterFeedButton(b)
    buttons[#buttons + 1] = b
    b:SetAttribute("type", "macro")
    self:UpdateFeedMacro()
end

function Pet:UpdateFeedMacro()
    if InCombatLockdown() then pending = true return end
    pending = false
    local food = self:BestFood()
    local text = ""
    if food and UnitExists("pet") then
        text = ("/cast Feed Pet\n/use item:%d"):format(food.itemID)
    end
    self.lastMacro = text
    self.lastFood = food
    for _, b in ipairs(buttons) do b:SetAttribute("macrotext", text) end
    if ns.UI and ns.UI.RefreshFeed then ns.UI:RefreshFeed(food) end
end

function Pet:Init()
    if self.inited then return end
    self.inited = true
    -- The keybind's button. Kept shown at a single transparent pixel so a
    -- CLICK binding can reach it whether or not the panel is open.
    local kb = newSecure("WicksBeastsFeedButton", UIParent)
    kb:SetSize(1, 1)
    kb:SetPoint("CENTER")
    kb:SetAlpha(0)
    kb:EnableMouse(false)
    kb:Show()

    ns.RegisterEvents({ "UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE", "PET_BAR_UPDATE",
        "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UNIT_LEVEL" })
    ns:On("UNIT_PET", function(_, unit) if unit == "player" then Pet:UpdateFeedMacro(); if ns.UI then ns.UI:Refresh() end end end)
    ns:On("UNIT_HAPPINESS", function() if ns.UI then ns.UI:Refresh() end end)
    ns:On("PET_UI_UPDATE", function() if ns.UI then ns.UI:Refresh() end end)
    ns:On("PET_BAR_UPDATE", function() if ns.UI then ns.UI:Refresh() end end)
    ns:On("UNIT_LEVEL", function(_, unit) if unit == "pet" then Pet:UpdateFeedMacro() end end)
    ns:On("BAG_UPDATE_DELAYED", function() Pet:UpdateFeedMacro(); if ns.UI then ns.UI:Refresh() end end)
    ns:On("PLAYER_ENTERING_WORLD", function() Pet:UpdateFeedMacro(); if ns.UI then ns.UI:Refresh() end end)
    ns:On("PLAYER_REGEN_ENABLED", function() if pending then Pet:UpdateFeedMacro() end if ns.UI then ns.UI:Refresh() end end)
    self:UpdateFeedMacro()
end

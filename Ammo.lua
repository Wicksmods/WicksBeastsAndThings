-- Wick's Beasts and Things
-- Ammo.lua: what is in the ammo slot, how many, and whether it fits the weapon.
--
-- Forever keeps the ammo slot (inventory slot 0). The equipped stack count
-- comes from GetInventoryItemCount, spare stacks from the bags, and
-- C_PaperDollInfo.AmmoNeeded says whether the ranged weapon uses ammo at
-- all (thrown weapons and wands do not).

local ADDON, ns = ...
local Core = WickCore
local D, R = Core.Dialect, Core.Restrict

local Ammo = {}
ns.Ammo = Ammo

local INV_AMMO   = rawget(_G, "INVSLOT_AMMO") or 0
local INV_RANGED = rawget(_G, "INVSLOT_RANGED") or 18

-- Weapon subtype to the ammo subtype it fires.
local FIRES = {
    Bows = "Arrow", Crossbows = "Arrow", Guns = "Bullet",
}

local function plain(v)
    if v == nil or R:IsSecret(v) then return nil end
    return v
end

function Ammo:State()
    local s = { needed = true, count = 0, bagCount = 0 }
    if C_PaperDollInfo and C_PaperDollInfo.AmmoNeeded then
        local ok, v = pcall(C_PaperDollInfo.AmmoNeeded)
        if ok and v == false then s.needed = false end
    end

    local rangedID = GetInventoryItemID and GetInventoryItemID("player", INV_RANGED)
    if rangedID then
        local it = D.GetItemInfo(rangedID)
        s.weapon = it and it.name
        s.weaponType = it and it.itemSubType
        s.fires = s.weaponType and FIRES[s.weaponType] or nil
    end

    local id = GetInventoryItemID and GetInventoryItemID("player", INV_AMMO)
    s.itemID = id
    if id then
        local it = D.GetItemInfo(id)
        s.name = it and it.name or ("item " .. id)
        s.icon = it and it.icon
        s.ammoType = it and it.itemSubType
        if GetInventoryItemCount then
            local ok, n = pcall(GetInventoryItemCount, "player", INV_AMMO)
            s.count = (ok and plain(n)) or 0
        end
        local inBags = D.GetItemCount(id, false) or 0
        -- Whether the bag count includes the equipped stack differs by
        -- client. When it does, the two reads are the same number and
        -- adding them would double count, so treat the larger as the
        -- total and the difference as the spares.
        if inBags >= s.count then
            s.total, s.spare = inBags, inBags - s.count
        else
            s.total, s.spare = s.count + inBags, inBags
        end
        s.bagCount = s.spare
        if s.fires and s.ammoType and s.ammoType ~= s.fires then s.mismatch = true end
    end
    s.total = s.total or 0

    -- How many the quivers hold. Every slot of every equipped quiver or
    -- ammo pouch, by the bag family the client reports (1 quiver, 2
    -- pouch), times the stack the ammo itself reports. 1768/2000 is what
    -- a hunter reads at a glance; 1768 alone is a number to think about.
    -- No such bag, no capacity, and the strip shows the plain count.
    if s.itemID and D.GetContainerNumFreeSlots then
        local slots = 0
        for bag = 1, 4 do
            local _, family = D.GetContainerNumFreeSlots(bag)
            if type(family) == "number" and family > 0 and bit.band(family, 3) ~= 0 then
                slots = slots + (D.GetContainerNumSlots(bag) or 0)
            end
        end
        if slots > 0 then
            local it = D.GetItemInfo(s.itemID)
            local stack = it and it.stackCount
            if type(stack) ~= "number" or stack <= 0 then stack = 200 end
            s.quiverSlots = slots
            s.capacity = slots * stack
        end
    end
    return s
end

function Ammo:Init()
    if self.inited then return end
    self.inited = true
    ns.RegisterEvents({ "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" })
    ns:On("UNIT_INVENTORY_CHANGED", function(_, unit) if unit == "player" and ns.UI then ns.UI:RefreshAmmo() end end)
    ns:On("PLAYER_EQUIPMENT_CHANGED", function() if ns.UI then ns.UI:RefreshAmmo() end end)
    ns:On("BAG_UPDATE_DELAYED", function() if ns.UI then ns.UI:RefreshAmmo() end end)
end

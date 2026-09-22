-- Wick's Beasts and Things
-- Beasts.lua: which family brings which ability.
--
-- There is no API for this. The client knows what your current pet can do
-- and it knows what family a beast belongs to, but nothing joins the two,
-- and Beast Lore on this build reports damage, health, armor, resistances
-- and diet, with no mention of abilities.
--
-- So this does the join itself. Whenever a pet is out it reads the pet
-- spell book and files what it found under that pet's family. After that,
-- pointing at any beast of a family you have tamed says what it brings.
--
-- Built by watching rather than shipped as a table, on purpose. A table
-- copied out of Burning Crusade would be a guess about Forever. This is
-- right by construction on whatever the client actually does.

local ADDON, ns = ...
local Core = WickCore
local Chrome = Core.Chrome
local C = Chrome.Colors

local Beasts = {}
ns.beasts = Beasts

-- An ability this many families share is plumbing, not a reason to tame.
local COMMON_AT = 3

local function store()
    local A = ns.A
    if not (A and A.db and A.db.global) then return nil end
    A.db.global.families = A.db.global.families or {}
    return A.db.global.families
end

local function petSpells()
    local out = {}
    local SB = rawget(_G, "C_SpellBook")
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet

    if SB and SB.HasPetSpells and SB.GetSpellBookItemInfo and bank then
        local ok, n = pcall(SB.HasPetSpells)
        if not ok or type(n) ~= "number" then return out end
        for i = 1, n do
            local got, info = pcall(SB.GetSpellBookItemInfo, i, bank)
            if got and type(info) == "table" and info.name and info.name ~= "" then
                out[#out + 1] = {
                    name = info.name,
                    passive = info.isPassive and true or false,
                    icon = info.iconID,
                    spellID = info.spellID or info.actionID,
                }
            end
        end
        return out
    end

    -- Older dialect: both of these are plain globals and the book is
    -- addressed by the string "pet" rather than a bank enum.
    local has = rawget(_G, "HasPetSpells")
    local nameOf = rawget(_G, "GetSpellBookItemName") or rawget(_G, "GetSpellName")
    if not (has and nameOf) then return out end
    local ok, n = pcall(has)
    if not ok or type(n) ~= "number" then return out end
    local isPassive = rawget(_G, "IsPassiveSpell")
    local textureOf = rawget(_G, "GetSpellBookItemTexture") or rawget(_G, "GetSpellTexture")
    local infoOf = rawget(_G, "GetSpellBookItemInfo")
    for i = 1, n do
        local got, name = pcall(nameOf, i, "pet")
        if got and type(name) == "string" and name ~= "" then
            local passive = false
            if isPassive then
                local pok, p = pcall(isPassive, i, "pet")
                passive = pok and p and true or false
            end
            local icon
            if textureOf then
                local tok, t = pcall(textureOf, i, "pet")
                if tok then icon = t end
            end
            local spellID
            if infoOf then
                -- The older call answers (type, id), and the id is only a
                -- spell when the type says so.
                local iok, kind, id = pcall(infoOf, i, "pet")
                if iok and kind == "SPELL" then spellID = id end
            end
            out[#out + 1] = { name = name, passive = passive, icon = icon, spellID = spellID }
        end
    end
    return out
end

-- File whatever the pet that is out can do, under its family.
function Beasts:Record()
    local fams = store()
    if not fams then return end
    if not (UnitExists and UnitExists("pet")) then return end
    local family = UnitCreatureFamily and UnitCreatureFamily("pet")
    if not family or family == "" then return end

    local spells = petSpells()
    if #spells == 0 then return end

    local rec = fams[family] or { abilities = {} }
    rec.abilities = rec.abilities or {}
    -- The icon and the spell were read and thrown away for a while. They
    -- are what lets the bestiary show an ability rather than name it.
    rec.icons = rec.icons or {}
    rec.spells = rec.spells or {}
    local added = {}
    for _, s in ipairs(spells) do
        if rec.abilities[s.name] == nil then added[#added + 1] = s.name end
        rec.abilities[s.name] = s.passive and "passive" or "active"
        if s.icon then rec.icons[s.name] = s.icon end
        if s.spellID then rec.spells[s.name] = s.spellID end
    end
    rec.seen = (rec.seen or 0) + 1
    fams[family] = rec

    if #added > 0 and self.announced ~= family then
        self.announced = family
        table.sort(added)
        ns.A:Print(("%s noted: %s"):format(family, table.concat(added, ", ")))
    end
end

-- What most families carry is plumbing. Worked out from what has been
-- recorded rather than assumed, so it sharpens as more beasts are tamed.
function Beasts:CommonNames()
    local fams = store()
    local count, total = {}, 0
    if not fams then return count, 0 end
    for _, rec in pairs(fams) do
        total = total + 1
        for name in pairs(rec.abilities or {}) do count[name] = (count[name] or 0) + 1 end
    end
    local common = {}
    for name, n in pairs(count) do
        if n >= COMMON_AT then common[name] = true end
    end
    return common, total
end

-- What a family brings: the ones that set it apart, then the rest.
function Beasts:Known(family)
    local fams = store()
    local rec = fams and family and fams[family]
    if not rec then return nil end
    local common = self:CommonNames()
    local special, shared = {}, {}
    for name in pairs(rec.abilities or {}) do
        table.insert(common[name] and shared or special, name)
    end
    table.sort(special)
    table.sort(shared)
    return special, shared, rec.seen or 0
end

-- What the bestiary needs to draw an ability rather than spell it out.
function Beasts:Art(family, name)
    local fams = store()
    local rec = fams and family and fams[family]
    if not rec then return nil end
    return (rec.icons or {})[name], (rec.spells or {})[name]
end

function Beasts:IsPassive(family, name)
    local fams = store()
    local rec = fams and family and fams[family]
    return rec and (rec.abilities or {})[name] == "passive" or false
end

function Beasts:Families()
    local fams = store()
    local names = {}
    if fams then for name in pairs(fams) do names[#names + 1] = name end end
    table.sort(names)
    return names
end

function Beasts:Forget(family)
    local fams = store()
    if not fams then return false end
    if family then
        local had = fams[family] ~= nil
        fams[family] = nil
        return had
    end
    for k in pairs(fams) do fams[k] = nil end
    return true
end

-- ============================================================
-- Tooltip
-- ============================================================

local function describe(family)
    local special, shared = Beasts:Known(family)
    if not special then return nil end
    if #special > 0 then return table.concat(special, ", ") end
    if #shared > 0 then return table.concat(shared, ", ") end
    return nil
end

function Beasts:DecorateUnit(tt, unit)
    if not unit then return end
    local db = ns.A and ns.A.db and ns.A.db.profile
    if db and db.beastTooltip == false then return end
    if not (UnitCreatureType and UnitCreatureType(unit) == "Beast") then return end
    local family = UnitCreatureFamily and UnitCreatureFamily(unit)
    if not family or family == "" then return end
    local line = describe(family)
    if line then
        tt:AddLine(("%s: %s"):format(family, line), C.fel[1], C.fel[2], C.fel[3])
    else
        tt:AddLine(("%s: not tamed yet"):format(family), C.muted[1], C.muted[2], C.muted[3])
    end
end

function Beasts:HookTooltip()
    local TDP = rawget(_G, "TooltipDataProcessor")
    local dataType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    if TDP and TDP.AddTooltipPostCall and dataType then
        TDP.AddTooltipPostCall(dataType, function(tt)
            local TU = rawget(_G, "TooltipUtil")
            local unit
            if TU and TU.GetDisplayedUnit then
                local _, u = TU.GetDisplayedUnit(tt)
                unit = u
            end
            Core.safe(Beasts.DecorateUnit, Beasts, tt, unit)
        end)
        return
    end
    local gt = rawget(_G, "GameTooltip")
    if gt and gt.HookScript then
        gt:HookScript("OnTooltipSetUnit", function(tt)
            local _, unit = tt:GetUnit()
            Core.safe(Beasts.DecorateUnit, Beasts, tt, unit)
        end)
    end
end

-- ============================================================

function Beasts:Report(print_)
    local names = self:Families()
    if #names == 0 then
        print_("no beasts recorded yet. Tame one and its family is noted on its own.")
        return
    end
    local _, total = self:CommonNames()
    print_(("%d famil%s recorded:"):format(total, total == 1 and "y" or "ies"))
    for _, family in ipairs(names) do
        local special, shared = self:Known(family)
        local bits = {}
        if #special > 0 then bits[#bits + 1] = table.concat(special, ", ") end
        if #shared > 0 then bits[#bits + 1] = "(" .. table.concat(shared, ", ") .. ")" end
        print_(("  %s: %s"):format(family, #bits > 0 and table.concat(bits, "  ") or "nothing recorded"))
    end
    if total < COMMON_AT then
        print_(("Anything %d families share gets bracketed as ordinary. Not enough recorded to tell yet."):format(COMMON_AT))
    end
end

-- ============================================================
-- The Beasts tab in the kit window
-- ============================================================

local ROW_H = 16

function Beasts:AttachPane(pane)
    self.pane = pane

    pane.note = Chrome:Text(pane, 10, C.muted)
    pane.note:SetPoint("TOPLEFT", 0, 0)
    pane.note:SetWidth(380)
    pane.note:SetJustifyH("LEFT")
    pane.note:SetText("Nothing in the game says which family brings which ability, so this reads your pet's spell book whenever one is out. Bracketed abilities are the ones most families carry.")

    pane.count = Chrome:Text(pane, 11, C.text)
    pane.count:SetPoint("TOPLEFT", 0, -34)

    -- Clip the list so a long roster scrolls rather than running out of
    -- the window.
    local clip = CreateFrame("ScrollFrame", nil, pane)
    clip:SetPoint("TOPLEFT", 0, -54)
    clip:SetPoint("BOTTOMRIGHT", 0, 24)
    local list = CreateFrame("Frame", nil, clip)
    list:SetSize(1, 1)
    clip:SetScrollChild(list)
    clip:EnableMouseWheel(true)
    clip:SetScript("OnMouseWheel", function(f, delta)
        local range = math.max(0, (tonumber(list:GetHeight()) or 0) - (tonumber(f:GetHeight()) or 0))
        if range <= 0 then return end
        f:SetVerticalScroll(math.min(range, math.max(0, (tonumber(f:GetVerticalScroll()) or 0) - delta * 24)))
    end)
    pane.clip, pane.list, pane.rows = clip, list, {}

    local forget = Chrome:Button(pane, "Forget all", 80, 20)
    forget:SetPoint("BOTTOMLEFT", 0, 0)
    forget:SetScript("OnClick", function()
        Beasts:Forget()
        Beasts:RefreshPane()
    end)

    pane:SetScript("OnShow", function() Beasts:RefreshPane() end)
    self:RefreshPane()
end

local function paneRow(pane, i)
    local r = pane.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, pane.list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    r.family = Chrome:Text(r, 11, C.text)
    r.family:SetPoint("LEFT", 0, 0)
    r.family:SetWidth(90)
    r.family:SetJustifyH("LEFT")
    r.abilities = Chrome:Text(r, 11, C.fel)
    r.abilities:SetPoint("LEFT", 94, 0)
    r.abilities:SetWidth(250)
    r.abilities:SetJustifyH("LEFT")
    pane.rows[i] = r
    return r
end

function Beasts:RefreshPane()
    local pane = self.pane
    if not pane then return end
    local names = self:Families()
    local _, total = self:CommonNames()

    if #names == 0 then
        pane.count:SetText("Nothing recorded yet. Tame a beast and its family is filed on its own.")
    elseif total < COMMON_AT then
        pane.count:SetText(("%d recorded. At %d, the abilities they share stop standing out."):format(total, COMMON_AT))
    else
        pane.count:SetText(("%d families recorded."):format(total))
    end

    for _, r in ipairs(pane.rows) do r:Hide() end
    for i, family in ipairs(names) do
        local r = paneRow(pane, i)
        local special, shared = self:Known(family)
        r.family:SetText(family)
        local bits = {}
        if #special > 0 then bits[#bits + 1] = table.concat(special, ", ") end
        if #shared > 0 then bits[#bits + 1] = "|cff8a8270(" .. table.concat(shared, ", ") .. ")|r" end
        r.abilities:SetText(#bits > 0 and table.concat(bits, "  ") or "nothing recorded")
        r:Show()
    end
    pane.list:SetHeight(math.max(1, #names * ROW_H))
    local w = tonumber(pane.clip:GetWidth())
    if w and w > 0 then pane.list:SetWidth(w) end
end

function Beasts:Init()
    self:HookTooltip()
    ns.RegisterEvents({ "UNIT_PET", "PET_BAR_UPDATE", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" })
    local function later()
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() Core.safe(Beasts.Record, Beasts) end)
        else
            Core.safe(Beasts.Record, Beasts)
        end
    end
    ns:On("UNIT_PET", function(_, unit)
        if unit == "player" then Beasts.announced = nil; later() end
    end)
    ns:On("PET_BAR_UPDATE", later)
    ns:On("SPELLS_CHANGED", later)
    ns:On("PLAYER_ENTERING_WORLD", later)
    -- A reload with a pet already out sends no UNIT_PET, so read once on
    -- the way up rather than waiting for the beast to be dismissed first.
    later()
end

function Beasts:OptionRow(page, y)
    local O = Core.Options
    local db = ns.A.db.profile
    y = O:Heading(page, "Beast atlas", y)
    y = O:Check(page, "Name a beast's abilities in its tooltip",
        function() return db.beastTooltip ~= false end,
        function(v) db.beastTooltip = v end, y)
    y = O:Note(page, "Nothing in the game lists which family brings which ability, so this builds the list by reading your pet's spell book whenever one is out. Point at any beast of a family you have tamed and its tooltip names what that family brings. Use /wbt beasts for everything recorded.", y)
    return y
end

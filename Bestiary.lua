-- Wick's Beasts and Things
-- Bestiary.lua: the animals themselves.
--
-- Beasts.lua files what a *family* can do. This files the individuals: the
-- ones you tamed, what they eat, how far they got, when you last had them
-- out. Nothing in the game keeps that. The stable master shows the slots
-- and says nothing about a pet sitting in one, and a pet you dismissed is
-- gone from every read the client offers.
--
-- So this writes a line whenever a pet is out and keeps it. A hunter has a
-- handful of animals at most, which is why the whole roster is cheap enough
-- to carry in the settings store rather than treated as a cache.
--
-- It also carries the food pin. That used to be one item for the hunter,
-- which is wrong the moment you own two pets: pin fish for the cat, call
-- the boar, and the pin quietly does not apply because a boar will not eat
-- it. The pin belongs to the animal.

local ADDON, ns = ...
local Core = WickCore
local Chrome = Core.Chrome
local C = Chrome.Colors

local Bestiary = {}
ns.Bestiary = Bestiary

local function store()
    local A = ns.A
    if not (A and A.db and A.db.char) then return nil end
    A.db.char.pets = A.db.char.pets or {}
    return A.db.char.pets
end

-- A hunter can own two animals of the same family, so the family alone will
-- not do as a key, and two of the same name is not possible.
function Bestiary:Key(name, family)
    if not name or name == "" then return nil end
    return (name:lower() .. "|" .. (family or "?"):lower())
end

-- ============================================================
-- Writing
-- ============================================================

-- Merge what the client will say about the pet that is out. Every field is
-- optional: a secret level or a happiness the client withholds leaves the
-- last known value alone rather than overwriting it with nothing.
function Bestiary:Record()
    local pets = store()
    if not pets then self.why = "no character store" return nil end
    local s = ns.Pet and ns.Pet:State()
    if not s then self.why = "Pet:State returned nothing" return nil end
    if not s.exists then self.why = "no pet out" return nil end
    if not s.name or s.name == "" then self.why = "the client would not name the pet" return nil end

    local key = self:Key(s.name, s.family)
    if not key then self.why = "no key for " .. tostring(s.name) return nil end
    self.why = nil
    local rec = pets[key]
    local isNew = rec == nil
    rec = rec or { name = s.name, family = s.family, firstSeen = time and time() or 0, seen = 0 }

    rec.name   = s.name
    rec.family = s.family or rec.family
    -- Levels only go up, and a level the client will not hand over is not a
    -- reason to forget the one it handed over last time.
    if s.level and (not rec.level or s.level > rec.level) then rec.level = s.level end
    if s.loyalty then rec.loyalty = s.loyalty end
    if s.happiness then rec.happiness = s.happiness end
    if s.trainingTotal then rec.trainingTotal, rec.trainingUsed = s.trainingTotal, s.trainingUsed end
    if s.diet and #s.diet > 0 then rec.diet = s.diet end
    rec.lastSeen = time and time() or 0
    rec.seen = (rec.seen or 0) + 1
    -- Whole seconds are not fine enough to order a pet swap by: call the
    -- cat and then the boar inside the same second and the two records tie.
    -- A counter taken off the top of the roster orders them properly and
    -- survives a restart without having to be stored on its own.
    local top = 0
    for _, other in pairs(pets) do
        if (other.order or 0) > top then top = other.order end
    end
    rec.order = top + 1
    pets[key] = rec
    self.currentKey = key

    if isNew and ns.A then
        ns.A:Print(("%s added to the bestiary%s."):format(s.name,
            s.family and s.family ~= "" and (", a " .. s.family:lower()) or ""))
    end
    return rec
end

-- ============================================================
-- Reading
-- ============================================================

function Bestiary:Current()
    local pets = store()
    if not pets then return nil end
    if not (UnitExists and UnitExists("pet")) then return nil end
    local name = UnitName and UnitName("pet")
    local key = self:Key(name, UnitCreatureFamily and UnitCreatureFamily("pet"))
    if key and pets[key] then return pets[key], key end
    return nil
end

-- Most recently out first: the roster reads as a history rather than an
-- alphabet, and the animal you are working with sits at the top.
function Bestiary:All()
    local pets = store()
    local list = {}
    if not pets then return list end
    for key, rec in pairs(pets) do
        rec.key = key
        list[#list + 1] = rec
    end
    table.sort(list, function(a, b)
        if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) > (b.order or 0) end
        if (a.lastSeen or 0) ~= (b.lastSeen or 0) then return (a.lastSeen or 0) > (b.lastSeen or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

function Bestiary:Count()
    local pets = store()
    local n = 0
    if pets then for _ in pairs(pets) do n = n + 1 end end
    return n
end

-- By name, so a slash command can take what the player would type.
function Bestiary:Find(name)
    local pets = store()
    if not (pets and name and name ~= "") then return nil end
    local want = name:lower()
    for key, rec in pairs(pets) do
        if (rec.name or ""):lower() == want then return rec, key end
    end
    for key, rec in pairs(pets) do
        if (rec.name or ""):lower():find(want, 1, true) then return rec, key end
    end
    return nil
end

function Bestiary:Forget(name)
    local pets = store()
    if not pets then return false end
    if not name then
        for k in pairs(pets) do pets[k] = nil end
        return true
    end
    local rec, key = self:Find(name)
    if not key then return false end
    pets[key] = nil
    return true, rec and rec.name
end

-- ============================================================
-- The food pin
-- ============================================================

-- Pin to the animal that is out. With none out there is nothing to pin to,
-- so the caller falls back to the hunter-wide pin the addon has always had.
function Bestiary:Pin(itemID)
    local rec = self:Current()
    if not rec then return nil end
    rec.food = itemID or nil
    return rec.name
end

function Bestiary:PinnedFood()
    local rec = self:Current()
    return rec and rec.food or nil
end

-- ============================================================
-- Report
-- ============================================================

-- An untamed name is the family name, so printing both gives "Crab Crab".
function Bestiary:Title(rec)
    local name, family = rec.name or "?", rec.family
    if not family or family == "" then return name end
    if name:lower() == family:lower() then return name end
    return name .. "  " .. family
end

function Bestiary:Report(print_)
    local list = self:All()
    if #list == 0 then
        print_("no animals recorded. Call a pet and it is written down on its own.")
        return
    end
    local _, curKey = self:Current()
    print_(("%d animal%s recorded:"):format(#list, #list == 1 and "" or "s"))
    for _, rec in ipairs(list) do
        -- Out at the end rather than a marker at the front: a leading glyph
        -- is lost in a chat frame, a trailing word is not.
        print_(("  %s%s%s%s"):format(
            self:Title(rec),
            rec.level and ("  " .. rec.level) or "",
            rec.diet and #rec.diet > 0 and ("  " .. table.concat(rec.diet, ", ")) or "  diet unknown",
            rec.key == curKey and "  (out)" or ""))
    end
end

-- ============================================================
-- The Bestiary tab
-- ============================================================

local ROW_H = 16

local function ago(t)
    if not t or t == 0 or not time then return "" end
    local d = time() - t
    if d < 90 then return "now" end
    if d < 3600 then return ("%dm"):format(math.floor(d / 60)) end
    if d < 86400 then return ("%dh"):format(math.floor(d / 3600)) end
    return ("%dd"):format(math.floor(d / 86400))
end

function Bestiary:AttachPane(pane)
    self.pane = pane

    pane.note = Chrome:Text(pane, 10, C.muted)
    pane.note:SetPoint("TOPLEFT", 0, 0)
    pane.note:SetWidth(380)
    pane.note:SetJustifyH("LEFT")
    pane.note:SetText("Every animal you have had out, with what it eats and how long ago you called it. A pet in the stable reads nothing to the client, so this is written while it is with you. The one out now is marked.")

    pane.count = Chrome:Text(pane, 11, C.text)
    pane.count:SetPoint("TOPLEFT", 0, -34)

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
        Bestiary:Forget()
        Bestiary:RefreshPane()
    end)

    pane:SetScript("OnShow", function() Bestiary:RefreshPane() end)
    self:RefreshPane()
end

local function paneRow(pane, i)
    local r = pane.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, pane.list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    r.name = Chrome:Text(r, 11, C.text)
    r.name:SetPoint("LEFT", 0, 0)
    r.name:SetWidth(96)
    r.name:SetJustifyH("LEFT")
    r.family = Chrome:Text(r, 11, C.fel)
    r.family:SetPoint("LEFT", 100, 0)
    r.family:SetWidth(84)
    r.family:SetJustifyH("LEFT")
    r.age = Chrome:Text(r, 11, C.muted)
    r.age:SetPoint("RIGHT", 0, 0)
    r.age:SetWidth(30)
    r.age:SetJustifyH("RIGHT")
    r.diet = Chrome:Text(r, 11, C.muted)
    r.diet:SetPoint("LEFT", 188, 0)
    r.diet:SetJustifyH("LEFT")
    -- Bounded on the right, or a long diet runs out of the window. The same
    -- fix the trade board rows needed.
    r.diet:SetPoint("RIGHT", r.age, "LEFT", -6, 0)
    r.diet:SetWordWrap(false)
    if r.diet.SetMaxLines then r.diet:SetMaxLines(1) end
    pane.rows[i] = r
    return r
end

function Bestiary:RefreshPane()
    local pane = self.pane
    if not pane then return end
    local list = self:All()
    local _, curKey = self:Current()

    if #list == 0 then
        pane.count:SetText("Nothing recorded yet. Call a pet and it writes itself down.")
    else
        pane.count:SetText(("%d animal%s recorded."):format(#list, #list == 1 and "" or "s"))
    end

    for _, r in ipairs(pane.rows) do r:Hide() end
    for i, rec in ipairs(list) do
        local r = paneRow(pane, i)
        local out = rec.key == curKey
        r.name:SetText((out and "|cff4FC778> |r" or "") .. (rec.name or "?"))
        local fam = rec.family or "?"
        if (rec.name or ""):lower() == fam:lower() then fam = "" end
        r.family:SetText(fam .. (rec.level and ((fam ~= "" and "  " or "") .. rec.level) or ""))
        local bits = {}
        if rec.diet and #rec.diet > 0 then bits[#bits + 1] = table.concat(rec.diet, ", ") end
        if rec.loyalty then bits[#bits + 1] = rec.loyalty end
        if rec.food then bits[#bits + 1] = "pinned food" end
        r.diet:SetText(#bits > 0 and table.concat(bits, "  ") or "diet unknown")
        r.age:SetText(out and "out" or ago(rec.lastSeen))
        r:Show()
    end
    pane.list:SetHeight(math.max(1, #list * ROW_H))
    local w = tonumber(pane.clip:GetWidth())
    if w and w > 0 then pane.list:SetWidth(w) end
end

-- ============================================================

function Bestiary:Init()
    if self.inited then return end
    self.inited = true
    local function later()
        local function go()
            Core.safe(Bestiary.Record, Bestiary)
            if Bestiary.pane and Bestiary.pane:IsShown() then Bestiary:RefreshPane() end
        end
        -- A pet that has just been called answers nothing for a moment.
        if C_Timer and C_Timer.After then C_Timer.After(1, go) else go() end
    end
    ns.RegisterEvents({ "UNIT_PET", "PET_UI_UPDATE", "UNIT_LEVEL", "PLAYER_ENTERING_WORLD" })
    ns:On("UNIT_PET", function(_, unit) if unit == "player" then later() end end)
    ns:On("PET_UI_UPDATE", later)
    ns:On("UNIT_LEVEL", function(_, unit) if unit == "pet" then later() end end)
    ns:On("PLAYER_ENTERING_WORLD", later)
    later()
end

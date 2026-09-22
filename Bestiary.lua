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
        Bestiary:RefreshWindow()
    end)

    local open = Chrome:Button(pane, "Open the bestiary", 120, 20)
    open:SetPoint("BOTTOMLEFT", forget, "BOTTOMRIGHT", 6, 0)
    open:SetScript("OnClick", function() Bestiary:Open() end)

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
    -- The tab is a roster; the page is the window. Clicking a line here is
    -- the way between them.
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", function(s) if s.key then Bestiary:Open(s.key) end end)
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
        r.key = rec.key
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
-- The window
-- ============================================================
--
-- The kit tab is a roster and nothing more. This is the page: pick an
-- animal on the left and the right says everything known about it,
-- including what its family brings, which is the one thing the two
-- records can only answer together.

local W = { LIST = 170, ROW = 17 }

local function detailLine(parent, y, size, color)
    local fs = Chrome:Text(parent, size or 11, color)
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetPoint("TOPRIGHT", 0, y)
    fs:SetJustifyH("LEFT")
    return fs
end

function Bestiary:Window()
    if self.win then return self.win end
    local db = ns.A.db.profile
    db.bestiaryWindow = db.bestiaryWindow or {}

    local f = Chrome:NewPanel("WicksBestiaryWindow", {
        title = "Bestiary", width = 540, height = 330,
        resizable = true, minWidth = 420, minHeight = 240,
        db = db.bestiaryWindow,
    })
    self.win = f
    local c = f.content

    -- Left: the roster.
    local clip = CreateFrame("ScrollFrame", nil, c)
    clip:SetPoint("TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMLEFT", 0, 22)
    clip:SetWidth(W.LIST)
    local list = CreateFrame("Frame", nil, clip)
    list:SetSize(W.LIST, 1)
    clip:SetScrollChild(list)
    clip:EnableMouseWheel(true)
    clip:SetScript("OnMouseWheel", function(s, delta)
        local range = math.max(0, (tonumber(list:GetHeight()) or 0) - (tonumber(s:GetHeight()) or 0))
        if range <= 0 then return end
        s:SetVerticalScroll(math.min(range, math.max(0, (tonumber(s:GetVerticalScroll()) or 0) - delta * 24)))
    end)
    f.clip, f.list, f.rows = clip, list, {}

    local rule = Chrome:Texture(c, "ARTWORK", C.border)
    rule:SetWidth(1)
    rule:SetPoint("TOPLEFT", W.LIST + 8, 0)
    rule:SetPoint("BOTTOMLEFT", W.LIST + 8, 0)

    -- Right: the page.
    local d = CreateFrame("Frame", nil, c)
    d:SetPoint("TOPLEFT", W.LIST + 17, 0)
    d:SetPoint("BOTTOMRIGHT", 0, 22)
    f.detail = d

    d.name = detailLine(d, 0, 14, C.fel)
    d.sub = detailLine(d, -20, 11, C.muted)
    d.diet = detailLine(d, -42, 11)
    d.loyal = detailLine(d, -60, 11)
    d.food = detailLine(d, -78, 11)
    d.abilHead = detailLine(d, -102, 11, C.muted)
    d.abil = detailLine(d, -118, 11, C.fel)
    d.abil:SetPoint("BOTTOMRIGHT", 0, 0)
    d.abil:SetJustifyV("TOP")
    d.empty = detailLine(d, -60, 11, C.muted)
    d.empty:SetText("Call a pet and it writes itself down. An animal in the stable reads nothing to the client, so nothing can be listed until it is out with you.")
    d.empty:SetWordWrap(true)

    -- Bottom row.
    local forget = Chrome:Button(c, "Forget", 64, 19)
    forget:SetPoint("BOTTOMRIGHT", 0, 0)
    forget:SetScript("OnClick", function()
        local rec = Bestiary:Selected()
        if not rec then return end
        Bestiary:Forget(rec.name)
        Bestiary.selectedKey = nil
        Bestiary:RefreshWindow()
        Bestiary:RefreshPane()
    end)
    f.forget = forget

    local pin = Chrome:Button(c, "Pin food", 74, 19)
    pin:SetPoint("BOTTOMRIGHT", forget, "BOTTOMLEFT", -6, 0)
    pin:SetScript("OnClick", function()
        -- Only the animal that is out can be pinned to: the pin is read off
        -- what the client says the pet will eat, and it says nothing about
        -- an animal in the stable.
        local rec, key = Bestiary:Current()
        if not rec or key ~= Bestiary.selectedKey then return end
        if rec.food then
            Bestiary:Pin(nil)
        else
            local food = ns.Pet:BestFood()
            if food then Bestiary:Pin(food.itemID) end
        end
        ns.Pet:UpdateFeedMacro()
        Bestiary:RefreshWindow()
    end)
    f.pin = pin

    f.count = Chrome:Text(c, 10, C.muted)
    f.count:SetPoint("BOTTOMLEFT", 0, 4)

    f:SetScript("OnShow", function() Bestiary:RefreshWindow() end)
    if f.OnResized == nil then f.OnResized = function() Bestiary:RefreshWindow() end end
    return f
end

function Bestiary:Selected()
    local pets = store()
    if not pets then return nil end
    return self.selectedKey and pets[self.selectedKey] or nil
end

function Bestiary:Toggle()
    local f = self:Window()
    if f:IsShown() then f:Hide() else f:Show() end
end

function Bestiary:Open(key)
    local f = self:Window()
    if key then self.selectedKey = key end
    f:Show()
    self:RefreshWindow()
end

local function winRow(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, f.list)
    r:SetHeight(W.ROW)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * W.ROW)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * W.ROW)
    r.hl = Chrome:Texture(r, "BACKGROUND", C.shadow)
    r.hl:SetAllPoints()
    r.hl:Hide()
    r.label = Chrome:Text(r, 11)
    r.label:SetPoint("LEFT", 4, 0)
    r.label:SetJustifyH("LEFT")
    r.tag = Chrome:Text(r, 10, C.fel)
    r.tag:SetPoint("RIGHT", -4, 0)
    r.tag:SetJustifyH("RIGHT")
    r.label:SetPoint("RIGHT", r.tag, "LEFT", -4, 0)
    r.label:SetWordWrap(false)
    if r.label.SetMaxLines then r.label:SetMaxLines(1) end
    r:SetScript("OnClick", function(s)
        Bestiary.selectedKey = s.key
        Bestiary:RefreshWindow()
    end)
    f.rows[i] = r
    return r
end

function Bestiary:RefreshWindow()
    local f = self.win
    if not (f and f:IsShown()) then return end
    local list = self:All()
    local _, curKey = self:Current()

    -- A selection that was forgotten, or none yet: fall to the top of the
    -- roster so the page is never blank while there is something to show.
    local pets = store()
    if not (self.selectedKey and pets and pets[self.selectedKey]) then
        self.selectedKey = list[1] and list[1].key or nil
    end

    for _, r in ipairs(f.rows) do r:Hide() end
    for i, rec in ipairs(list) do
        local r = winRow(f, i)
        r.key = rec.key
        r.label:SetText(rec.name or "?")
        r.tag:SetText(rec.key == curKey and "out" or (rec.level and tostring(rec.level) or ""))
        r.hl:SetShown(rec.key == self.selectedKey)
        r:Show()
    end
    f.list:SetHeight(math.max(1, #list * W.ROW))
    f.count:SetText(("%d animal%s"):format(#list, #list == 1 and "" or "s"))

    local d = f.detail
    local rec = self:Selected()
    local has = rec ~= nil
    for _, k in ipairs({ "name", "sub", "diet", "loyal", "food", "abilHead", "abil" }) do
        d[k]:SetShown(has)
    end
    d.empty:SetShown(not has)
    f.forget:SetShown(has)
    f.pin:SetShown(has and rec.key == curKey)
    if not has then return end

    d.name:SetText(rec.name or "?")
    local bits = {}
    if rec.family and (rec.name or ""):lower() ~= rec.family:lower() then bits[#bits + 1] = rec.family end
    if rec.level then bits[#bits + 1] = "level " .. rec.level end
    if rec.key == curKey then bits[#bits + 1] = "out now"
    elseif rec.lastSeen then bits[#bits + 1] = "last out " .. ago(rec.lastSeen) .. " ago" end
    if rec.seen then bits[#bits + 1] = ("called %d time%s"):format(rec.seen, rec.seen == 1 and "" or "s") end
    d.sub:SetText(table.concat(bits, "   "))

    d.diet:SetText("Eats: " .. (rec.diet and #rec.diet > 0 and table.concat(rec.diet, ", ") or "not known"))

    local lbits = {}
    if rec.loyalty then lbits[#lbits + 1] = rec.loyalty end
    if rec.trainingTotal then
        lbits[#lbits + 1] = ("%s of %s training points spent"):format(
            tostring(rec.trainingUsed or 0), tostring(rec.trainingTotal))
    end
    d.loyal:SetText(#lbits > 0 and table.concat(lbits, "   ") or "")

    if rec.food then
        local it = Core.Dialect.GetItemInfo(rec.food)
        d.food:SetText("Feeds on: " .. ((it and it.name) or ("item " .. rec.food)))
    elseif rec.key == curKey then
        d.food:SetText("Feeds on: the best food in your bags")
    else
        d.food:SetText("")
    end

    -- The join the two records exist for: this animal, and what anything of
    -- its family has been seen to bring.
    local special, shared = nil, nil
    if ns.beasts and rec.family then special, shared = ns.beasts:Known(rec.family) end
    if special then
        d.abilHead:SetText((rec.family or "Its family") .. " brings")
        local out = {}
        if #special > 0 then out[#out + 1] = table.concat(special, ", ") end
        if #shared > 0 then out[#out + 1] = "|cff8a8270" .. table.concat(shared, ", ") .. "|r" end
        d.abil:SetText(table.concat(out, "   "))
    else
        d.abilHead:SetText("")
        d.abil:SetText("")
    end
end

-- ============================================================

function Bestiary:Init()
    if self.inited then return end
    self.inited = true
    local function later()
        local function go()
            Core.safe(Bestiary.Record, Bestiary)
            if Bestiary.pane and Bestiary.pane:IsShown() then Bestiary:RefreshPane() end
            Bestiary:RefreshWindow()
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

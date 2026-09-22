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

local W = { LIST = 178, ROW = 20, PORTRAIT = 46 }

-- The game names its own pet icons after the family, so the path can be
-- derived rather than listed. Only the families whose file name differs
-- from the name the client prints need an entry here.
local ICON_NAME = {
    ["wind serpent"] = "WindSerpent",
    ["carrion bird"] = "CarrionBird",
    ["nether ray"]   = "Netherray",
    ["dragonhawk"]   = "DragonHawk",
}
local ICON_DIR = "Interface\\Icons\\"
local FALLBACK_ICON = ICON_DIR .. "Ability_Hunter_BeastCall"

function Bestiary:FamilyIcon(family)
    if not family or family == "" then return FALLBACK_ICON end
    local key = family:lower()
    local file = ICON_NAME[key] or family:gsub("%s+", "")
    return ICON_DIR .. "Ability_Hunter_Pet_" .. file
end

-- The animal that is out has a real portrait; one in the stable has only
-- its family icon, because the client will not draw a pet it cannot see.
local function paintPortrait(tex, rec, isOut)
    if isOut then
        local fn = rawget(_G, "SetPortraitTexture")
        if fn then
            local ok = pcall(fn, tex, "pet")
            if ok then
                tex:SetTexCoord(0, 1, 0, 1)
                return
            end
        end
    end
    tex:SetTexture(Bestiary:FamilyIcon(rec and rec.family))
    -- Icons carry a border in the file; trimming the edge drops it.
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

local function label(parent, x, y, text)
    local fs = Chrome:Text(parent, 9, C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function value(parent, x, y, w, color)
    local fs = Chrome:Text(parent, 12, color)
    fs:SetPoint("TOPLEFT", x, y - 11)
    fs:SetWidth(w)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function Bestiary:Window()
    if self.win then return self.win end
    local db = ns.A.db.profile
    db.bestiaryWindow = db.bestiaryWindow or {}

    local f = Chrome:NewPanel("WicksBestiaryWindow", {
        title = "Bestiary", width = 560, height = 340,
        resizable = true, minWidth = 460, minHeight = 260,
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

    -- Portrait, framed the way the rest of the suite frames things.
    local pf = CreateFrame("Frame", nil, d)
    pf:SetSize(W.PORTRAIT, W.PORTRAIT)
    pf:SetPoint("TOPLEFT", 0, 0)
    Chrome:AddBorder(pf)
    d.portrait = pf:CreateTexture(nil, "ARTWORK")
    d.portrait:SetPoint("TOPLEFT", 1, -1)
    d.portrait:SetPoint("BOTTOMRIGHT", -1, 1)
    d.portraitFrame = pf

    local textX = W.PORTRAIT + 10
    d.name = Chrome:Text(d, 15, C.fel)
    d.name:SetPoint("TOPLEFT", textX, -2)
    d.sub = Chrome:Text(d, 11, C.muted)
    d.sub:SetPoint("TOPLEFT", textX, -21)
    d.sub:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    d.sub:SetJustifyH("LEFT")
    d.sub:SetWordWrap(false)

    -- A dot rather than a word: the roster already says "out", and on the
    -- page it wants to read as a state, not a label.
    d.dot = Chrome:Texture(d, "OVERLAY", C.fel)
    d.dot:SetSize(6, 6)
    d.dot:SetPoint("TOPLEFT", textX, -38)
    d.outText = Chrome:Text(d, 10, C.fel)
    d.outText:SetPoint("TOPLEFT", textX + 11, -34)
    d.outText:SetText("out with you now")

    local r1 = Chrome:Texture(d, "ARTWORK", C.border)
    r1:SetHeight(1)
    r1:SetPoint("TOPLEFT", 0, -(W.PORTRAIT + 10))
    r1:SetPoint("TOPRIGHT", 0, -(W.PORTRAIT + 10))
    d.rule1 = r1

    -- Three cells, so the numbers line up instead of running together in
    -- one sentence.
    local cy = -(W.PORTRAIT + 20)
    d.lLevel = label(d, 0, cy, "LEVEL")
    d.vLevel = value(d, 0, cy, 60)
    d.lLoyal = label(d, 70, cy, "LOYALTY")
    d.vLoyal = value(d, 70, cy, 130)
    d.lTrain = label(d, 208, cy, "TRAINING")
    d.vTrain = value(d, 208, cy, 90)

    local dy = cy - 38
    d.lDiet = label(d, 0, dy, "EATS")
    d.diet = Chrome:Text(d, 11)
    d.diet:SetPoint("TOPLEFT", 0, dy - 12)
    d.diet:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    d.diet:SetJustifyH("LEFT")

    local fy = dy - 32
    d.lFood = label(d, 0, fy, "FEEDS ON")
    d.foodIcon = d:CreateTexture(nil, "ARTWORK")
    d.foodIcon:SetSize(14, 14)
    d.foodIcon:SetPoint("TOPLEFT", 0, fy - 13)
    d.foodIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    d.food = Chrome:Text(d, 11)
    d.food:SetPoint("TOPLEFT", 18, fy - 12)
    d.food:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    d.food:SetJustifyH("LEFT")
    d.food:SetWordWrap(false)

    local r2 = Chrome:Texture(d, "ARTWORK", C.border)
    r2:SetHeight(1)
    r2:SetPoint("TOPLEFT", 0, fy - 32)
    r2:SetPoint("TOPRIGHT", 0, fy - 32)
    d.rule2 = r2

    d.abilHead = label(d, 0, fy - 42, "")
    -- Icons where there are icons, words where there are not. An atlas
    -- recorded before the icon was captured still has the names, and a
    -- name is worth more than a blank row.
    d.abilBox = CreateFrame("Frame", nil, d)
    d.abilBox:SetPoint("TOPLEFT", 0, fy - 55)
    d.abilBox:SetPoint("BOTTOMRIGHT", 0, 0)
    d.chips = {}
    d.abil = Chrome:Text(d, 11, C.fel)
    d.abilTop = fy - 55
    d.abil:SetPoint("TOPLEFT", 0, d.abilTop)
    d.abil:SetPoint("BOTTOMRIGHT", 0, 0)
    d.abil:SetJustifyH("LEFT")
    d.abil:SetJustifyV("TOP")

    d.empty = Chrome:Text(d, 11, C.muted)
    d.empty:SetPoint("TOPLEFT", 0, -4)
    d.empty:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    d.empty:SetJustifyH("LEFT")
    d.empty:SetText("Call a pet and it writes itself down. An animal in the stable reads nothing to the client, so nothing can be listed until it is out with you.")

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

local CHIP, CHIP_GAP = 24, 3

local function chip(d, i)
    local b = d.chips[i]
    if b then return b end
    b = CreateFrame("Button", nil, d.abilBox)
    b:SetSize(CHIP, CHIP)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    Chrome:AddBorder(b)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        -- The real spell tooltip when the book gave us an id to ask with,
        -- and the name when it did not. Never nothing.
        local shown = false
        if s.spellID and GameTooltip.SetSpellByID then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, s.spellID)
        end
        if not shown then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(s.abilityName or "?", C.fel[1], C.fel[2], C.fel[3])
        end
        if s.passive then GameTooltip:AddLine("Passive", 0.6, 0.6, 0.6) end
        GameTooltip:AddLine(s.shared and "Most families bring this" or "Sets this family apart",
            0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.chips[i] = b
    return b
end

-- Lay the chips out left to right, wrapping at the width there is.
local function layoutChips(d, entries)
    for _, b in ipairs(d.chips) do b:Hide() end
    local width = tonumber(d.abilBox:GetWidth()) or 0
    if width <= 0 then width = 300 end
    local perRow = math.max(1, math.floor((width + CHIP_GAP) / (CHIP + CHIP_GAP)))
    for i, e in ipairs(entries) do
        local b = chip(d, i)
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        b:SetPoint("TOPLEFT", col * (CHIP + CHIP_GAP), -row * (CHIP + CHIP_GAP))
        b.icon:SetTexture(e.icon)
        -- Shared abilities are plumbing, so they are greyed rather than
        -- hidden: still there to point at, not competing for the eye.
        b.icon:SetDesaturated(e.shared and true or false)
        b.icon:SetAlpha(e.shared and 0.55 or 1)
        b.abilityName, b.spellID, b.passive, b.shared = e.name, e.spellID, e.passive, e.shared
        b:Show()
    end
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
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 3, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.label = Chrome:Text(r, 11)
    r.label:SetPoint("LEFT", 22, 0)
    r.label:SetJustifyH("LEFT")
    r.tag = Chrome:Text(r, 10, C.muted)
    r.tag:SetPoint("RIGHT", -4, 0)
    r.tag:SetJustifyH("RIGHT")
    r.label:SetPoint("RIGHT", r.tag, "LEFT", -4, 0)
    r.label:SetWordWrap(false)
    if r.label.SetMaxLines then r.label:SetMaxLines(1) end
    -- Hovering shows the row is live without pretending it is selected.
    r:SetScript("OnEnter", function(s) if not s.chosen then s.hl:SetAlpha(0.5); s.hl:Show() end end)
    r:SetScript("OnLeave", function(s) s.hl:SetAlpha(1); s.hl:SetShown(s.chosen == true) end)
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
        r.chosen = rec.key == self.selectedKey
        r.icon:SetTexture(self:FamilyIcon(rec.family))
        r.label:SetText(rec.name or "?")
        r.tag:SetText(rec.key == curKey and "|cff4FC778out|r" or (rec.level and tostring(rec.level) or ""))
        r.hl:SetAlpha(1)
        r.hl:SetShown(r.chosen)
        r:Show()
    end
    f.list:SetHeight(math.max(1, #list * W.ROW))
    f.count:SetText(("%d animal%s"):format(#list, #list == 1 and "" or "s"))

    local d = f.detail
    local rec = self:Selected()
    local has = rec ~= nil
    local out = has and rec.key == curKey
    for _, k in ipairs({ "name", "sub", "diet", "food", "abilHead", "abil", "rule1", "rule2",
                         "lLevel", "vLevel", "lLoyal", "vLoyal", "lTrain", "vTrain",
                         "lDiet", "lFood", "foodIcon" }) do
        d[k]:SetShown(has)
    end
    d.portraitFrame:SetShown(has)
    d.dot:SetShown(out)
    d.outText:SetShown(out)
    d.empty:SetShown(not has)
    f.forget:SetShown(has)
    f.pin:SetShown(out)
    if not has then return end

    paintPortrait(d.portrait, rec, out)
    d.name:SetText(rec.name or "?")

    local bits = {}
    if rec.family and (rec.name or ""):lower() ~= rec.family:lower() then bits[#bits + 1] = rec.family end
    if not out and rec.lastSeen then bits[#bits + 1] = "last out " .. ago(rec.lastSeen) .. " ago" end
    if rec.seen then bits[#bits + 1] = ("called %d time%s"):format(rec.seen, rec.seen == 1 and "" or "s") end
    d.sub:SetText(table.concat(bits, "   "))

    d.vLevel:SetText(rec.level and tostring(rec.level) or "-")
    d.vLoyal:SetText(rec.loyalty or "-")
    d.vTrain:SetText(rec.trainingTotal
        and ("%s / %s"):format(tostring(rec.trainingUsed or 0), tostring(rec.trainingTotal))
        or "-")

    d.diet:SetText(rec.diet and #rec.diet > 0 and table.concat(rec.diet, ", ") or "not known")

    if rec.food then
        local it = Core.Dialect.GetItemInfo(rec.food)
        d.foodIcon:SetTexture(it and it.icon or FALLBACK_ICON)
        d.foodIcon:Show()
        d.food:SetText((it and it.name) or ("item " .. rec.food))
    else
        d.foodIcon:Hide()
        d.food:SetText(out and "the best food in your bags" or "nothing pinned")
    end

    -- The join the two records exist for: this animal, and what anything of
    -- its family has been seen to bring.
    local special, shared = nil, nil
    if ns.beasts and rec.family then special, shared = ns.beasts:Known(rec.family) end
    if special then
        d.abilHead:SetText((rec.family or "ITS FAMILY"):upper() .. " BRINGS")
        -- What sets the family apart leads; the plumbing follows, greyed.
        local entries, missing = {}, {}
        local function add(name, isShared)
            local icon, spellID = ns.beasts:Art(rec.family, name)
            if icon then
                entries[#entries + 1] = {
                    name = name, icon = icon, spellID = spellID, shared = isShared,
                    passive = ns.beasts:IsPassive(rec.family, name),
                }
            else
                missing[#missing + 1] = isShared and ("|cff8a8270" .. name .. "|r") or name
            end
        end
        for _, n in ipairs(special) do add(n, false) end
        for _, n in ipairs(shared) do add(n, true) end
        layoutChips(d, entries)
        d.abilBox:SetShown(#entries > 0)
        d.abil:SetShown(#missing > 0)
        d.abil:SetText(table.concat(missing, ", "))
        -- The text falls under the chips when both are showing, so it only
        -- takes the whole box when there are no chips at all.
        d.abil:SetPoint("TOPLEFT", 0, d.abilTop - (#entries > 0 and 30 or 0))
    else
        d.abilHead:SetText("NOT TAMED LONG ENOUGH TO SAY")
        layoutChips(d, {})
        d.abilBox:Hide()
        d.abil:Show()
        d.abil:SetPoint("TOPLEFT", 0, d.abilTop)
        d.abil:SetText("|cff8a8270Its abilities are read from the pet spell book while it is out.|r")
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

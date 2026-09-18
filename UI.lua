-- Wick's Beasts and Things
-- UI.lua: the compact strip and the details panel.
--
-- The strip is the piece meant to stay on screen: one 26px row with the
-- pet's happiness and name, the feed button as a food icon with its stack
-- count, and the ammo count. Everything else (loyalty, training points,
-- diet, weapon match) lives in tooltips on the strip and in the details
-- panel a right-click opens. All of it is read out of combat; values that
-- turn secret in combat simply stop updating and the strip says so.

local ADDON, ns = ...
local Core = WickCore
local Chrome, R = Core.Chrome, Core.Restrict
local C = Chrome.Colors

local UI = {}
ns.UI = UI

local RED    = { 0.80, 0.30, 0.30, 1 }
local AMBER  = { 0.85, 0.65, 0.25, 1 }
local HAPPY  = { [1] = RED, [2] = AMBER, [3] = C.fel }
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function tint(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
local function classCap(s) return s and (s:sub(1, 1) .. s:sub(2):lower()) or "" end

local function petLines(tt, s)
    if not s.exists then
        tt:AddLine("No pet out", 0.6, 0.6, 0.6)
        return
    end
    local h = s.happiness
    tt:AddLine(s.name or "Pet", 1, 1, 1)
    local sub = {}
    if s.family then sub[#sub + 1] = s.family end
    if s.level then sub[#sub + 1] = ("level %d"):format(s.level) end
    if s.dead then sub[#sub + 1] = "dead" end
    if #sub > 0 then tt:AddLine(table.concat(sub, ", "), 0.6, 0.6, 0.6) end
    if h then
        local c = HAPPY[h] or C.text
        local txt = ns.Pet.HAPPINESS_TEXT[h] or tostring(h)
        if s.damagePct then txt = txt .. (", %d%% damage"):format(s.damagePct) end
        tt:AddLine(txt, c[1], c[2], c[3])
        if s.loyaltyRate and s.loyaltyRate < 0 then tt:AddLine("Losing loyalty", RED[1], RED[2], RED[3])
        elseif s.loyaltyRate and s.loyaltyRate > 0 then tt:AddLine("Gaining loyalty", C.fel[1], C.fel[2], C.fel[3]) end
    else
        tt:AddLine(R:AurasBlocked() and "Happiness hidden in combat" or "Happiness unknown", 0.6, 0.6, 0.6)
    end
    if s.loyalty then tt:AddLine("Loyalty: " .. s.loyalty, 0.83, 0.78, 0.63) end
    if s.trainingTotal then
        tt:AddLine(("Training points: %d of %d free"):format(
            math.max(0, (s.trainingTotal or 0) - (s.trainingUsed or 0)), s.trainingTotal or 0), 0.83, 0.78, 0.63)
    end
    if s.diet and #s.diet > 0 then tt:AddLine("Eats: " .. table.concat(s.diet, ", "), 0.83, 0.78, 0.63) end
end

local function foodLines(tt, food)
    if food then
        if tt.SetItemByID then tt:SetItemByID(food.itemID) else tt:SetHyperlink("item:" .. food.itemID) end
        tt:AddLine(" ")
        tt:AddLine(food.pinned and "Pinned. /wbt food clear to go back to the best food in bags."
            or "Best food in your bags for this pet. Click or press the Feed pet key.", 0.6, 0.6, 0.6, true)
    else
        tt:SetText("Nothing to feed", 1, 1, 1)
        tt:AddLine(UnitExists("pet") and "Carry food the pet eats. Hover the pet for its diet." or "Call your pet first.", 0.6, 0.6, 0.6, true)
    end
end

local function ammoLines(tt, a)
    if not a.needed then
        tt:AddLine(a.weapon and (a.weapon .. " needs no ammo") or "No ranged weapon", 0.6, 0.6, 0.6)
        return
    end
    if not a.itemID then
        tt:AddLine("Ammo slot empty", RED[1], RED[2], RED[3])
        if a.fires then tt:AddLine(("Your %s fires %ss."):format(a.weaponType or "weapon", a.fires:lower()), 0.6, 0.6, 0.6) end
        return
    end
    tt:AddLine(a.name, 1, 1, 1)
    tt:AddLine(("%d equipped, %d in bags"):format(a.count or 0, a.bagCount or 0), 0.83, 0.78, 0.63)
    local warn = ns.db and ns.db.profile.ammoWarn or 200
    if a.mismatch then
        tt:AddLine(("Wrong ammo: %s fires %ss."):format(a.weapon or "your weapon", (a.fires or ""):lower()), RED[1], RED[2], RED[3])
    elseif (a.total or 0) < warn then
        tt:AddLine(("Below %d shots. Restock."):format(warn), RED[1], RED[2], RED[3])
    elseif (a.count or 0) < warn then
        tt:AddLine("Equipped stack is low; spares in bags.", AMBER[1], AMBER[2], AMBER[3])
    end
end

local function makeSecureFeed(parent)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    ns.Pet:RegisterFeedButton(b)
    return b
end

-- ============================================================
-- Compact strip
-- ============================================================

local STRIP_H  = 26
local PET_W    = 118
local FEED_W   = 26
local AMMO_W   = 74
local PAD      = 6

function UI:BuildStrip()
    if self.strip then return self.strip end
    local db = ns.db and ns.db.profile
    local f = CreateFrame("Frame", "WicksBeastsStrip", UIParent)
    self.strip = f
    f:SetSize(PAD + PET_W + 1 + FEED_W + 1 + AMMO_W + PAD, STRIP_H)
    f:SetPoint("CENTER", 0, -220)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if db and not db.stripLocked then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        if db then db.strip = db.strip or {}; Chrome:SavePosition(s, db.strip) end
    end)
    f:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then UI:Toggle() end end)
    if db and db.strip and db.strip.point then
        local w, h = f:GetWidth(), f:GetHeight()
        Chrome:RestorePosition(f, db.strip)
        f:SetSize(w, h)   -- position only; the strip sizes itself
    end
    f:Hide()

    local bg = Chrome:Texture(f, "BACKGROUND", C.voidBG); bg:SetAllPoints()
    Chrome:AddBorder(f)
    Chrome:AddBrackets(f)

    -- Pet segment
    local pet = CreateFrame("Frame", nil, f)
    pet:SetPoint("TOPLEFT", PAD, 0); pet:SetSize(PET_W, STRIP_H)
    pet:EnableMouse(true)
    f.happy = {}
    for i = 1, 3 do
        local t = Chrome:Texture(pet, "ARTWORK", C.border)
        t:SetSize(5, 12)
        t:SetPoint("LEFT", (i - 1) * 7, 0)
        f.happy[i] = t
    end
    f.petName = Chrome:Text(pet, 11)
    f.petName:SetPoint("LEFT", 24, 0)
    f.petName:SetPoint("RIGHT", -4, 0)
    f.petName:SetJustifyH("LEFT")
    f.petName:SetWordWrap(false)
    pet:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        petLines(GameTooltip, ns.Pet:State())
        GameTooltip:Show()
    end)
    pet:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Drag and right-click pass through the segment to the strip.
    pet:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" and db and not db.stripLocked then f:StartMoving() end end)
    pet:SetScript("OnMouseUp", function(_, btn)
        f:StopMovingOrSizing()
        if btn == "RightButton" then UI:Toggle() elseif db then db.strip = db.strip or {}; Chrome:SavePosition(f, db.strip) end
    end)

    local div1 = Chrome:Texture(f, "ARTWORK", C.border)
    div1:SetPoint("TOPLEFT", pet, "TOPRIGHT", 0, -1); div1:SetPoint("BOTTOMLEFT", pet, "BOTTOMRIGHT", 0, 1); div1:SetWidth(1)

    -- Feed segment: the food icon is the button. It is a protected frame,
    -- so it anchors to the pet segment frame, never to a texture.
    local feed = makeSecureFeed(f)
    feed:SetPoint("LEFT", pet, "RIGHT", 3, 0)
    feed:SetSize(FEED_W - 4, STRIP_H - 4)
    feed.icon = feed:CreateTexture(nil, "ARTWORK")
    feed.icon:SetAllPoints()
    feed.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    feed.count = Chrome:Text(feed, 9)
    feed.count:SetPoint("BOTTOMRIGHT", -1, 1)
    feed.hl = feed:CreateTexture(nil, "HIGHLIGHT")
    feed.hl:SetAllPoints()
    feed.hl:SetColorTexture(1, 1, 1, 0.12)
    feed:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        foodLines(GameTooltip, ns.Pet.lastFood)
        GameTooltip:Show()
    end)
    feed:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.feed = feed

    local div2 = Chrome:Texture(f, "ARTWORK", C.border)
    div2:SetPoint("TOPLEFT", feed, "TOPRIGHT", 2, 1); div2:SetPoint("BOTTOMLEFT", feed, "BOTTOMRIGHT", 2, -1); div2:SetWidth(1)

    -- Ammo segment
    local ammo = CreateFrame("Frame", nil, f)
    ammo:SetPoint("LEFT", div2, "RIGHT", 0, 0); ammo:SetSize(AMMO_W, STRIP_H)
    ammo:EnableMouse(true)
    f.ammoIcon = ammo:CreateTexture(nil, "ARTWORK")
    f.ammoIcon:SetSize(16, 16)
    f.ammoIcon:SetPoint("LEFT", 5, 0)
    f.ammoIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.ammoText = Chrome:Text(ammo, 11)
    f.ammoText:SetPoint("LEFT", f.ammoIcon, "RIGHT", 5, 0)
    f.ammoText:SetPoint("RIGHT", -4, 0)
    f.ammoText:SetJustifyH("LEFT")
    f.ammoText:SetWordWrap(false)
    ammo:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        ammoLines(GameTooltip, ns.Ammo:State())
        GameTooltip:Show()
    end)
    ammo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ammo:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" and db and not db.stripLocked then f:StartMoving() end end)
    ammo:SetScript("OnMouseUp", function(_, btn)
        f:StopMovingOrSizing()
        if btn == "RightButton" then UI:Toggle() elseif db then db.strip = db.strip or {}; Chrome:SavePosition(f, db.strip) end
    end)

    f:SetScript("OnShow", function() UI:RefreshStrip() end)
    R:OnChange(function() if f:IsShown() then UI:RefreshStrip() end end)
    return f
end

function UI:ApplyStripVisibility()
    local db = ns.db and ns.db.profile
    local want = ns.isHunter and db and db.showStrip ~= false
    if want then
        self:BuildStrip()
        self.strip:Show()
        self:RefreshStrip()
    elseif self.strip then
        self.strip:Hide()
    end
end

function UI:SetStripLocked(locked)
    local db = ns.db and ns.db.profile
    if db then db.stripLocked = locked and true or false end
    ns.A:Print(locked and "strip locked." or "strip unlocked: drag it into place, then /wbt lock.")
end

function UI:RefreshStrip()
    local f = self.strip
    if not f or not f.ammoText or not f:IsShown() then return end
    local s = ns.Pet:State()
    local h = s.exists and s.happiness or nil
    for i = 1, 3 do
        local c = (h and i <= h) and (HAPPY[h] or C.fel) or C.border
        f.happy[i]:SetColorTexture(c[1], c[2], c[3], 1)
    end
    if s.exists then
        f.petName:SetText(s.name or "Pet")
        tint(f.petName, s.dead and RED or C.text)
    else
        f.petName:SetText("No pet")
        tint(f.petName, C.muted)
    end
    self:RefreshFeed()
    self:RefreshAmmo()
end

-- ============================================================
-- Details panel
-- ============================================================

function UI:Build()
    if self.panel then return self.panel end
    local db = ns.db and ns.db.profile
    local p = Chrome:NewPanel("WicksBeastsPanel", {
        title = "Wick's Beasts and Things", width = 340, height = 250,
        closable = true, strata = "MEDIUM", db = db and db.window,
    })
    self.panel = p
    local ct = p.content

    local y = 0
    local head = Chrome:Heading(ct, "Pet"); head:SetPoint("TOPLEFT", 0, y)
    y = y - 20
    p.petName = Chrome:Text(ct, 12); p.petName:SetPoint("TOPLEFT", 0, y)
    y = y - 18
    p.happy = {}
    for i = 1, 3 do
        local t = Chrome:Texture(ct, "ARTWORK", C.border)
        t:SetSize(22, 8)
        t:SetPoint("TOPLEFT", (i - 1) * 25, y - 3)
        p.happy[i] = t
    end
    p.happyText = Chrome:Text(ct, 11); p.happyText:SetPoint("LEFT", p.happy[3], "RIGHT", 10, 0)
    y = y - 18
    p.loyalty = Chrome:Text(ct, 11, C.muted); p.loyalty:SetPoint("TOPLEFT", 0, y)
    y = y - 16
    p.diet = Chrome:Text(ct, 11, C.muted); p.diet:SetPoint("TOPLEFT", 0, y)
    y = y - 22

    local feed = makeSecureFeed(ct)
    feed:SetSize(300, 24)
    feed:SetPoint("TOPLEFT", 0, y)
    local fbg = Chrome:Texture(feed, "BACKGROUND", C.shadow); fbg:SetAllPoints()
    Chrome:AddBorder(feed)
    feed.icon = feed:CreateTexture(nil, "ARTWORK")
    feed.icon:SetSize(18, 18)
    feed.icon:SetPoint("LEFT", 3, 0)
    feed.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    feed.label = Chrome:Text(feed, 11)
    feed.label:SetPoint("LEFT", feed.icon, "RIGHT", 8, 0)
    feed.label:SetPoint("RIGHT", -6, 0)
    feed.label:SetJustifyH("LEFT")
    feed:SetScript("OnEnter", function(s)
        for _, t in pairs(s.border) do t:SetColorTexture(C.fel[1], C.fel[2], C.fel[3], 1) end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        foodLines(GameTooltip, ns.Pet.lastFood)
        GameTooltip:Show()
    end)
    feed:SetScript("OnLeave", function(s)
        for _, t in pairs(s.border) do t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1) end
        GameTooltip:Hide()
    end)
    p.feed = feed
    y = y - 34

    local ahead = Chrome:Heading(ct, "Ammo"); ahead:SetPoint("TOPLEFT", 0, y)
    y = y - 20
    p.ammoIcon = ct:CreateTexture(nil, "ARTWORK")
    p.ammoIcon:SetSize(18, 18)
    p.ammoIcon:SetPoint("TOPLEFT", 0, y + 2)
    p.ammoIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.ammoText = Chrome:Text(ct, 11); p.ammoText:SetPoint("LEFT", p.ammoIcon, "RIGHT", 8, 0)
    y = y - 18
    p.ammoNote = Chrome:Text(ct, 10, C.muted); p.ammoNote:SetPoint("TOPLEFT", 0, y)

    local kitBtn = Chrome:Button(ct, "Kit", 70, 20)
    kitBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    kitBtn:SetScript("OnClick", function() ns.A.kit:Toggle() end)
    local optBtn = Chrome:Button(ct, "Options", 70, 20)
    optBtn:SetPoint("RIGHT", kitBtn, "LEFT", -6, 0)
    optBtn:SetScript("OnClick", function() ns.A:OpenOptions() end)
    local stripBtn = Chrome:Button(ct, "Strip", 70, 20)
    stripBtn:SetPoint("RIGHT", optBtn, "LEFT", -6, 0)
    stripBtn:SetScript("OnClick", function()
        if db then db.showStrip = not (db.showStrip ~= false) end
        UI:ApplyStripVisibility()
    end)

    p:SetScript("OnShow", function() UI:Refresh() end)
    R:OnChange(function() if p:IsShown() then UI:Refresh() end end)
    return p
end

function UI:Init()
    self:ApplyStripVisibility()
end

function UI:Toggle()
    self:Build()
    self.panel:Toggle()
end

function UI:RefreshPet()
    local p = self.panel
    if not p or not p:IsShown() then return end
    local s = ns.Pet:State()
    if not s.exists then
        p.petName:SetText("No pet out")
        tint(p.petName, C.muted)
        for i = 1, 3 do p.happy[i]:SetColorTexture(C.border[1], C.border[2], C.border[3], 1) end
        p.happyText:SetText("")
        p.loyalty:SetText("")
        p.diet:SetText("")
        return
    end
    local desc = s.name or "Pet"
    if s.family then desc = desc .. "  " .. s.family end
    if s.level then desc = desc .. ("  level %d"):format(s.level) end
    if s.dead then desc = desc .. "  (dead)" end
    p.petName:SetText(desc)
    tint(p.petName, s.dead and RED or C.text)

    local h = s.happiness
    for i = 1, 3 do
        local c = (h and i <= h) and (HAPPY[h] or C.fel) or C.border
        p.happy[i]:SetColorTexture(c[1], c[2], c[3], 1)
    end
    if h then
        local txt = ns.Pet.HAPPINESS_TEXT[h] or tostring(h)
        if s.damagePct then txt = txt .. ("  %d%% damage"):format(s.damagePct) end
        if s.loyaltyRate and s.loyaltyRate < 0 then txt = txt .. "  losing loyalty"
        elseif s.loyaltyRate and s.loyaltyRate > 0 then txt = txt .. "  gaining loyalty" end
        p.happyText:SetText(txt)
        tint(p.happyText, HAPPY[h] or C.text)
    else
        p.happyText:SetText(R:AurasBlocked() and "in combat" or "unknown")
        tint(p.happyText, C.muted)
    end

    local loy = s.loyalty and ("Loyalty: " .. s.loyalty) or ""
    if s.trainingTotal then
        loy = loy .. (loy ~= "" and "    " or "") .. ("Training points: %d of %d free"):format(
            math.max(0, (s.trainingTotal or 0) - (s.trainingUsed or 0)), s.trainingTotal or 0)
    end
    p.loyalty:SetText(loy)
    p.diet:SetText(#(s.diet or {}) > 0 and ("Eats: " .. table.concat(s.diet, ", ")) or "Diet unknown")
end

function UI:RefreshFeed(food)
    food = food or ns.Pet.lastFood
    -- Registering a feed button triggers this before its panel is finished,
    -- so each half checks that its regions exist.
    local p, f = self.panel, self.strip
    if p and p.feed and p.feed.label then
        if food then
            p.feed.icon:SetTexture(food.icon or QUESTION)
            p.feed.icon:Show()
            p.feed.label:SetText(("Feed  %s  x%d%s"):format(food.name or "?", food.count or 0, food.pinned and "  (pinned)" or ""))
            tint(p.feed.label, C.text)
        else
            p.feed.icon:Hide()
            p.feed.label:SetText(UnitExists("pet") and "Feed  (no food the pet will eat)" or "Feed  (no pet out)")
            tint(p.feed.label, C.muted)
        end
    end
    if f and f.feed and f.feed.count then
        if food then
            f.feed.icon:SetTexture(food.icon or QUESTION)
            f.feed.icon:SetDesaturated(false)
            f.feed.icon:SetAlpha(1)
            f.feed.count:SetText(food.count and food.count > 1 and tostring(food.count) or "")
        else
            f.feed.icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTraining")
            f.feed.icon:SetDesaturated(true)
            f.feed.icon:SetAlpha(0.35)
            f.feed.count:SetText("")
        end
    end
end

function UI:RefreshAmmo()
    local a = ns.Ammo:State()
    local warn = ns.db and ns.db.profile.ammoWarn or 200
    local color, note, text
    if not a.needed then
        color, text, note = C.muted, a.weapon and (a.weapon .. " needs no ammo") or "No ranged weapon", ""
    elseif not a.itemID then
        color, text = RED, "Ammo slot empty"
        note = a.fires and ("Your %s fires %ss."):format(a.weaponType or "weapon", a.fires:lower()) or ""
    else
        text = ("%s  %d equipped, %d in bags"):format(a.name, a.count or 0, a.bagCount or 0)
        if a.mismatch then
            color, note = RED, ("Wrong ammo: %s fires %ss."):format(a.weapon or "your weapon", (a.fires or ""):lower())
        elseif (a.total or 0) < warn then
            color, note = RED, ("Below %d shots. Restock."):format(warn)
        elseif (a.count or 0) < warn then
            color, note = AMBER, "Equipped stack is low; spares in bags."
        else
            color, note = C.text, ""
        end
    end

    local p = self.panel
    if p and p.ammoText and p:IsShown() then
        if a.itemID and a.needed then p.ammoIcon:SetTexture(a.icon or QUESTION); p.ammoIcon:Show() else p.ammoIcon:Hide() end
        p.ammoText:SetText(text)
        tint(p.ammoText, color)
        p.ammoNote:SetText(note)
    end
    local f = self.strip
    if f and f.ammoText and f:IsShown() then
        if a.itemID and a.needed then
            f.ammoIcon:SetTexture(a.icon or QUESTION)
            f.ammoIcon:SetDesaturated(false)
            f.ammoIcon:SetAlpha(1)
            local n = a.count or 0
            f.ammoText:SetText((a.bagCount or 0) > 0 and ("%d +%d"):format(n, a.bagCount) or tostring(n))
        else
            f.ammoIcon:SetTexture("Interface\\Icons\\INV_Ammo_Arrow_01")
            f.ammoIcon:SetDesaturated(true)
            f.ammoIcon:SetAlpha(0.35)
            f.ammoText:SetText(a.needed and "none" or "")
        end
        tint(f.ammoText, color)
    end
end

function UI:Refresh()
    if self.panel and self.panel:IsShown() then
        self:RefreshPet()
        self:RefreshFeed()
        self:RefreshAmmo()
    end
    self:RefreshStrip()
end

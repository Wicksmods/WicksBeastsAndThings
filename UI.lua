-- Wick's Beasts and Things
-- UI.lua: the pet and ammo panel.
--
-- One small panel in the Wick chrome: a pet card (name, family, level,
-- happiness, loyalty, training points, diet) with the Feed button under it,
-- and an ammo row that goes red when the quiver runs low or holds the
-- wrong kind. Everything on it is read out of combat; in combat the values
-- that turn secret simply stop updating and the card says so.

local ADDON, ns = ...
local Core = WickCore
local Chrome, R = Core.Chrome, Core.Restrict
local C = Chrome.Colors

local UI = {}
ns.UI = UI

local RED    = { 0.80, 0.30, 0.30, 1 }
local AMBER  = { 0.85, 0.65, 0.25, 1 }
local HAPPY  = { [1] = RED, [2] = AMBER, [3] = C.fel }

local function tint(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

function UI:Build()
    if self.panel then return self.panel end
    local db = ns.db and ns.db.profile
    local p = Chrome:NewPanel("WicksBeastsPanel", {
        title = "Wick's Beasts and Things", width = 340, height = 250,
        closable = true, strata = "MEDIUM", db = db and db.window,
    })
    self.panel = p
    local ct = p.content

    -- Pet card
    local y = 0
    local head = Chrome:Heading(ct, "Pet"); head:SetPoint("TOPLEFT", 0, y)
    y = y - 20

    p.petName = Chrome:Text(ct, 12); p.petName:SetPoint("TOPLEFT", 0, y)
    y = y - 18

    -- Happiness as three blocks that fill left to right.
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

    -- Feed button: a secure button in Wick chrome, registered with Pet so its
    -- macro is rewritten alongside the keybind's.
    local feed = CreateFrame("Button", nil, ct, "SecureActionButtonTemplate")
    feed:SetSize(300, 24)
    feed:SetPoint("TOPLEFT", 0, y)
    feed:RegisterForClicks("AnyUp", "AnyDown")
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
        local food = ns.Pet.lastFood
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        if food then
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(food.itemID)
            else GameTooltip:SetHyperlink("item:" .. food.itemID) end
            GameTooltip:AddLine(food.pinned and "Pinned food. /wbt food clear to unpin." or "Best food in your bags for this pet.", 0.5, 0.5, 0.5, true)
        else
            GameTooltip:SetText("Nothing to feed", 1, 1, 1)
            GameTooltip:AddLine("Carry food the pet eats. Its diet is listed above.", 0.5, 0.5, 0.5, true)
        end
        GameTooltip:Show()
    end)
    feed:SetScript("OnLeave", function(s)
        for _, t in pairs(s.border) do t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1) end
        GameTooltip:Hide()
    end)
    p.feed = feed
    ns.Pet:RegisterFeedButton(feed)
    y = y - 34

    -- Ammo row
    local ahead = Chrome:Heading(ct, "Ammo"); ahead:SetPoint("TOPLEFT", 0, y)
    y = y - 20
    p.ammoIcon = ct:CreateTexture(nil, "ARTWORK")
    p.ammoIcon:SetSize(18, 18)
    p.ammoIcon:SetPoint("TOPLEFT", 0, y + 2)
    p.ammoIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.ammoText = Chrome:Text(ct, 11); p.ammoText:SetPoint("LEFT", p.ammoIcon, "RIGHT", 8, 0)
    y = y - 18
    p.ammoNote = Chrome:Text(ct, 10, C.muted); p.ammoNote:SetPoint("TOPLEFT", 0, y)

    -- Footer buttons
    local kitBtn = Chrome:Button(ct, "Kit", 70, 20)
    kitBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    kitBtn:SetScript("OnClick", function() ns.A.kit:Toggle() end)
    local optBtn = Chrome:Button(ct, "Options", 70, 20)
    optBtn:SetPoint("RIGHT", kitBtn, "LEFT", -6, 0)
    optBtn:SetScript("OnClick", function() ns.A:OpenOptions() end)

    p:SetScript("OnShow", function() UI:Refresh() end)
    R:OnChange(function() if p:IsShown() then UI:Refresh() end end)
    return p
end

function UI:Init()
    -- Built lazily on first toggle; nothing to do until then.
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
        local on = h and i <= h
        local c = on and HAPPY[h] or C.border
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
    local p = self.panel
    if not p then return end
    food = food or ns.Pet.lastFood
    if food then
        p.feed.icon:SetTexture(food.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        p.feed.icon:Show()
        p.feed.label:SetText(("Feed  %s  x%d%s"):format(food.name or "?", food.count or 0, food.pinned and "  (pinned)" or ""))
        tint(p.feed.label, C.text)
    else
        p.feed.icon:Hide()
        p.feed.label:SetText(UnitExists("pet") and "Feed  (no food the pet will eat)" or "Feed  (no pet out)")
        tint(p.feed.label, C.muted)
    end
end

function UI:RefreshAmmo()
    local p = self.panel
    if not p or not p:IsShown() then return end
    local a = ns.Ammo:State()
    local warn = ns.db and ns.db.profile.ammoWarn or 200
    if not a.needed then
        p.ammoIcon:Hide()
        p.ammoText:SetText(a.weapon and (a.weapon .. " needs no ammo") or "No ranged weapon")
        tint(p.ammoText, C.muted)
        p.ammoNote:SetText("")
        return
    end
    if not a.itemID then
        p.ammoIcon:Hide()
        p.ammoText:SetText("Ammo slot empty")
        tint(p.ammoText, RED)
        p.ammoNote:SetText(a.fires and ("Your %s fires %ss."):format(a.weaponType or "weapon", a.fires:lower()) or "")
        return
    end
    p.ammoIcon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    p.ammoIcon:Show()
    p.ammoText:SetText(("%s  %d equipped, %d in bags"):format(a.name, a.count or 0, a.bagCount or 0))
    if a.mismatch then
        tint(p.ammoText, RED)
        p.ammoNote:SetText(("Wrong ammo: %s fires %ss."):format(a.weapon or "your weapon", (a.fires or ""):lower()))
    elseif (a.total or 0) < warn then
        tint(p.ammoText, RED)
        p.ammoNote:SetText(("Below %d shots. Restock."):format(warn))
    elseif (a.count or 0) < warn then
        tint(p.ammoText, AMBER)
        p.ammoNote:SetText("Equipped stack is low; spares in bags.")
    else
        tint(p.ammoText, C.text)
        p.ammoNote:SetText("")
    end
end

function UI:Refresh()
    if not self.panel or not self.panel:IsShown() then return end
    self:RefreshPet()
    self:RefreshFeed()
    self:RefreshAmmo()
end

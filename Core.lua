-- Wick's Beasts and Things
-- Core.lua: WickCore addon object, saved variables, event dispatch, slash command.
--
-- The hunter kit for World of Warcraft: Forever. A hunter's setup is a pet
-- and a quiver: the pet has to be out, fed and loyal, the quiver has to be
-- full of the right ammo. Both are readable out of combat and neither is a
-- combat tracker, so the kit fits Forever's addon rules as they stand.
-- Through WickCore the kit adds the talent layer, the pre-pull checklist
-- and racials.

local ADDON, ns = ...

local Core = WickCore
assert(Core, "Wick's Beasts and Things requires WickCore. Enable the WickCore addon.")
local D, R = Core.Dialect, Core.Restrict

ns.version = "0.1.0"

local PROFILE_DEFAULTS = {
    ammoWarn      = 200,     -- the ammo row turns red below this many shots
    foodItem      = false,   -- itemID to feed instead of the best food found
    preferCheap   = false,   -- lowest eligible food instead of the highest
    beastTooltip  = true,    -- name a beast family's abilities in its tooltip
    showStrip     = true,    -- the compact strip that stays on screen
    stripLocked   = true,
    strip         = {},
    window        = {},
    kitWindow     = {},
    bestiaryWindow = {},
}

-- The bestiary is per character. Another hunter's animals are not yours,
-- and a hunter owns a handful at most, so the whole roster is small enough
-- to ride along in the settings store rather than be treated as a cache.
local CHAR_DEFAULTS = {
    pets = {},
}

local A = Core:NewAddon("WicksBeastsAndThings", {
    title    = "Wick's Beasts and Things",
    version  = ns.version,
    savedVar = "WicksBeastsSaved",
    defaults = { profile = PROFILE_DEFAULTS, char = CHAR_DEFAULTS, global = {} },
})
ns.A = A

-- ============================================================
-- Event dispatcher
-- ============================================================
local events = {}
function ns:On(event, fn)
    events[event] = events[event] or {}
    table.insert(events[event], fn)
end

local frame = CreateFrame("Frame", "WicksBeastsEvents")
ns.eventFrame = frame
frame:SetScript("OnEvent", function(_, event, ...)
    if events[event] then
        for _, fn in ipairs(events[event]) do
            local ok, err = pcall(fn, event, ...)
            if not ok then A:Print(("error in %s: %s"):format(event, tostring(err))) end
        end
    end
end)
function ns.RegisterEvents(list)
    for _, ev in ipairs(list) do pcall(frame.RegisterEvent, frame, ev) end
end

local _, playerClass = UnitClass("player")
ns.isHunter = playerClass == "HUNTER"

-- Spell IDs (rank 1) used for "known" gates on the checklist.
ns.SPELL = {
    ASPECT_HAWK   = 13165,
    ASPECT_MONKEY = 13163,
    CALL_PET      = 883,
    FEED_PET      = 6991,
    TRUESHOT_AURA = 19506,
}

-- ============================================================
-- Lifecycle
-- ============================================================
function A:OnInitialize()
    ns.db = self.db
    self.db:On("OnProfileChanged", function()
        if ns.UI and ns.UI.ApplyStripVisibility then ns.UI:ApplyStripVisibility() end
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.Pet and ns.Pet.UpdateFeedMacro then ns.Pet:UpdateFeedMacro() end
    end)

    Core.Cooldowns:New(self, { key = "cooldownBar" })

    Core.Kit:New(self, {
        racials = true,
        tabs = {
            { id = "beasts", label = "Beasts",
              attach = function(pane) if ns.beasts then ns.beasts:AttachPane(pane) end end },
            { id = "bestiary", label = "Bestiary",
              attach = function(pane) if ns.Bestiary then ns.Bestiary:AttachPane(pane) end end },
        },
        checklist = {
            { label = "Aspect up",
              aura = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah",
                       "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Beast" },
              cast = "Aspect of the Hawk", known = ns.SPELL.ASPECT_MONKEY },
            { label = "Pet out", cast = "Call Pet", known = ns.SPELL.CALL_PET, check = function()
                local s = ns.Pet:State()
                if not s then return nil end
                return s.exists and not s.dead
            end },
            { label = "Pet fed", known = ns.SPELL.FEED_PET, check = function()
                local s = ns.Pet:State()
                if not s or not s.exists then return false end
                if s.happiness == nil then return nil end
                return s.happiness == 3
            end },
            { label = "Ammo stocked", check = function()
                local a = ns.Ammo:State()
                if not a then return nil end
                if not a.needed then return true end
                if a.mismatch then return false end
                return a.count > 0 and a.count >= (ns.db.profile.ammoWarn or 0)
            end },
            { label = "Trueshot Aura", aura = "Trueshot Aura", cast = "Trueshot Aura", known = ns.SPELL.TRUESHOT_AURA },
        },
    })
end

function A:OnEnable()
    if not ns.isHunter then
        self:Print("loaded (non-hunter: viewer mode).")
    else
        self:Print("loaded. /wbt for the pet and ammo panel, /wbt kit for talents and checklist.")
    end
    if ns.Pet and ns.Pet.Init then ns.Pet:Init() end
    if ns.Ammo and ns.Ammo.Init then ns.Ammo:Init() end
    if ns.Bestiary and ns.Bestiary.Init then ns.Bestiary:Init() end
    if ns.UI and ns.UI.Init then ns.UI:Init() end
    if self.cooldowns then self.cooldowns:Init() end
    if ns.beasts then ns.beasts:Init() end

    self:RegisterLauncher({
        onClick = function(_, button)
            if button == "RightButton" then self.kit:Toggle()
            else ns.UI:Toggle() end
        end,
        tooltip = function(tt)
            tt:AddLine(Core.Chrome:TitleMarkup("Wick's Beasts and Things"))
            tt:AddLine("Left-click: pet and ammo   Right-click: talents and checklist", 0.5, 0.5, 0.5)
        end,
    })

    self:RegisterOptions(function(page, addon)
        local O = Core.Options
        local db = addon.db.profile
        local y = O:Heading(page, "Strip", 0)
        y = O:Check(page, "Show the compact strip", function() return db.showStrip ~= false end,
            function(v) db.showStrip = v; ns.UI:ApplyStripVisibility() end, y)
        y = O:Check(page, "Lock the strip", function() return db.stripLocked ~= false end,
            function(v) db.stripLocked = v end, y)
        y = O:Note(page, "One row: pet happiness and name, the feed button, ammo. Hover any part for detail, right-click for the full panel.", y)
        y = O:Heading(page, "Feeding", y - 6)
        y = O:Check(page, "Prefer the cheapest eligible food", function() return db.preferCheap == true end,
            function(v) db.preferCheap = v; ns.Pet:UpdateFeedMacro(); ns.UI:Refresh() end, y)
        y = O:Note(page, "The feed key picks the best food in your bags that the pet will eat. Pin one with /wbt food <item link>, clear it with /wbt food clear.", y)
        y = O:Heading(page, "Ammo", y - 6)
        y = O:Note(page, ("Warn below %d shots. Change it with /wbt ammo <count>."):format(db.ammoWarn or 200), y)
        y = O:Button(page, "Open panel", function() ns.UI:Toggle() end, y, 100)
        y = O:Button(page, "Open kit", function() addon.kit:Toggle() end, y, 100)
        if ns.beasts then y = ns.beasts:OptionRow(page, y - 6) end
        if addon.cooldowns then y = addon.cooldowns:OptionRow(page, y - 6) end
        y = O:ProfileSection(page, addon, y - 8)
    end)
end

-- Keybinding entry points
BINDING_HEADER_WICKSBEASTS = "Wick's Beasts and Things"
_G["BINDING_NAME_CLICK WicksBeastsFeedButton:LeftButton"] = "Feed pet"
BINDING_NAME_WICKSBEASTS_TOGGLE = "Toggle pet and ammo panel"
function WicksBeastsAndThings_Toggle() if ns.UI then ns.UI:Toggle() end end

-- ============================================================
-- Slash command
-- ============================================================
A:RegisterSlash(function(_, msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local lower = msg:lower()
    if lower == "" or lower == "show" or lower == "toggle" then ns.UI:Toggle() return end
    if lower == "strip" then
        A.db.profile.showStrip = not (A.db.profile.showStrip ~= false)
        ns.UI:ApplyStripVisibility()
        A:Print("strip " .. (A.db.profile.showStrip and "shown" or "hidden") .. ".")
        return
    end
    if lower == "unlock" or lower == "move" then ns.UI:SetStripLocked(false) return end
    if lower == "lock" then ns.UI:SetStripLocked(true) return end
    if lower == "kit" or lower == "talents" or lower == "checklist" then A.kit:Toggle() return end
    if lower == "cd" or lower:match("^cd%s") then return A.cooldowns:Command(msg:match("^%a+%s*(.*)$")) end
    if lower == "beasts" or lower:match("^beasts%s") then
        local rest = msg:match("^%a+%s+(.*)$")
        if rest == "clear" then
            ns.beasts:Forget()
            A:Print("beast atlas cleared.")
        elseif rest and rest ~= "" then
            if ns.beasts:Forget(rest) then A:Print("forgot " .. rest .. ".")
            else A:Print("nothing recorded for " .. rest .. ".") end
        else
            ns.beasts:Report(function(line) A:Print(line) end)
        end
        return
    end
    if lower == "bestiary" then ns.Bestiary:Toggle() return end
    if lower == "pets" or lower:match("^pets%s") then
        local rest = msg:match("^%a+%s+(.*)$")
        if rest == "clear" or rest == "forget" then
            ns.Bestiary:Forget()
            A:Print("bestiary cleared.")
        elseif rest and rest ~= "" then
            local gone, name = ns.Bestiary:Forget(rest)
            if gone then A:Print("forgot " .. (name or rest) .. ".")
            else A:Print("no animal recorded by that name.") end
        else
            ns.Bestiary:Report(function(line) A:Print(line) end)
        end
        if ns.Bestiary.pane then ns.Bestiary:RefreshPane() end
        ns.Bestiary:RefreshWindow()
        return
    end
    if lower == "options" or lower == "config" then A:OpenOptions() return end
    local db = A.db.profile
    if lower:match("^ammo") then
        local n = tonumber(lower:match("^ammo%s+(%d+)") or "")
        if not n then A:Print(("ammo warning at %d shots. Use /wbt ammo <count>."):format(db.ammoWarn or 200)) return end
        db.ammoWarn = n
        A:Print(("ammo warning set to %d shots."):format(n))
        ns.UI:Refresh()
        return
    end
    if lower:match("^food") then
        local arg = msg:match("^%a+%s+(.+)$")
        if not arg then
            local food = ns.Pet:BestFood()
            local rec = ns.Bestiary:Current()
            if rec and rec.food then
                A:Print(("pinned for %s: item %d"):format(rec.name or "this pet", rec.food))
            elseif db.foodItem then
                A:Print("pinned food: item " .. tostring(db.foodItem) .. " (for any pet)")
            else
                A:Print("no pinned food; feeding the best food in bags.")
            end
            A:Print(food and ("next feed: %s x%d"):format(food.name or "?", food.count or 0) or "nothing in your bags that the pet will eat.")
            return
        end
        if arg:lower() == "clear" or arg:lower() == "off" then
            -- Clear both, or clearing with a pet out leaves the hunter-wide
            -- pin quietly in force and looks like the command did nothing.
            db.foodItem = false
            ns.Bestiary:Pin(nil)
            A:Print("pinned food cleared.")
        else
            local id = tonumber(arg) or tonumber(arg:match("item:(%d+)") or "")
            if not id then A:Print("give an item link or item ID: /wbt food [Haunch of Meat]") return end
            -- A cat and a boar do not eat the same thing, so the pin belongs
            -- to the animal whenever there is one to pin it to.
            local who = ns.Bestiary:Pin(id)
            if who then
                A:Print(("pinned food for %s: item %d"):format(who, id))
            else
                db.foodItem = id
                A:Print("no pet out, so pinned for any pet: item " .. id)
            end
        end
        ns.Pet:UpdateFeedMacro()
        ns.UI:Refresh()
        return
    end
    if lower == "status" or lower == "debug" then
        local s = ns.Pet:State() or {}
        local a = ns.Ammo:State() or {}
        A:Print(("pet %s  happiness %s  loyalty %s  points %s/%s  diet %s"):format(
            tostring(s.name or "none"), tostring(s.happiness), tostring(s.loyalty),
            tostring(s.trainingUsed), tostring(s.trainingTotal), table.concat(s.diet or {}, ", ")))
        A:Print(("ammo %s  count %s  bags %s  needed %s  mismatch %s"):format(
            tostring(a.name or "none"), tostring(a.count), tostring(a.bagCount), tostring(a.needed), tostring(a.mismatch)))
        A:Print("feed macro: " .. (ns.Pet.lastMacro or ""):gsub("\n", " | "))
        local Bst = ns.Bestiary
        local cur = Bst and Bst:Current()
        A:Print(("bestiary %d recorded  out now %s  last skip %s"):format(
            Bst and Bst:Count() or -1,
            cur and (cur.name or "?") or "none",
            tostring(Bst and Bst.why or "none")))
        return
    end
    A:Print("commands: show | strip | lock | unlock | kit | cd | bestiary | pets [name|clear] | options | ammo <count> | food [link|clear] | status")
end, "/wbt", "/wbeasts")

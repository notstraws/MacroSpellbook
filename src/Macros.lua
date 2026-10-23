local addonName, smb = ...

-- Builds the page's macro list (smb.macros) from the spellbook and the player's class config, and keeps
-- the WoW macros it creates in step with it. No frames here: SpellBookTab.lua draws the page.

local ICON_QUESTION_MARK = 134400 -- Interface\Icons\INV_Misc_QuestionMark

local MAX_MACRO_NAME = 16 -- longer names are truncated by CreateMacro, so GetMacroIndexByName would miss them
local MAX_MACRO_BODY = 255
local FOCUS_SUFFIX = " @F" -- ends a focus copy's WoW macro name, keeping it apart from the spell's own

-- MAX_CHARACTER_MACROS and MAX_ACCOUNT_MACROS come from the load-on-demand Blizzard_MacroUI, so they
-- are nil until the macro window has been opened once.
local function maxCharacterMacros()
    return MAX_CHARACTER_MACROS or 18
end

local function maxAccountMacros()
    return MAX_ACCOUNT_MACROS or 120
end

-- Per-account sets of spell names, keyed by setting: "mouseover" (macro casts on the mouseover unit
-- first), "cursor" (macro casts a ground-targeted spell where the cursor points), "focus" (the page
-- also lists a copy of the macro that casts on the focus target), "pet" (a summon macro casts the
-- pet's ability while that pet is out), "raidRank1" (the macro casts rank 1 in a raid group), "spam"
-- (the macro does nothing while its channelled spell is channelling, or its stealth spell is on), "stance" (the macro switches to a
-- stance the spell can be cast in first), "petAttack" (the macro also sends
-- the pet to attack), "stopCast" (the macro stops the current cast first) or "startAttack" (the macro
-- starts melee auto-attack after the cast). For petAttack, stopCast and startAttack, true or false overrides the
-- setting's default (optionDefault), nil follows it. "useItems" holds a list of equipment slots instead of a
-- flag: the macro uses each slot's item, in that order, before the cast. Read lazily: saved
-- variables are not loaded until ADDON_LOADED, after this file runs.
local function settings(key)
    MacroSpellbookDB = MacroSpellbookDB or {}
    MacroSpellbookDB[key] = MacroSpellbookDB[key] or {}
    return MacroSpellbookDB[key]
end

-- Whether the page also lists the class spells not learned yet, in their sections among the learned ones.
function smb.showsUnlearned()
    return MacroSpellbookDB ~= nil and MacroSpellbookDB.showUnlearned == true
end

function smb.setShowUnlearned(on)
    MacroSpellbookDB = MacroSpellbookDB or {}
    MacroSpellbookDB.showUnlearned = on or nil
end

-- Whether a plain spell on an action bar counts as its macro being placed even when the macro has options
-- on (see smb.isOnActionBars). Macros with no options on always count it.
function smb.countsSpellsOnBars()
    return MacroSpellbookDB ~= nil and MacroSpellbookDB.countSpellsOnBars == true
end

function smb.setCountSpellsOnBars(on)
    MacroSpellbookDB = MacroSpellbookDB or {}
    MacroSpellbookDB.countSpellsOnBars = on or nil
end

-- Whether "petAttack" is on for every enemy spell macro that has no setting of its own.
function smb.petAttacksByDefault()
    return MacroSpellbookDB ~= nil and MacroSpellbookDB.petAttackDefault == true
end

function smb.setPetAttacksByDefault(on)
    MacroSpellbookDB = MacroSpellbookDB or {}
    MacroSpellbookDB.petAttackDefault = on or nil
end

-- Whether "stopCast" is on for every spell macro that has no setting of its own.
function smb.stopsCastingByDefault()
    return MacroSpellbookDB ~= nil and MacroSpellbookDB.stopCastDefault == true
end

function smb.setStopsCastingByDefault(on)
    MacroSpellbookDB = MacroSpellbookDB or {}
    MacroSpellbookDB.stopCastDefault = on or nil
end

-- Whether "startAttack" is on for every spell macro that has no setting of its own.
function smb.startsAttackByDefault()
    return MacroSpellbookDB ~= nil and MacroSpellbookDB.startAttackDefault == true
end

function smb.setStartsAttackByDefault(on)
    MacroSpellbookDB = MacroSpellbookDB or {}
    MacroSpellbookDB.startAttackDefault = on or nil
end

-- The settings with a default; each spell macro stores one only where it differs from the default.
local DEFAULTED = { petAttack = true, stopCast = true, startAttack = true }

-- The default of a setting that has one ("petAttack", "stopCast" or "startAttack"), or nil.
local function optionDefault(key)
    if key == "petAttack" then return smb.petAttacksByDefault() end
    if key == "stopCast" then return smb.stopsCastingByDefault() end
    if key == "startAttack" then return smb.startsAttackByDefault() end
end

local function toggleSetting(key, name)
    local set = settings(key)
    set[name] = not set[name] or nil
end

-- Turns a config list into a function returning a spell name's position in it, or nil. Entries ending
-- in * match by prefix.
local function nameMatcher(list)
    local exact, prefixes = {}, {}
    for i, entry in ipairs(list or {}) do
        local prefix = entry:match("^(.-)%*$")
        if prefix then
            prefixes[#prefixes + 1] = {prefix = prefix, index = i}
        elseif not exact[entry] then
            exact[entry] = i
        end
    end
    return function(name)
        if exact[name] then return exact[name] end
        for _, p in ipairs(prefixes) do
            if name:sub(1, #p.prefix) == p.prefix then return p.index end
        end
    end
end

local UNLISTED = math.huge -- spells in no category sort after everything else
local PET_CLASSES = { HUNTER = true, WARLOCK = true } -- classes with a combat pet; only they get pet settings
-- classes that fight with auto-attack; they get "startAttack" in place of "stopCast"
local MELEE_CLASSES = { WARRIOR = true, HUNTER = true, ROGUE = true }

local config -- the player's class config with its matchers, built on first use

-- The player's class config (Config/<Class>.lua), with its lists compiled into matchers. Built lazily so
-- every config file has loaded first.
local function classConfig()
    if config then return config end
    local class = select(2, UnitClass("player"))
    local source = smb.classConfigs[class] or {}
    local hasPet = PET_CLASSES[class] == true
    config = {
        categories = source.categories or {},
        custom = source.custom or {},
        extraSpells = source.extraSpells or {},
        petAbilities = hasPet and source.petAbilities or {},
        stances = source.stances or {},
        hasStances = source.stances ~= nil,
        petAttack = hasPet,
        startAttack = MELEE_CLASSES[class] == true,
        categoryMatchers = {},
        categoryRankByName = {},
        isEnemySpell = nameMatcher(source.mouseoverEnemy),
        isFriendSpell = nameMatcher(source.mouseoverFriend),
        isCursorSpell = nameMatcher(source.cursor),
        isRaidRank1Spell = nameMatcher(source.raidRank1),
        isChanneledSpell = nameMatcher(source.channeled),
        isStealthSpell = nameMatcher(source.stealth),
    }
    for rank, category in ipairs(config.categories) do
        config.categoryMatchers[rank] = nameMatcher(category.spells)
        config.categoryRankByName[category.name] = config.categoryRankByName[category.name] or rank
    end
    return config
end

-- A spell's section rank, section name and position within it. The first matching category wins.
local function categoryOf(name)
    local c = classConfig()
    for rank, matches in ipairs(c.categoryMatchers) do
        local priority = matches(name)
        if priority then return rank, c.categories[rank].name, priority end
    end
    return UNLISTED, "Unsorted", UNLISTED
end

-- The macro conditional a spell's mouseover option uses, or nil for spells without one. A spell in both
-- lists casts on any unit.
local function targetOf(name)
    local c = classConfig()
    local enemy, friend = c.isEnemySpell(name), c.isFriendSpell(name)
    if enemy and friend then return "exists" end
    if enemy then return "harm" end
    if friend then return "help" end
end

-- Whether the player's class has a combat pet, which turns on the "petAttack" option.
function smb.classOffersPetAttack()
    return classConfig().petAttack
end

-- Enemy spell macros offer "petAttack" when the class does. A focus copy shares its spell's setting.
function smb.offersPetAttack(macro)
    return smb.classOffersPetAttack() and macro.target == "harm" and not macro.custom
end

-- Whether the player's class is a melee one, which swaps the "stopCast" option for "startAttack".
function smb.classOffersStartAttack()
    return classConfig().startAttack
end

-- Every spell macro offers "stopCast", or "startAttack" for a melee class, except a stealth spell's:
-- attacking would break the stealth. A focus copy shares its spell's setting. Custom and equipment macros
-- offer neither.
function smb.offersStopCast(macro)
    return not macro.custom and not macro.equipment and not smb.classOffersStartAttack()
end

function smb.offersStartAttack(macro)
    return not macro.custom and not macro.equipment and not macro.stealth and smb.classOffersStartAttack()
end

-- Whether a macro offers an option ("mouseover", "cursor", "focus", "pet", "raidRank1", "spam", "stance",
-- "petAttack", "stopCast" or "startAttack") and the player turned it on.
function smb.isOptionOn(macro, key)
    if DEFAULTED[key] then
        local offered
        if key == "petAttack" then
            offered = smb.offersPetAttack(macro)
        elseif key == "stopCast" then
            offered = smb.offersStopCast(macro)
        else
            offered = smb.offersStartAttack(macro)
        end
        if not offered then return false end
        local on = settings(key)[macro.name]
        if on == nil then return optionDefault(key) end
        return on
    end
    local offered
    if key == "cursor" then
        offered = macro.cursor
    elseif key == "pet" then
        offered = macro.petAbility ~= nil
    elseif key == "raidRank1" then
        offered = macro.raidRank1
    elseif key == "spam" then
        offered = macro.spam ~= nil
    elseif key == "stance" then
        offered = macro.stances ~= nil
    else
        offered = macro.target ~= nil
    end
    return offered and settings(key)[macro.name] == true
end

-- Whether a macro offers a way to cast other than the plain spell's (any option but stopCast and
-- startAttack).
function smb.hasCastOptions(macro)
    return macro.target ~= nil or macro.cursor or macro.petAbility ~= nil or macro.raidRank1 or macro.spam ~= nil
        or macro.stances ~= nil
end

-- Every spell macro offers using equipped items before the cast. A focus copy shares its spell's slots.
function smb.offersUseItems(macro)
    return not macro.custom and not macro.equipment
end

local NO_SLOTS = {}

-- The equipment slots a macro uses before its cast, in the order the player ticked them. Don't modify it.
function smb.useItemSlots(macro)
    if not smb.offersUseItems(macro) then return NO_SLOTS end
    return settings("useItems")[macro.name] or NO_SLOTS
end

-- A slot's place in a macro's useItemSlots, or nil when the macro doesn't use it.
function smb.isUsingSlot(macro, slot)
    for i, used in ipairs(smb.useItemSlots(macro)) do
        if used == slot then return i end
    end
end

-- Whether a macro has an options menu: every spell macro does, for stopCast or startAttack.
function smb.hasOptions(macro)
    return smb.hasCastOptions(macro) or smb.offersStopCast(macro) or smb.offersStartAttack(macro)
        or smb.offersUseItems(macro)
end

-- A macro conditional joining the given conditions (nil or "" ones are skipped) behind the always-present
-- spam condition (nil or ""), e.g. "[nochanneling:Drain Life,@mouseover,harm,nodead]". Returns "" when
-- there is nothing to check, so a plain cast stays "/cast Name".
local function cond(spam, ...)
    local parts = {}
    if spam and spam ~= "" then parts[1] = spam end
    for i = 1, select("#", ...) do
        local c = select(i, ...)
        if c and c ~= "" then parts[#parts + 1] = c end
    end
    return #parts > 0 and "[" .. table.concat(parts, ",") .. "]" or ""
end

-- A /cast of name that tries each target conditional in turn ("" for none), with a rank 1 cast in a raid
-- group before each one.
local function raidRank1Cast(name, targets, spam)
    local clauses = {}
    for _, target in ipairs(targets) do
        clauses[#clauses + 1] = cond(spam, target, "group:raid") .. " " .. name .. "(Rank 1)"
        local plain = cond(spam, target)
        clauses[#clauses + 1] = (plain ~= "" and plain .. " " or "") .. name
    end
    return "/cast " .. table.concat(clauses, "; ")
end

-- A focus copy switches back to the previous target after the cast.
local FOCUS_FOOTER = "\n/script TargetLastTarget()"

-- The body macroBody gives a spell macro with no options on, which does just what the plain spell does.
local function bareBody(name)
    return "#showtooltip\n/cast " .. name
end

-- The slot a Warrior stance always takes on the stance bar, for one not learned yet: they are learned in
-- this order.
local WARRIOR_STANCE_SLOTS = { ["Battle Stance"] = 1, ["Defensive Stance"] = 2, ["Berserker Stance"] = 3 }

-- A stance's slot on the stance bar (the n of [stance:n]), or nil when unknown.
local function stanceSlot(stance)
    for i = 1, GetNumShapeshiftForms() do
        local spellID = select(4, GetShapeshiftFormInfo(i))
        if spellID and C_Spell.GetSpellName(spellID) == stance then return i end
    end
    return WARRIOR_STANCE_SLOTS[stance]
end

-- A line switching to the first of a spell's stances unless already in one of them, e.g.
-- "/cast [nostance:1/3] Battle Stance\n", or "" when the first stance's slot is unknown.
local function stanceLine(stances)
    if not stanceSlot(stances[1]) then return "" end
    local slots = {}
    for _, stance in ipairs(stances) do
        slots[#slots + 1] = stanceSlot(stance)
    end
    return "/cast [nostance:" .. table.concat(slots, "/") .. "] " .. stances[1] .. "\n"
end

-- The stances a stance-using class can be in: the Warrior stances and whatever is on the stance bar.
local function knownStances()
    local names = {}
    for name in pairs(WARRIOR_STANCE_SLOTS) do names[#names + 1] = name end
    for i = 1, GetNumShapeshiftForms() do
        local spellID = select(4, GetShapeshiftFormInfo(i))
        local name = spellID and C_Spell.GetSpellName(spellID)
        if name and not WARRIOR_STANCE_SLOTS[name] then names[#names + 1] = name end
    end
    return names
end

local scanTooltip -- hidden tooltip for clients without C_TooltipInfo

-- The text of a tooltip's lines, left and right. infoGetter is the C_TooltipInfo function and setter the
-- GameTooltip method that fill it (e.g. "GetSpellByID" and "SetSpellByID"), both called with the rest.
local function scanLines(infoGetter, setter, ...)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo[infoGetter] then
        local data = C_TooltipInfo[infoGetter](...)
        for _, line in ipairs(data and data.lines or {}) do
            lines[#lines + 1] = line.leftText
            lines[#lines + 1] = line.rightText
        end
        return lines
    end
    local name = addonName .. "ScanTooltip"
    scanTooltip = scanTooltip or CreateFrame("GameTooltip", name, nil, "GameTooltipTemplate")
    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTooltip[setter](scanTooltip, ...)
    for i = 1, scanTooltip:NumLines() do
        for _, side in ipairs({"Left", "Right"}) do
            local text = _G[name .. "Text" .. side .. i]
            lines[#lines + 1] = text and text:GetText()
        end
    end
    scanTooltip:Hide()
    return lines
end

-- The text of a spell's tooltip lines, left and right.
local function tooltipLines(id)
    return scanLines("GetSpellByID", "SetSpellByID", id)
end

-- The stances a spell's tooltip says it requires ("Requires Battle Stance, Defensive Stance"), in the
-- tooltip's order, or nil when it names none or isn't loaded.
local function tooltipStances(id)
    for _, text in ipairs(tooltipLines(id)) do
        if type(text) == "string" and text:find("Requires", 1, true) then
            local found = {}
            for _, stance in ipairs(knownStances()) do
                local at = text:find(stance, 1, true)
                if at then found[#found + 1] = {stance = stance, at = at} end
            end
            if #found > 0 then
                table.sort(found, function(a, b) return a.at < b.at end)
                local stances = {}
                for i, f in ipairs(found) do stances[i] = f.stance end
                return stances
            end
        end
    end
end

-- The stances a spell can be cast in, the one to switch to first, or nil for a spell that needs none. The
-- tooltip says which stances, so the list matches this client's rules; the class config's list fills in
-- when the tooltip names none, and its order picks the stance to switch to.
local function stancesOf(name, id)
    local c = classConfig()
    if not c.hasStances then return nil end
    local configured = c.stances[name]
    local allowed = id and tooltipStances(id)
    if not allowed then return configured end
    local target = allowed[1]
    for _, stance in ipairs(configured or {}) do
        if tContains(allowed, stance) then
            target = stance
            break
        end
    end
    local stances = {target}
    for _, stance in ipairs(allowed) do
        if stance ~= target then stances[#stances + 1] = stance end
    end
    return stances
end

local function castBody(macro)
    -- the spam option adds [nochanneling:<spell>] (or [nostealth]) to every cast clause, so a press while
    -- the spell is channelling (or stealth is on) can't restart (or cancel) it; the stopCast option stops
    -- the current cast first (but, with spam on, not this spell's own channel); the useItems slots are used
    -- next, in order; the petAttack option sends the pet at the current target before the
    -- cast; the stance option switches stance before the cast. With items or a stance, #showtooltip names
    -- the spell so the button doesn't show the item or the stance
    local spam = smb.isOptionOn(macro, "spam") and macro.spam or nil
    local stopCast = smb.isOptionOn(macro, "stopCast") and "/stopcasting" .. (spam and " [" .. spam .. "]" or "") .. "\n"
    local useLines = {}
    for i, slot in ipairs(smb.useItemSlots(macro)) do useLines[i] = "/use " .. slot .. "\n" end
    local use = table.concat(useLines)
    local stance = smb.isOptionOn(macro, "stance") and stanceLine(macro.stances) or ""
    local namesSpell = stance ~= "" or use ~= ""
    local header = "#showtooltip" .. (namesSpell and " " .. macro.name or "") .. "\n" .. (stopCast or "") .. use
        .. (smb.isOptionOn(macro, "petAttack") and "/petattack\n" or "") .. stance
    -- "/cast <conditional> name", or "/cast name" when there is no conditional
    local function cast(conditional)
        return "/cast " .. (conditional ~= "" and conditional .. " " or "") .. macro.name
    end
    if smb.isOptionOn(macro, "raidRank1") then
        local targets = {""}
        if macro.focus then
            targets = {"@focus," .. macro.target .. ",nodead", ""}
        elseif smb.isOptionOn(macro, "mouseover") then
            targets = {"@mouseover," .. macro.target .. ",nodead", ""}
        end
        return header .. raidRank1Cast(macro.name, targets, spam) .. (macro.focus and FOCUS_FOOTER or "")
    end
    if macro.focus then
        return header .. cast(cond(spam, "@focus," .. macro.target .. ",nodead") .. "[" .. (spam or "") .. "]")
            .. FOCUS_FOOTER
    end
    if smb.isOptionOn(macro, "pet") then
        -- [pet:X] matches the pet's creature family, so another demon being out still summons this one
        local family = macro.name:match("^Summon (.+)$") or macro.name
        return header .. "/cast " .. cond(spam, "pet:" .. family) .. " " .. macro.petAbility .. "; "
            .. (spam and cond(spam) .. " " or "") .. macro.name
    end
    if smb.isOptionOn(macro, "cursor") then
        return header .. cast(cond(spam, "@cursor"))
    end
    if smb.isOptionOn(macro, "mouseover") then
        return header .. cast(cond(spam, "@mouseover," .. macro.target .. ",nodead") .. "[" .. (spam or "") .. "]")
    end
    return header .. cast(cond(spam))
end

-- The startAttack option starts melee auto-attack as the macro's last line, after the cast.
local function macroBody(macro)
    return castBody(macro) .. (smb.isOptionOn(macro, "startAttack") and "\n/startattack" or "")
end

-- One macro per learned class spell (and unlearned one, when shown) plus the class config's custom macros,
-- in page order. Rebuilt each time the page opens.
smb.macros = {}

-- The condition a spell's spam option adds to its casts, or nil for spells without one. Stealth toggles
-- off when cast again, so a stealth spell casts only while not stealthed.
local function spamCondition(name)
    local c = classConfig()
    if c.isStealthSpell(name) then return "nostealth" end
    if c.isChanneledSpell(name) then return "nochanneling:" .. name end
end

local function makeMacro(name, icon, unlearned, id)
    local categoryRank, category, priority = categoryOf(name)
    local macro = {
        name = name,
        unlearned = unlearned,
        categoryRank = categoryRank,
        priority = priority,
        category = category,
        noGlow = categoryRank ~= UNLISTED and classConfig().categories[categoryRank].noGlow == true,
        target = targetOf(name),
        cursor = classConfig().isCursorSpell(name) ~= nil,
        petAbility = classConfig().petAbilities[name],
        raidRank1 = classConfig().isRaidRank1Spell(name) ~= nil,
        spam = spamCondition(name),
        stealth = classConfig().isStealthSpell(name) ~= nil,
        stances = stancesOf(name, id),
        -- the question mark icon lets #showtooltip show the spell's own icon on the action bar
        macroName = name:sub(1, MAX_MACRO_NAME),
        macroIcon = ICON_QUESTION_MARK,
        icon = icon or ICON_QUESTION_MARK,
    }
    macro.body = macroBody(macro)
    return macro
end

-- A copy of a spell macro that casts on the focus target, falling back to the current target. Its menu
-- offers only the focus option, which removes it.
local function makeFocusMacro(macro)
    local copy = {}
    for key, value in pairs(macro) do copy[key] = value end
    copy.focus = true
    copy.cursor = false
    copy.petAbility = nil
    copy.macroName = macro.name:sub(1, MAX_MACRO_NAME - #FOCUS_SUFFIX) .. FOCUS_SUFFIX
    copy.body = macroBody(copy)
    return copy
end

local getSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture

-- The icon of the spell named by a leading "#showtooltip <spell>" line, or nil.
local function showtooltipIcon(body)
    local spell = body:match("^#showtooltip[ \t]+([^\n]*%S)")
    if spell and getSpellTexture then return getSpellTexture(spell) end
end

-- A config custom entry as a page macro. Its body is used as written, and it has no options menu.
local function makeCustomMacro(entry, index, categoryRank)
    return {
        name = entry.name,
        categoryRank = categoryRank,
        priority = index,
        category = entry.category or "Custom",
        custom = true,
        cursor = false,
        macroName = entry.name:sub(1, MAX_MACRO_NAME),
        macroIcon = entry.icon or ICON_QUESTION_MARK,
        icon = entry.icon or showtooltipIcon(entry.body) or ICON_QUESTION_MARK,
        body = entry.body,
    }
end

local warned = {}

-- Prints a config problem once per session.
local function warn(message)
    if warned[message] then return end
    warned[message] = true
    print(addonName .. ": " .. message)
end

-- Appends the valid custom entries to smb.macros. taken holds the macro names already in use.
local function addCustomMacros(taken)
    local c = classConfig()
    local categoryRanks = {}
    for i, entry in ipairs(c.custom) do
        local name, body = type(entry) == "table" and entry.name, type(entry) == "table" and entry.body
        if type(name) ~= "string" or name == "" or type(body) ~= "string" or body == "" then
            warn("custom macro #" .. i .. " in your class config needs a name and a body.")
        elseif #body > MAX_MACRO_BODY then
            warn("custom macro \"" .. name .. "\" is " .. #body .. " characters; macros allow " .. MAX_MACRO_BODY .. ".")
        elseif taken[name:sub(1, MAX_MACRO_NAME)] then
            warn("custom macro \"" .. name .. "\" has the same name (first " .. MAX_MACRO_NAME
                .. " characters) as another macro on the page.")
        else
            taken[name:sub(1, MAX_MACRO_NAME)] = true
            local category = entry.category or "Custom"
            -- a config category keeps its place; others follow them in order of first use
            categoryRanks[category] = categoryRanks[category] or c.categoryRankByName[category] or #c.categories + i
            smb.macros[#smb.macros + 1] = makeCustomMacro(entry, i, categoryRanks[category])
        end
    end
end

local getItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell

-- The names equipment macros show and take, by inventory slot.
local SLOT_LABELS = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs",
    [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1",
    [14] = "Trinket 2", [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard",
}

-- Whether the item in an equipment slot has a "Use:" effect. The tooltip check catches effects added to the
-- item, such as engineering tinkers, which GetItemSpell on the item itself may not see.
local function hasUseEffect(slot, link)
    if getItemSpell and getItemSpell(link) then return true end
    local prefix = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
    for _, text in ipairs(scanLines("GetInventoryItem", "SetInventoryItem", "player", slot)) do
        if type(text) == "string" and text:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- A macro that uses whatever is in an equipment slot, so it keeps working when the item is swapped. It has
-- no options menu.
local function makeEquipmentMacro(slot, link, categoryRank)
    local label = SLOT_LABELS[slot]
    return {
        name = link:match("%[(.-)%]") or label,
        equipment = true,
        slot = slot,
        slotLabel = label,
        categoryRank = categoryRank,
        priority = slot,
        category = "Equipment",
        cursor = false,
        macroName = ("Use " .. label):sub(1, MAX_MACRO_NAME),
        macroIcon = ICON_QUESTION_MARK,
        icon = GetInventoryItemTexture("player", slot) or ICON_QUESTION_MARK,
        body = "#showtooltip\n/use " .. slot,
    }
end

-- The equipped items with a "Use:" effect, in slot order, as {slot = 13, link = ...}.
function smb.usableSlots()
    local usable = {}
    for slot = 1, #SLOT_LABELS do
        local link = GetInventoryItemLink("player", slot)
        if link and hasUseEffect(slot, link) then
            usable[#usable + 1] = {slot = slot, link = link}
        end
    end
    return usable
end

-- The name a slot shows in menus: its label, plus the equipped item's name when there is one.
function smb.slotLabel(slot)
    local link = GetInventoryItemLink("player", slot)
    local item = link and link:match("%[(.-)%]")
    return SLOT_LABELS[slot] .. (item and ": " .. item or "")
end

-- Appends a macro for each equipped item with a "Use:" effect to smb.macros. taken holds the macro names
-- already in use. The section follows the custom macros unless the class config places an "Equipment"
-- category.
local function addEquipmentMacros(taken)
    local c = classConfig()
    local categoryRank = c.categoryRankByName.Equipment or #c.categories + #c.custom + 1
    for _, usable in ipairs(smb.usableSlots()) do
        local macro = makeEquipmentMacro(usable.slot, usable.link, categoryRank)
        if not taken[macro.macroName] then
            taken[macro.macroName] = true
            smb.macros[#smb.macros + 1] = macro
        end
    end
end

-- Calls fn(name, icon, id) for every learned, castable spell outside the General skill line, in skill line
-- order.
local function forEachClassSpell(fn)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum.SpellBookSpellBank.Player
        for line = 2, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info and not info.shouldHide and not info.offSpecID then
                for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                    if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive
                            and not item.isOffSpec then
                        fn(item.name, item.iconID, item.spellID or item.actionID)
                    end
                end
            end
        end
    else
        for line = 2, GetNumSpellTabs() do
            local _, _, offset, numSlots = GetSpellTabInfo(line)
            for slot = offset + 1, offset + numSlots do
                local itemType, id = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL)
                if itemType == "SPELL" and not IsPassiveSpell(slot, BOOKTYPE_SPELL) then
                    fn(GetSpellBookItemName(slot, BOOKTYPE_SPELL), GetSpellBookItemTexture(slot, BOOKTYPE_SPELL), id)
                end
            end
        end
    end
end

local isSpellPassive = C_Spell and C_Spell.IsSpellPassive or IsPassiveSpell

local requested = {} -- spell ids asked for once, so an id that never loads can't keep the page redrawing

-- A spell's name, or nil while its data isn't loaded (it is then requested).
local function spellName(id)
    local name = C_Spell.GetSpellName(id)
    if not name and not requested[id] then
        requested[id] = true
        C_Spell.RequestLoadSpellData(id)
    end
    return name
end

-- The rank in a spell's subtext ("Rank 2"), or nil for a spell without ranks.
local function rankOf(id)
    local subtext = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    return subtext and tonumber(subtext:match("%d+"))
end

-- Whether a spell isn't rank 1: its subtext says a higher rank, or it requires its own previous rank. Nil
-- while a required spell's name isn't loaded.
local function isHigherRank(spell, name)
    if (rankOf(spell.id) or 1) > 1 then return true end
    for _, id in ipairs(spell.requires or {}) do
        local required = spellName(id)
        if not required then return nil end
        if required == name then return true end
    end
    return false
end

-- Calls fn(name, icon, id) for the rank 1 of every class trainer spell whose name isn't in learned: the
-- bundled ones (Data/) by level, then the ones this character's trainers offered (Trainer.lua), then the
-- class config's extraSpells. Data/ includes the rank 1 of each talent that has trainer ranks, so those
-- talents show until learned; talents without trainer ranks need an extraSpells entry.
-- Spells whose data isn't loaded yet are skipped: SpellBookTab.lua refreshes on SPELL_DATA_LOAD_RESULT.
local function forEachUnlearnedSpell(fn, learned)
    local faction, race = UnitFactionGroup("player"), select(3, UnitRace("player"))
    local seen = {}
    local spells = {}
    for _, list in ipairs({smb.trainerSpells[select(2, UnitClass("player"))] or {}, smb.recordedTrainerSpells()}) do
        for _, spell in ipairs(list) do spells[#spells + 1] = spell end
    end
    for _, id in ipairs(classConfig().extraSpells) do spells[#spells + 1] = {id = id} end
    for _, spell in ipairs(spells) do
        if (not spell.faction or spell.faction == faction) and (not spell.race or spell.race == race) then
            local name = spellName(spell.id)
            if name and not seen[name] then
                local higherRank = isHigherRank(spell, name)
                if higherRank == false then
                    seen[name] = true -- the lowest level entry is rank 1
                    if not learned[name] and not isSpellPassive(spell.id) then
                        fn(name, C_Spell.GetSpellTexture(spell.id), spell.id)
                    end
                end
            end
        end
    end
end

-- Rebuilds smb.macros: the learned spells (from the spellbook), the class config's custom macros and the
-- equipped items with a "Use:" effect, plus the spells not learned yet when smb.showsUnlearned().
function smb.collectMacros()
    wipe(smb.macros)
    local taken, seen = {}, {}
    local function add(name, icon, unlearned, id)
        local macro = makeMacro(name, icon, unlearned, id)
        if unlearned and taken[macro.macroName] then return end -- a custom macro already uses the name
        taken[macro.macroName] = true
        smb.macros[#smb.macros + 1] = macro
        if smb.isOptionOn(macro, "focus") then
            local copy = makeFocusMacro(macro)
            taken[copy.macroName] = true
            smb.macros[#smb.macros + 1] = copy
        end
    end
    forEachClassSpell(function(name, icon, id)
        if name and not seen[name] then -- older books list each rank separately
            seen[name] = true
            add(name, icon, nil, id)
        end
    end)
    addCustomMacros(taken)
    addEquipmentMacros(taken)
    if smb.showsUnlearned() then
        forEachUnlearnedSpell(function(name, icon, id) add(name, icon, true, id) end, seen)
    end
    -- by section; within one, spells before custom macros, then config order, then by name, each focus
    -- copy right after its spell
    table.sort(smb.macros, function(a, b)
        if a.categoryRank ~= b.categoryRank then return a.categoryRank < b.categoryRank end
        if (not a.custom) ~= (not b.custom) then return not a.custom end
        if a.priority ~= b.priority then return a.priority < b.priority end
        if a.name ~= b.name then return a.name < b.name end
        return not a.focus and b.focus == true
    end)
end

-- Rewrites the WoW macro at index if its body differs from the page's. Index 0 means it does not exist.
local function syncMacro(macro, index)
    if index ~= 0 and select(3, GetMacroInfo(index)) ~= macro.body then
        EditMacro(index, nil, nil, macro.body)
    end
end

-- Creates the macro on first use (character specific, or general once those slots are full), then puts
-- it on the cursor so it can be dropped on an action bar. Equipment macros are always general: their body
-- names only the slot, so every character shares them.
function smb.pickupMacro(macro)
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
        return
    end
    local index = GetMacroIndexByName(macro.macroName)
    if index == 0 then
        local numAccount, numCharacter = GetNumMacros()
        local perCharacter = not macro.equipment and numCharacter < maxCharacterMacros()
        if not perCharacter and numAccount >= maxAccountMacros() then
            UIErrorsFrame:AddMessage(addonName .. ": no free " .. (macro.equipment and "general " or "")
                .. "macro slots.", 1, 0.1, 0.1)
            return
        end
        index = CreateMacro(macro.macroName, macro.macroIcon, macro.body, perCharacter)
    else
        syncMacro(macro, index)
    end
    PickupMacro(index)
end

-- Rewrites the existing WoW macros whose body no longer matches the page (a setting or config changed).
function smb.syncAllMacros()
    if InCombatLockdown() then return end
    for _, macro in ipairs(smb.macros) do
        syncMacro(macro, GetMacroIndexByName(macro.macroName))
    end
end

local MAX_ACTION_SLOTS = 180 -- Classic has 120; empty or missing slots return nil

-- What is on the action bars: {macros = {[macro name] = true}, spells = {[spell name] = true}}. For a
-- macro that shows a spell, GetActionInfo gives the spell's id (subtype "spell") rather than the macro's
-- index, so macros are matched by the name GetActionText gives.
function smb.scanActionBars()
    local bars = {macros = {}, spells = {}}
    for slot = 1, MAX_ACTION_SLOTS do
        local actionType, id, subType = GetActionInfo(slot)
        if actionType == "macro" then
            local name = GetActionText(slot) or (subType ~= "spell" and GetMacroInfo(id))
            if name then bars.macros[name] = true end
        elseif actionType == "spell" and id then
            local name = C_Spell.GetSpellName(id)
            if name then bars.spells[name] = true end
        end
    end
    return bars
end

-- Whether a page macro is on the action bars, scanned by smb.scanActionBars. A spell macro with no
-- options on also counts when its plain spell is on a bar, and with smb.countsSpellsOnBars() any spell
-- macro does.
function smb.isOnActionBars(macro, bars)
    if bars.macros[macro.macroName] then return true end
    if macro.custom or macro.equipment or macro.focus or not bars.spells[macro.name] then return false end
    return smb.countsSpellsOnBars() or macro.body == bareBody(macro.name)
end

-- Flips a setting ("mouseover", "cursor", "focus", "pet", "raidRank1", "spam", "stance", "petAttack",
-- "stopCast" or "startAttack") and rewrites the macro if it already exists. In combat the rewrite waits until
-- the next pickup. The focus setting adds or removes a page entry and raidRank1, spam, stance, petAttack,
-- stopCast and startAttack also change the focus copy, so the page must be rebuilt after any of them.
function smb.toggleOption(macro, key)
    if DEFAULTED[key] then
        -- stored only where it differs from the default, so the rest follow a change of default
        local on = not smb.isOptionOn(macro, key)
        if on == optionDefault(key) then
            settings(key)[macro.name] = nil
        else
            settings(key)[macro.name] = on
        end
    else
        toggleSetting(key, macro.name)
    end
    macro.body = macroBody(macro)
    if InCombatLockdown() then return end
    syncMacro(macro, GetMacroIndexByName(macro.macroName))
end

-- Adds an equipment slot to the end of the macro's useItems list, or removes it, then rewrites the macro
-- like smb.toggleOption. The focus copy changes too, so the page must be rebuilt after.
function smb.toggleUseSlot(macro, slot)
    local slots = {}
    local at = smb.isUsingSlot(macro, slot)
    for i, used in ipairs(smb.useItemSlots(macro)) do
        if i ~= at then slots[#slots + 1] = used end
    end
    if not at then slots[#slots + 1] = slot end
    settings("useItems")[macro.name] = #slots > 0 and slots or nil
    macro.body = macroBody(macro)
    if InCombatLockdown() then return end
    syncMacro(macro, GetMacroIndexByName(macro.macroName))
end

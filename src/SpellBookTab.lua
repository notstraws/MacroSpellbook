local addonName, smb = ...

-- Adds a "Macro Spellbook" tab to the spellbook. LibSpellBookTabs owns the tab, its placement and
-- the parchment page; this file only draws smb.macros (built by Macros.lua) onto the page.

local ICON_MACRO = "Interface\\MacroFrame\\MacroFrame-Icon" -- the "M" key shown on Blizzard's macro window

local function hideTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local setMacro, refresh

-- Every spell macro has a menu; custom macros don't. A focus copy's menu only removes it.
local function showMacroMenu(button)
    local macro = button.macro
    if not smb.hasOptions(macro) then return end
    MenuUtil.CreateContextMenu(button, function(_, rootDescription)
        rootDescription:CreateTitle(macro.name)
        local function addOption(label, key)
            rootDescription:CreateCheckbox(label,
                function() return smb.isOptionOn(macro, key) end,
                function()
                    smb.toggleOption(macro, key)
                    if key == "focus" or key == "petAttack" or key == "raidRank1" or key == "spam"
                            or key == "stance" or key == "stopCast" or key == "startAttack" then
                        refresh(button:GetParent()) -- adds, removes or rewrites the focus copy
                    elseif button.macro == macro then
                        setMacro(button, macro)
                    end
                end)
        end
        if macro.focus then
            addOption("Cast On Focus", "focus")
            return
        end
        if macro.target then addOption("Cast on mouseover", "mouseover") end
        if macro.cursor then addOption("Cast at cursor", "cursor") end
        if macro.petAbility then addOption("Cast " .. macro.petAbility .. " if summoned", "pet") end
        if macro.raidRank1 then addOption("Downrank in raids", "raidRank1") end
        if macro.spam then addOption("Spammable", "spam") end
        if macro.stances then addOption("Switch to " .. macro.stances[1], "stance") end
        if macro.target then addOption("Cast On Focus", "focus") end
        if smb.offersPetAttack(macro) then addOption("Enable Pet Attack", "petAttack") end
        if smb.offersStartAttack(macro) then
            addOption("Start Attack After Casting", "startAttack")
        elseif smb.offersStopCast(macro) then
            addOption("Stop Casting Before Casting", "stopCast")
        end
        if smb.offersUseItems(macro) then
            -- the equipped on-use items, plus any slot already ticked so it can be unticked after a gear swap
            local slots, listed = {}, {}
            for _, usable in ipairs(smb.usableSlots()) do
                slots[#slots + 1], listed[usable.slot] = usable.slot, true
            end
            for _, slot in ipairs(smb.useItemSlots(macro)) do
                if not listed[slot] then slots[#slots + 1] = slot end
            end
            if #slots > 0 then
                local submenu = rootDescription:CreateButton("Use Before Casting")
                for _, slot in ipairs(slots) do
                    local at = smb.isUsingSlot(macro, slot)
                    submenu:CreateCheckbox(smb.slotLabel(slot) .. (at and " (" .. at .. ")" or ""),
                        function() return smb.isUsingSlot(macro, slot) ~= nil end,
                        function()
                            smb.toggleUseSlot(macro, slot)
                            refresh(button:GetParent()) -- rewrites the focus copy too
                        end)
                end
            end
        end
    end)
end

-- Native spellbook geometry (Camelot's Blizzard_SpellBookTemplates.xml): each page's spell view is 680
-- wide, 95 below the book's top, 85 from its left (left page) or 50 from its right (right page). Our page
-- frame starts 60 below the book's top.
local VIEW_WIDTH, VIEW_TOP, VIEW_LEFT, VIEW_RIGHT, VIEW_BOTTOM = 680, -35, 85, 50, 75
local COLUMNS, CELL_HEIGHT, CATEGORY_GAP = 3, 52, 12
local FOOTER_BOTTOM = 46 -- the footer's bottom edge, roughly level with the paging arrows (40 up)
local CELL_WIDTH = VIEW_WIDTH / COLUMNS
local ICON_SIZE = 36

-- parchment ink, matching the native spell names and subtext
local INK_COLOR = {0.18, 0.106, 0.059}
local MOUSEOVER_COLOR = {0.10, 0.38, 0.05}

-- The native spell item's atlases and layout (Camelot's SpellBookItemTemplate, read in game). The item is
-- 217x60 with a 40x40 icon button at its left; our button is the item, so the native button's anchors
-- become offsets from the 36x36 icon, which sits 2 inside it. Each falls back to an old file texture,
-- sized from the icon, if this build lacks the atlas.
local ITEM_WIDTH = 217
local ATLAS_FRAME = "spellbook-item-iconframe"
local ATLAS_FRAME_INACTIVE = "spellbook-item-iconframe-inactive"
local ATLAS_FRAME_HOVER = "spellbook-item-iconframe-hover"
local ATLAS_GLOW = "spellbook-item-unassigned-glow"
local ATLAS_MASK = "spellbook-item-spellicon-mask"

local function hasAtlas(atlas)
    return C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- Stretches texture over the icon, grown by the given insets (left, top, right, bottom).
local function setAroundIcon(texture, icon, left, top, right, bottom)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", icon, "TOPLEFT", -left, top)
    texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", right, -bottom)
end

-- Returns true when the atlas was used.
local function setAtlasOr(texture, atlas, file, scale, icon)
    if hasAtlas(atlas) then
        texture:SetAtlas(atlas, false)
        return true
    end
    if file then
        texture:SetTexture(file)
        texture:SetSize(ICON_SIZE * scale, ICON_SIZE * scale)
        texture:SetPoint("CENTER", icon)
    end
    return false
end

-- Cells are reused across refreshes; setMacro points one at a macro.
local function createMacroButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ITEM_WIDTH, ICON_SIZE + 4)
    button.icon = button:CreateTexture(nil, "ARTWORK", nil, -1)
    button.icon:SetSize(ICON_SIZE, ICON_SIZE)
    button.icon:SetPoint("LEFT", 2, 0)
    if hasAtlas(ATLAS_MASK) then
        local mask = button:CreateMaskTexture()
        mask:SetAtlas(ATLAS_MASK, false)
        mask:SetAllPoints(button.icon)
        button.icon:AddMaskTexture(mask)
    end
    -- the frame's curl hangs off the icon's bottom left
    button.border = button:CreateTexture(nil, "OVERLAY", nil, 1)
    if setAtlasOr(button.border, ATLAS_FRAME, "Interface\\Buttons\\UI-Quickslot2", 1.6, button.icon) then
        setAroundIcon(button.border, button.icon, 13, 3, 3, 9)
    end
    -- glow on a macro that isn't on the action bars yet, like the native page's unassigned spells
    button.glow = button:CreateTexture(nil, "OVERLAY", nil, 5)
    if setAtlasOr(button.glow, ATLAS_GLOW, "Interface\\Buttons\\UI-ActionButton-Border", 1.8, button.icon) then
        setAroundIcon(button.glow, button.icon, 6, 5, 5, 5)
    else
        button.glow:SetBlendMode("ADD")
        button.glow:SetVertexColor(1, 0.82, 0) -- the texture is white; Blizzard tints it per use
    end
    button.glow:Hide()
    -- fades in and out like the spellbook's glow on new spells; updateGlow starts it
    button.pulse = button.glow:CreateAnimationGroup()
    button.pulse:SetLooping("BOUNCE")
    local fade = button.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.5)
    fade:SetSmoothing("IN_OUT")
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    if hasAtlas(ATLAS_FRAME_HOVER) then
        highlight:SetAtlas(ATLAS_FRAME_HOVER, false)
    else
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        highlight:SetBlendMode("ADD")
    end
    setAroundIcon(highlight, button.icon, 2, 2, 2, 2)

    local text = CreateFrame("Frame", nil, button)
    text:SetHeight(29.5)
    text:SetPoint("LEFT", 50, -1)
    text:SetPoint("RIGHT", 0, -1)
    button.name = text:CreateFontString(nil, "ARTWORK", "SystemFont_Large")
    button.name:SetPoint("TOPLEFT")
    button.name:SetPoint("TOPRIGHT")
    button.name:SetJustifyH("LEFT")
    button.name:SetWordWrap(false)
    button.name:SetTextColor(unpack(INK_COLOR))
    button.subText = text:CreateFontString(nil, "ARTWORK", "SystemFont_Med1")
    button.subText:SetPoint("TOPLEFT", button.name, "BOTTOMLEFT", 0, -2)
    button.subText:SetPoint("TOPRIGHT", button.name, "BOTTOMRIGHT", 0, -2)
    button.subText:SetJustifyH("LEFT")
    button.subText:SetWordWrap(false)

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self) smb.pickupMacro(self.macro) end)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            showMacroMenu(self)
        else
            smb.pickupMacro(self.macro)
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- an equipment macro shows its item, with the item's Use: line
        if not (self.macro.equipment and GameTooltip:SetInventoryItem("player", self.macro.slot)) then
            GameTooltip:SetText(self.macro.name)
            GameTooltip:AddLine(self.macro.body, 1, 1, 1, true)
        end
        if self.macro.unlearned then
            GameTooltip:AddLine("Not learned yet.", 1, 0.1, 0.1, true)
        elseif self.glow:IsShown() then
            GameTooltip:AddLine("Not on your action bars.", 0.5, 0.5, 0.5, true)
        end
        GameTooltip:AddLine("Click or drag to place on an action bar.", 0.5, 0.5, 0.5, true)
        if smb.hasOptions(self.macro) then
            GameTooltip:AddLine("Right-click for options.", 0.5, 0.5, 0.5, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", hideTooltip)
    button:SetScript("OnHide", hideTooltip)
    return button
end

-- Shows the glow when the button's macro is learned but not on the bars (from smb.scanActionBars).
-- Custom macros and those in a noGlow category never glow.
local function updateGlow(button, bars)
    local macro = button.macro
    local shown = not macro.custom and not macro.noGlow and not macro.unlearned
        and not smb.isOnActionBars(macro, bars)
    button.glow:SetShown(shown)
    if not shown then
        button.pulse:Stop()
    elseif not button.pulse:IsPlaying() then
        button.pulse:Play()
    end
end

-- bars is a smb.scanActionBars() result, scanned here when nil.
function setMacro(button, macro, bars)
    button.macro = macro
    updateGlow(button, bars or smb.scanActionBars())
    button.icon:SetTexture(macro.icon)
    button.icon:SetDesaturated(macro.unlearned == true)
    local frameAtlas = macro.unlearned and ATLAS_FRAME_INACTIVE or ATLAS_FRAME
    if hasAtlas(frameAtlas) then button.border:SetAtlas(frameAtlas, false) end
    button.name:SetText(macro.name)
    if macro.custom then
        button.subText:SetText("Custom")
        button.subText:SetTextColor(unpack(INK_COLOR))
    elseif macro.equipment then
        button.subText:SetText(macro.slotLabel)
        button.subText:SetTextColor(unpack(INK_COLOR))
    elseif macro.focus then
        button.subText:SetText("Focus")
        button.subText:SetTextColor(unpack(MOUSEOVER_COLOR))
    elseif smb.isOptionOn(macro, "pet") then
        button.subText:SetText("Pet")
        button.subText:SetTextColor(unpack(MOUSEOVER_COLOR))
    elseif smb.isOptionOn(macro, "cursor") then
        button.subText:SetText("Cursor")
        button.subText:SetTextColor(unpack(MOUSEOVER_COLOR))
    elseif smb.isOptionOn(macro, "mouseover") then
        button.subText:SetText("Mouseover")
        button.subText:SetTextColor(unpack(MOUSEOVER_COLOR))
    elseif smb.isOptionOn(macro, "stance") then
        button.subText:SetText("Stance")
        button.subText:SetTextColor(unpack(MOUSEOVER_COLOR))
    elseif smb.useItemSlots(macro)[1] then
        button.subText:SetText("Use items")
        button.subText:SetTextColor(unpack(MOUSEOVER_COLOR))
    elseif smb.isOptionOn(macro, "petAttack") then
        button.subText:SetText("Pet attack")
        button.subText:SetTextColor(unpack(MOUSEOVER_COLOR))
    elseif smb.isOptionOn(macro, "raidRank1") then
        button.subText:SetText("Raid R1")
        button.subText:SetTextColor(unpack(MOUSEOVER_COLOR))
    elseif smb.isOptionOn(macro, "spam") then
        button.subText:SetText("Spammable")
        button.subText:SetTextColor(unpack(MOUSEOVER_COLOR))
    else
        button.subText:SetText(smb.hasCastOptions(macro) and "Macro" or "Self")
        button.subText:SetTextColor(unpack(INK_COLOR))
    end
end

-- The same category bar the native page draws over each skill line.
local function createHeader(parent)
    local header = CreateFrame("Frame", nil, parent, "SpellBookHeaderTemplate")
    header:SetWidth(VIEW_WIDTH)
    return header
end

local function setHeader(header, text)
    header.Text:SetText(text)
    header.Backplate:SetWidth(math.min(VIEW_WIDTH + 85, math.max(416, header.Text:GetStringWidth() * 2.5)))
end

-- Acquire hands out pooled frames in order; ReleaseAll hides the ones from the last layout.
local function framePool(create)
    local pool = {used = 0}
    function pool:Acquire()
        self.used = self.used + 1
        local frame = self[self.used] or create()
        self[self.used] = frame
        frame:ClearAllPoints()
        frame:Show()
        return frame
    end
    function pool:ReleaseAll()
        for i = 1, #self do self[i]:Hide() end
        self.used = 0
    end
    return pool
end

-- Splits the macros into page halves of {header = text, y} and {macro, column, y} entries. A category
-- flows top to bottom and repeats its header when it carries over to the next half.
local function paginate(height, headerHeight)
    local halves, half, y = {}, nil, 0
    local function newHalf()
        half, y = {}, 0
        halves[#halves + 1] = half
    end
    local function addHeader(text)
        half[#half + 1] = {header = text, y = y}
        y = y + headerHeight
    end
    newHalf()
    local category, column
    for _, macro in ipairs(smb.macros) do
        if macro.category ~= category then
            category, column = macro.category, 0
            if y > 0 then
                y = y + CELL_HEIGHT + CATEGORY_GAP -- close the previous category's last row
                if y + headerHeight + CELL_HEIGHT > height then newHalf() end
            end
            addHeader(category)
        elseif column == COLUMNS then
            column = 0
            y = y + CELL_HEIGHT
            if y + CELL_HEIGHT > height then
                newHalf()
                addHeader(category)
            end
        end
        half[#half + 1] = {macro = macro, column = column, y = y}
        column = column + 1
    end
    return halves
end

-- Draws the current spread: two pages side by side, or one when the book is minimized.
local function layout(page)
    page.headers:ReleaseAll()
    page.buttons:ReleaseAll()
    local controls = page.pagingControls
    local width, height = page:GetWidth(), page:GetHeight()
    local spread = width >= 2 * VIEW_WIDTH and 2 or 1
    -- a minimized book shows one page, centred; an open one uses the native left and right pages
    local origins = spread == 2 and {VIEW_LEFT, width - VIEW_RIGHT - VIEW_WIDTH} or {(width - VIEW_WIDTH) / 2}
    page.footer:ClearAllPoints()
    page.footer:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", origins[1] + 8, FOOTER_BOTTOM)
    if #smb.macros == 0 then
        local header = page.headers:Acquire()
        header:SetPoint("TOPLEFT", page, "TOPLEFT", origins[1], VIEW_TOP)
        setHeader(header, "Macro Spellbook")
        page.empty:SetText("No macros found.")
        page.empty:ClearAllPoints()
        page.empty:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -12)
        page.empty:Show()
        controls:Hide()
        return
    end
    page.empty:Hide()

    local headerHeight = math.max(page.headers:Acquire():GetHeight(), 30) + 8
    page.headers:ReleaseAll()

    local halves = paginate(height + VIEW_TOP - VIEW_BOTTOM, headerHeight)
    local maxPages = math.ceil(#halves / spread)
    page.paging = true
    controls:SetMaxPages(maxPages)
    page.paging = false
    controls:SetShown(maxPages > 1)
    local current = math.min(controls:GetCurrentPage(), maxPages)
    local bars = smb.scanActionBars()
    for side = 1, spread do
        local x = origins[side]
        for _, entry in ipairs(halves[(current - 1) * spread + side] or {}) do
            if entry.header then
                local header = page.headers:Acquire()
                header:SetPoint("TOPLEFT", page, "TOPLEFT", x, VIEW_TOP - entry.y)
                setHeader(header, entry.header)
            else
                local button = page.buttons:Acquire()
                button:SetPoint("TOPLEFT", page, "TOPLEFT", x + entry.column * CELL_WIDTH + 8, VIEW_TOP - entry.y - 4)
                setMacro(button, entry.macro, bars)
            end
        end
    end
end

-- Rebuilds the list from the spellbook and the class config, updates changed macros, then redraws.
function refresh(page)
    smb.collectMacros()
    smb.syncAllMacros()
    layout(page)
end

local function buildPage(page)
    page.headers = framePool(function() return createHeader(page) end)
    page.buttons = framePool(function() return createMacroButton(page) end)

    page.empty = page:CreateFontString(nil, "OVERLAY", "SystemFont_Med3")
    page.empty:SetTextColor(unpack(INK_COLOR))

    -- usage hint along the bottom of the left page, level with the paging arrows; layout places it
    page.footer = page:CreateFontString(nil, "OVERLAY", "SystemFont_Med1")
    page.footer:SetTextColor(unpack(INK_COLOR))
    page.footer:SetJustifyH("LEFT")
    page.footer:SetText("Right click macro to edit; Change global settings via dropdown next to the search;")

    -- the native settings cog, laid over the native one in the toolbar; its menu
    -- holds the page-wide settings
    local options = CreateFrame("DropdownButton", nil, page.header, "SpellBookSettingsDropdownTemplate")
    page.options = options
    options:ClearAllPoints()
    options:SetPoint("TOPRIGHT", page.header, "TOPRIGHT", -30, -27)
    options:SetupMenu(function(_, rootDescription)
        rootDescription:CreateTitle("Settings")
        rootDescription:CreateCheckbox("Show unlearned spells", smb.showsUnlearned, function()
            smb.setShowUnlearned(not smb.showsUnlearned())
            if page.pagingControls.SetCurrentPage then
                page.paging = true
                page.pagingControls:SetCurrentPage(1)
                page.paging = false
            end
            refresh(page)
        end)
        rootDescription:CreateCheckbox("Count spells on bars as placed", smb.countsSpellsOnBars, function()
            smb.setCountSpellsOnBars(not smb.countsSpellsOnBars())
            layout(page)
        end)
        if smb.classOffersPetAttack() then
            rootDescription:CreateCheckbox("Enable Pet attacks before spell cast", smb.petAttacksByDefault, function()
                smb.setPetAttacksByDefault(not smb.petAttacksByDefault())
                refresh(page) -- rewrites the macros that follow the default
            end)
        end
        if smb.classOffersStartAttack() then
            rootDescription:CreateCheckbox("Start attack after spell cast", smb.startsAttackByDefault, function()
                smb.setStartsAttackByDefault(not smb.startsAttackByDefault())
                refresh(page) -- rewrites the macros that follow the default
            end)
        else
            rootDescription:CreateCheckbox("Stop casting before spell cast", smb.stopsCastingByDefault, function()
                smb.setStopsCastingByDefault(not smb.stopsCastingByDefault())
                refresh(page) -- rewrites the macros that follow the default
            end)
        end
    end)

    -- the native page's "Page 1/2" arrows, bottom right of the book
    local controls = CreateFrame("Frame", nil, page, "PagingControlsHorizontalTemplate")
    page.pagingControls = controls
    controls:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -75, 40)
    controls.PageText:SetFontObject("SystemFont_Med3")
    controls.PageText:SetTextColor(unpack(INK_COLOR))
    controls.spacing = 8
    controls.prevPageSound, controls.nextPageSound = SOUNDKIT.IG_ABILITY_PAGE_TURN, SOUNDKIT.IG_ABILITY_PAGE_TURN
    function page:OnPageChanged()
        if not self.paging then layout(self) end
    end
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta)
        if controls:IsShown() then controls:OnMouseWheel(delta) end
    end)

    page:SetScript("OnSizeChanged", function(self) if self:IsVisible() then layout(self) end end)
    page:RegisterEvent("SPELLS_CHANGED")
    page:RegisterEvent("PLAYER_EQUIPMENT_CHANGED") -- the Equipment section follows the gear worn
    -- unlearned spells whose names weren't loaded were skipped; redraw once a burst of them arrives
    page:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    -- placing or removing an action only changes the glows; redraw them once per burst
    page:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    page:RegisterEvent("UPDATE_MACROS")
    page:SetScript("OnEvent", function(self, event)
        if not self:IsVisible() then return end
        if event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_MACROS" then
            if self.glowsPending then return end
            self.glowsPending = true
            C_Timer.After(0, function()
                self.glowsPending = false
                if not self:IsVisible() then return end
                local bars = smb.scanActionBars()
                for i = 1, self.buttons.used do updateGlow(self.buttons[i], bars) end
            end)
        elseif event ~= "SPELL_DATA_LOAD_RESULT" then
            refresh(self)
        elseif smb.showsUnlearned() and not self.refreshPending then
            self.refreshPending = true
            C_Timer.After(0, function()
                self.refreshPending = false
                if self:IsVisible() then refresh(self) end
            end)
        end
    end)
end

LibStub("LibSpellBookTabs-1.0"):RegisterTab(addonName, {
    name = "Macro Spellbook",
    icon = ICON_MACRO,
    onCreate = buildPage,
    onShow = refresh,
})


local ADDON, SF = ...
local C = SF.Components
local T = SF.Theme

local BRAND = CreateColorFromHexString("FF61BEFF")

SF.Setup(ADDON)
T.accent = BRAND
T.accentDim = CreateColor(BRAND.r * 0.6, BRAND.g * 0.6, BRAND.b * 0.6, 1)
T.accentFade = CreateColor(BRAND.r, BRAND.g, BRAND.b, 0.2)

local FONT_SIZE = 14
local TITLE_FONT_SIZE = 16
T.font.size.normal = FONT_SIZE

local ROW_HEIGHT = 24
local FRAME_WIDTH = 780
local FRAME_HEIGHT = 460
local TOOLBAR_HEIGHT = 44
local LIST_HEADER_HEIGHT = 26
local STRIPE_ALPHA = 0.03
local BUTTON_HEIGHT = 24
local DROPDOWN_WIDTH = 152
local CHAR_DROPDOWN_WIDTH = 180
local ICON = "Interface\\Icons\\ability_mage_brainfreeze"
local DIFFICULTIES = {Normal = true, Heroic = true, Mythic = true}

local COLS = {
    {key = "item", x = 2, w = 280, label = "Item won"},
    {key = "spec", x = 286, w = 110, label = "Spec"},
    {key = "source", x = 400, w = 160, label = "Source"},
    {key = "context", x = 564, w = 130, label = "Difficulty"},
    {key = "date", x = 698, w = 50, label = "Date", justify = "RIGHT"},
}

local rows = {}
local db
local viewKey

local function Print(msg)
    print("|cff61beffBrain Freeze:|r " .. msg)
end

local function Color(c)
    return c.r, c.g, c.b, 1
end

local function CharKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

local function CurrentSeason()
    if C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID then
        local season = C_SeasonInfo.GetCurrentDisplaySeasonID()
        if season and season > 0 then
            return season
        end
    end
    if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
        local season = C_MythicPlus.GetCurrentSeason()
        if season and season > 0 then
            return season
        end
    end
    return 0
end

local contextNames
local function ContextName(ctx)
    if not contextNames then
        contextNames = {}
        if Enum and Enum.ItemCreationContext then
            for name, value in pairs(Enum.ItemCreationContext) do
                contextNames[value] = name:gsub("(%l)(%u)", "%1 %2")
            end
        end
    end
    return contextNames[ctx] or ("Context " .. tostring(ctx))
end

local function ContextText(roll)
    local name = ContextName(roll.context)
    if name:find("^Challenge Mode") then
        return (roll.keyLevel or 0) > 0 and ("Mythic+ (" .. roll.keyLevel .. ")") or "Mythic+"
    end
    local kind, difficulty = name:match("^(%a+) (%a+)$")
    if kind and DIFFICULTIES[difficulty] then
        return kind .. " (" .. difficulty .. ")"
    end
    return name
end

local function SpecInfo(specID)
    if specID and specID > 0 then
        local _, name, _, icon = GetSpecializationInfoByID(specID)
        if name then
            return name, icon
        end
    end
    return "Spec " .. tostring(specID), 134400
end

-- currency:source:context:keyLevel:itemId:specId joined by /, prefix optional
local function ExtractImport(text)
    if not text then
        return nil
    end
    return text:match("bonus_roll_items=([%d:/]+)") or text:match("([%d:/]+)")
end

local function ParseImport(line)
    local list = {}
    for entry in (line or ""):gmatch("[^/]+") do
        local cur, src, ctx, key, item, spec = entry:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
        if cur then
            table.insert(list, {
                currency = tonumber(cur),
                source = tonumber(src),
                context = tonumber(ctx),
                keyLevel = tonumber(key),
                itemId = tonumber(item),
                spec = tonumber(spec),
            })
        end
    end
    return list
end

local function LiveRolls()
    local simc = _G.SimulationCraftDB
    local char = simc and simc.char and simc.char[viewKey]
    local rolls = char and char.bonusRolls
    if type(rolls) == "table" then
        return rolls
    end
end

local function GetUnfiltered()
    local live = LiveRolls()
    local list = {}
    if db.source == "live" then
        if live then
            local season = CurrentSeason()
            for _, roll in ipairs(live) do
                if type(roll) == "table" and roll.itemId and (db.allSeasons or roll.season == season) then
                    table.insert(list, roll)
                end
            end
        end
    else
        list = ParseImport(db.imports[viewKey])
    end
    return list, live ~= nil
end

local function Characters()
    local seen, list = {[CharKey()] = true}, {}
    local simc = _G.SimulationCraftDB
    for key, char in pairs(simc and simc.char or {}) do
        if type(char) == "table" and type(char.bonusRolls) == "table" and #char.bonusRolls > 0 then
            seen[key] = true
        end
    end
    for key in pairs(db.imports) do
        seen[key] = true
    end
    for key in pairs(seen) do
        table.insert(list, key)
    end
    local me = CharKey()
    table.sort(list, function(a, b)
        if (a == me) ~= (b == me) then
            return a == me
        end
        return a < b
    end)
    return list
end

local function CharClass(key)
    if key == CharKey() then
        return (select(2, UnitClass("player")))
    end
    local simc = _G.SimulationCraftDB
    local char = simc and simc.char and simc.char[key]
    local sources = {char and type(char.bonusRolls) == "table" and char.bonusRolls or {}, ParseImport(db.imports[key])}
    for _, rolls in ipairs(sources) do
        for _, roll in ipairs(rolls) do
            if type(roll) == "table" and (roll.spec or 0) > 0 then
                local classFile = select(6, GetSpecializationInfoByID(roll.spec))
                if classFile then
                    return classFile
                end
            end
        end
    end
end

local function GetRolls()
    local all, hasLive = GetUnfiltered()
    local list = {}
    for _, roll in ipairs(all) do
        if db.spec == 0 or roll.spec == db.spec then
            table.insert(list, roll)
        end
    end
    table.sort(list, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then
            return (a.ts or 0) > (b.ts or 0)
        end
        if a.spec ~= b.spec then
            return a.spec < b.spec
        end
        if a.source ~= b.source then
            return a.source < b.source
        end
        return a.itemId < b.itemId
    end)
    return list, all, hasLive
end

local frame = CreateFrame("Frame", "BrainFreezeFrame", UIParent, "BackdropTemplate")
frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
frame:SetFrameStrata("HIGH")
frame:SetToplevel(true)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
C.SetBackdrop(frame, T.bg.dark, T.border.color)
frame:Hide()
table.insert(UISpecialFrames, "BrainFreezeFrame")

local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
header:SetHeight(T.headerHeight)
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
C.SetBackdrop(header, T.bg.med, T.border.color)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function() frame:StartMoving() end)
header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local point, _, relPoint, x, y = frame:GetPoint()
    db.pos = {point, relPoint, x, y}
end)

local headerLine = frame:CreateTexture(nil, "ARTWORK")
headerLine:SetHeight(1)
headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
headerLine:SetColorTexture(1, 1, 1, 0.12)

local titleIcon = header:CreateTexture(nil, "OVERLAY")
titleIcon:SetSize(20, 20)
titleIcon:SetPoint("LEFT", T.padding.med, 0)
titleIcon:SetTexture(ICON)
titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local title = header:CreateFontString(nil, "OVERLAY")
C.ApplyFont(title, TITLE_FONT_SIZE)
title:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
title:SetText("Brain Freeze")
title:SetTextColor(Color(BRAND))

local subtitle = header:CreateFontString(nil, "OVERLAY")
C.ApplyFont(subtitle, FONT_SIZE)
subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 0)
subtitle:SetText("Uhh, what did I roll again?")
subtitle:SetTextColor(Color(T.text.muted))

local closeButton = C:CreateCloseButton(header, function() frame:Hide() end)
closeButton:SetPoint("RIGHT", -6, 0)

local toolbar = CreateFrame("Frame", nil, frame)
toolbar:SetHeight(TOOLBAR_HEIGHT)
toolbar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", T.padding.small, -T.padding.small)
toolbar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -T.padding.small, -T.padding.small)

local Refresh

local charDropdown = C:CreateDropdown(toolbar, "Character", {}, nil, function(value)
    viewKey = value
    db.spec = 0
    Refresh()
end)
charDropdown:SetWidth(CHAR_DROPDOWN_WIDTH)
charDropdown:SetPoint("TOPLEFT")

local sourceDropdown = C:CreateDropdown(toolbar, "Data", {
    {text = "SimulationCraft", value = "live"},
    {text = "Pasted export", value = "import"},
}, "live", function(value)
    db.source = value
    db.spec = 0
    Refresh()
end)
sourceDropdown:SetWidth(DROPDOWN_WIDTH)
sourceDropdown:SetPoint("LEFT", charDropdown, "RIGHT", T.padding.med, 0)

local seasonDropdown = C:CreateDropdown(toolbar, "Season", {
    {text = "Current", value = false},
    {text = "All", value = true},
}, false, function(value)
    db.allSeasons = value
    db.spec = 0
    Refresh()
end)
seasonDropdown:SetWidth(DROPDOWN_WIDTH)
seasonDropdown:SetPoint("LEFT", sourceDropdown, "RIGHT", T.padding.med, 0)

local specDropdown = C:CreateDropdown(toolbar, "Spec", {{text = "All", value = 0}}, 0, function(value)
    db.spec = value
    Refresh()
end)
specDropdown:SetWidth(DROPDOWN_WIDTH)
specDropdown:SetPoint("LEFT", seasonDropdown, "RIGHT", T.padding.med, 0)

local importButton = C:CreateButton(toolbar, "Import", {
    width = 100,
    height = BUTTON_HEIGHT,
})
importButton:SetPoint("TOPRIGHT", 0, -14)

local listPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
listPanel:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -T.padding.med)
listPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.padding.small, T.padding.small)
C.SetBackdrop(listPanel, T.bg.light, T.border.color)

local listHeader = CreateFrame("Frame", nil, listPanel, "BackdropTemplate")
listHeader:SetHeight(LIST_HEADER_HEIGHT)
listHeader:SetPoint("TOPLEFT")
listHeader:SetPoint("TOPRIGHT")
C.SetBackdrop(listHeader, T.bg.med, T.border.color)

for _, col in ipairs(COLS) do
    local fs = listHeader:CreateFontString(nil, "OVERLAY")
    C.ApplyFont(fs, FONT_SIZE)
    fs:SetPoint("LEFT", col.x + 2, 0)
    fs:SetWidth(col.w)
    fs:SetJustifyH(col.justify or "LEFT")
    fs:SetText(col.label)
    fs:SetTextColor(Color(T.text.secondary))
end

local listLine = listPanel:CreateTexture(nil, "ARTWORK")
listLine:SetHeight(1)
listLine:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT")
listLine:SetPoint("TOPRIGHT", listHeader, "BOTTOMRIGHT")
listLine:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 0.25)

local listArea = CreateFrame("Frame", nil, listPanel)
listArea:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 1, -2)
listArea:SetPoint("BOTTOMRIGHT", -1, 1)

local scrollFrame = CreateFrame("ScrollFrame", nil, listArea)
scrollFrame:SetPoint("TOPLEFT")
scrollFrame:SetPoint("BOTTOMRIGHT", -(T.scrollbarWidth + 2), 0)
scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local maxScroll = self:GetVerticalScrollRange()
    self:SetVerticalScroll(delta > 0 and math.max(cur - ROW_HEIGHT * 2, 0) or math.min(cur + ROW_HEIGHT * 2, maxScroll))
end)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetHeight(1)
scrollFrame:SetScrollChild(content)
scrollFrame:SetScript("OnSizeChanged", function(_, width)
    content:SetWidth(width)
end)

C:ApplyScrollbar(scrollFrame, content, listArea)

local emptyText = listArea:CreateFontString(nil, "OVERLAY")
C.ApplyFont(emptyText, FONT_SIZE)
emptyText:SetPoint("CENTER")
emptyText:SetTextColor(Color(T.text.muted))

local importPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
importPanel:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -T.padding.small)
importPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.padding.small, T.padding.small)
importPanel:SetFrameLevel(frame:GetFrameLevel() + 20)
importPanel:EnableMouse(true)
C.SetBackdrop(importPanel, T.bg.dark, T.border.color)
importPanel:Hide()

local importLabel = importPanel:CreateFontString(nil, "OVERLAY")
C.ApplyFont(importLabel, FONT_SIZE)
importLabel:SetPoint("TOPLEFT", T.padding.small, -T.padding.small)
importLabel:SetText("Paste your /simc export, or just the bonus_roll_items line")
importLabel:SetTextColor(Color(T.text.secondary))

local importArea = C:CreateTextArea(importPanel, "")
importArea:SetPoint("TOPLEFT", importLabel, "BOTTOMLEFT", 0, -T.padding.small)
importArea:SetPoint("BOTTOMRIGHT", -T.padding.small, BUTTON_HEIGHT + T.padding.small * 2)

local saveButton = C:CreateButton(importPanel, "Save", {
    width = 100,
    height = BUTTON_HEIGHT,
})
saveButton:SetPoint("BOTTOMRIGHT", -T.padding.small, T.padding.small)

local cancelButton = C:CreateButton(importPanel, "Cancel", {
    width = 100,
    height = BUTTON_HEIGHT,
    callback = function() importPanel:Hide() end,
})
cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -T.padding.small, 0)

local function ShowImport()
    frame:Show()
    importArea:SetValue("")
    importPanel:Show()
    importArea:GetEditBox():SetFocus()
end

importButton:SetCallback(ShowImport)

saveButton:SetCallback(function()
    local line = ExtractImport(importArea:GetValue())
    local count = #ParseImport(line)
    if count == 0 then
        Print("no bonus_roll_items entries found in that text")
        return
    end
    db.imports[viewKey] = line
    db.source = "import"
    db.spec = 0
    importPanel:Hide()
    Print(string.format("imported %d rolls", count))
    Refresh()
end)

local function SetItemText(fs, icon, itemID, plain)
    if not itemID or itemID == 0 then
        fs.itemID = nil
        fs:SetText("Unknown")
        fs:SetTextColor(Color(T.text.muted))
        if icon then
            icon:SetTexture(134400)
        end
        return
    end
    fs.itemID = itemID
    fs:SetText(tostring(itemID))
    fs:SetTextColor(Color(T.text.muted))
    if icon then
        icon:SetTexture(C_Item.GetItemIconByID(itemID) or 134400)
    end
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        local name = item:GetItemName()
        if not name or fs.itemID ~= itemID then
            return
        end
        if plain then
            fs:SetText(name:match(":%s*(.+)$") or name)
            fs:SetTextColor(Color(T.text.primary))
            return
        end
        local r, g, b = C_Item.GetItemQualityColor(item:GetItemQuality() or 1)
        fs:SetText(name)
        fs:SetTextColor(r, g, b, 1)
    end)
end

local function ShowItemTooltip(owner, itemID)
    if not itemID or itemID == 0 then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
end

local function LinkItem(itemID)
    if not itemID or not IsModifiedClick("CHATLINK") then
        return
    end
    local _, link = C_Item.GetItemInfo(itemID)
    if link then
        ChatEdit_InsertLink(link)
    end
end

local function GetRow(index)
    if rows[index] then
        return rows[index]
    end

    local row = CreateFrame("Button", nil, content, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", content, "RIGHT")
    row:RegisterForClicks("LeftButtonUp")
    local stripe = index % 2 == 0 and STRIPE_ALPHA or 0
    C.SetBackdrop(row, CreateColor(1, 1, 1, stripe), CreateColor(0, 0, 0, 0))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", COLS[1].x, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.specIcon = row:CreateTexture(nil, "ARTWORK")
    row.specIcon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.specIcon:SetPoint("LEFT", COLS[2].x, 0)
    row.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.cells = {}
    for i, col in ipairs(COLS) do
        local fs = row:CreateFontString(nil, "OVERLAY")
        C.ApplyFont(fs, FONT_SIZE)
        local inset = i <= 2 and ROW_HEIGHT or 0
        fs:SetPoint("LEFT", col.x + inset, 0)
        fs:SetWidth(col.w - inset)
        fs:SetJustifyH(col.justify or "LEFT")
        fs:SetWordWrap(false)
        fs:SetTextColor(Color(T.text.primary))
        row.cells[col.key] = fs
    end

    local function Highlight(on)
        if on then
            row:SetBackdropColor(T.bg.hover.r, T.bg.hover.g, T.bg.hover.b, T.bg.hover.a)
        else
            row:SetBackdropColor(1, 1, 1, stripe)
        end
    end

    row:SetScript("OnClick", function(self)
        LinkItem(self.roll and self.roll.itemId)
    end)
    row:SetScript("OnEnter", function(self)
        Highlight(true)
        ShowItemTooltip(self, self.roll and self.roll.itemId)
    end)
    row:SetScript("OnLeave", function()
        Highlight(false)
        GameTooltip:Hide()
    end)

    local pool = CreateFrame("Button", nil, row)
    pool:SetPoint("LEFT", COLS[3].x, 0)
    pool:SetSize(COLS[3].w, ROW_HEIGHT)
    pool:RegisterForClicks("LeftButtonUp")
    pool:SetScript("OnClick", function()
        LinkItem(row.roll and row.roll.source)
    end)
    pool:SetScript("OnEnter", function(self)
        Highlight(true)
        ShowItemTooltip(self, row.roll and row.roll.source)
    end)
    pool:SetScript("OnLeave", function()
        Highlight(false)
        GameTooltip:Hide()
    end)

    rows[index] = row
    return row
end

local function UpdateSpecOptions(all)
    local seen, specs = {}, {}
    for _, roll in ipairs(all) do
        if not seen[roll.spec] then
            seen[roll.spec] = 0
            table.insert(specs, roll.spec)
        end
        seen[roll.spec] = seen[roll.spec] + 1
    end
    table.sort(specs)

    local options = {{text = string.format("All (%d)", #all), value = 0}}
    for _, specID in ipairs(specs) do
        table.insert(options, {text = string.format("%s (%d)", (SpecInfo(specID)), seen[specID]), value = specID})
    end
    if db.spec ~= 0 and not seen[db.spec] then
        db.spec = 0
    end
    specDropdown:SetOptions(options)
    specDropdown:SetValue(db.spec, true)
end

Refresh = function()
    if not frame:IsShown() then
        return
    end

    local chars = {}
    for _, key in ipairs(Characters()) do
        local color = RAID_CLASS_COLORS[CharClass(key) or ""]
        table.insert(chars, {text = color and color:WrapTextInColorCode(key) or key, value = key})
    end
    charDropdown:SetOptions(chars)
    charDropdown:SetValue(viewKey, true)

    local list, all, hasLive = GetRolls()
    UpdateSpecOptions(all)
    sourceDropdown:SetValue(db.source, true)
    seasonDropdown:SetValue(db.allSeasons, true)
    seasonDropdown:SetEnabled(db.source == "live")

    for i, roll in ipairs(list) do
        local row = GetRow(i)
        row.roll = roll
        SetItemText(row.cells.item, row.icon, roll.itemId)
        local specName, specIcon = SpecInfo(roll.spec)
        row.specIcon:SetTexture(specIcon)
        row.cells.spec:SetText(specName)
        SetItemText(row.cells.source, nil, roll.source, true)
        row.cells.context:SetText(ContextText(roll))
        row.cells.date:SetText(roll.ts and date("%m/%d", roll.ts) or "-")
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
    end
    content:SetHeight(math.max(1, #list * ROW_HEIGHT))

    if #list > 0 then
        emptyText:SetText("")
    elseif db.source == "live" and not hasLive then
        emptyText:SetText("No SimulationCraft data for this character, use Import to paste an export")
    elseif db.source == "import" then
        emptyText:SetText("Nothing imported for this character yet")
    else
        emptyText:SetText("No bonus rolls recorded")
    end
end

frame:SetScript("OnShow", function() Refresh() end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("BONUS_ROLL_RESULT")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        BrainFreezeDB = BrainFreezeDB or {}
        db = BrainFreezeDB
        db.imports = db.imports or {}
        db.source = db.source or "live"
        db.allSeasons = db.allSeasons or false
        db.spec = db.spec or 0
        viewKey = CharKey()
        if db.pos then
            frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
        else
            frame:SetPoint("CENTER")
        end
    elseif event == "BONUS_ROLL_RESULT" then
        C_Timer.After(0.5, Refresh)
    end
end)

SLASH_BRAINFREEZE1 = "/brainfreeze"
SLASH_BRAINFREEZE2 = "/bfreeze"
SLASH_BRAINFREEZE3 = "/bf"
SlashCmdList.BRAINFREEZE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "import" then
        ShowImport()
    elseif msg == "clear" then
        db.imports[viewKey] = nil
        db.source = "live"
        Print("cleared the pasted export for " .. viewKey)
        Refresh()
    else
        frame:SetShown(not frame:IsShown())
    end
end

-- EasyPoisons: plan a batch of rogue poisons and buy the missing
-- reagents at the vendor in one click. By Fostercare5988, based on Horyoshi's
-- original EasyPoisons. WoW 1.12.1 with ClassicAPI 1.16.0+
-- (ClassicAPIRequirement.lua).
local addonName, ns = ...
if ns.unsupported then return end
local UI = ns.UI

EasyPoisons = {}

local VIAL, LEADED_VIAL, DUST, ANGUISH, AGONY, PAIN, DEATHWEED = 8925, 3372, 8924, 2931, 8923, 2930, 5173
local FLASH_POWDER, FLASH_TARGET = 5140, 20    -- server database, item 5140

-- The starting rank of each poison: the highest a level 60 rogue knows on the
-- server. Item IDs and recipes as the Poisons window reported them in play
-- (2026-10-21/22; Deadly V and Corrosive II need content that is not open yet).
-- Opening the Poisons window saves the client's recipes in EasyPoisonsDB.Recipes,
-- which replace these, and the highest rank of each poison the character knows
-- (new ranks need no update).
local POISONS = {
    { itemID = 8928, name = "Instant Poison VI", reagents = { [DUST] = 4, [VIAL] = 1 } },
    { itemID = 54010, name = "Dissolvent Poison II", reagents = { [DUST] = 3, [ANGUISH] = 4, [VIAL] = 1 } },
    { itemID = 3776, name = "Crippling Poison II", reagents = { [AGONY] = 3, [VIAL] = 1 } },
    { itemID = 9186, name = "Mind-numbing Poison III", reagents = { [DUST] = 2, [AGONY] = 2, [VIAL] = 1 } },
    { itemID = 8985, name = "Deadly Poison IV", reagents = { [DEATHWEED] = 5, [VIAL] = 1 } },
    { itemID = 47408, name = "Corrosive Poison", reagents = { [DUST] = 3, [DEATHWEED] = 3, [VIAL] = 1 } },
    { itemID = 10918, name = "Wound Poison", reagents = { [PAIN] = 1, [DEATHWEED] = 1, [LEADED_VIAL] = 1 } },
    { itemID = 65032, name = "Agitating Poison", reagents = { [ANGUISH] = 2, [LEADED_VIAL] = 1 } },
}
local ROMAN = { I = 1, V = 5, X = 10 }

-- "Deadly Poison IV" -> "Deadly Poison", 4. A name without a numeral is rank 1.
local function SplitRank(name)
    local _, _, base, numeral = string.find(name, "^(.-) ([IVX]+)$")
    if not base then return name, 1 end
    local rank, largest = 0, 0
    for n = string.len(numeral), 1, -1 do
        local value = ROMAN[string.sub(numeral, n, n)]
        if value < largest then rank = rank - value else rank = rank + value; largest = value end
    end
    return base, rank
end

local poisonRow = {}       -- item ID of each row's current rank -> row
local familyRow = {}       -- "Deadly Poison" -> row
for i, poison in ipairs(POISONS) do familyRow[SplitRank(poison.name)] = i end
local ranks = {}           -- this character's EasyPoisonsDB.Ranks entry: starting item ID -> { itemID, name, rank }

local quantities = {}
local isReagent = {}
local offers = {}          -- reagent itemID -> what the open vendor sells; offer.slot is nil when not sold
local flashSlot = nil      -- the open vendor's Flash Powder, if it sells it
local needed, room, buys = {}, {}, {}
local buyCount = 0
local atVendor = false
local buying = false       -- an order is being bought, one purchase at a time
local pending = {}         -- the purchase in flight: pending.id, pending.want (bag count once it lands)
local purchaseToken = 0    -- ignores timeouts of purchases that already landed
local misses = 0           -- purchases in a row that never arrived
local BuyNext, StopBuying
local refreshQueued = false
local frame, rows = nil, {}

local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00EasyPoisons:|r |cFFFFFFFF" .. text .. "|r")
end

-- The rank a row stands for: the highest this character knows, else the table's.
local function Item(i)
    local known = ranks[POISONS[i].itemID]
    return known and known.itemID or POISONS[i].itemID
end

local function PoisonName(i)
    local known = ranks[POISONS[i].itemID]
    return known and known.name or POISONS[i].name
end

local function Recipe(i)
    local id = Item(i)
    return EasyPoisonsDB.Recipes[id] or (id == POISONS[i].itemID and POISONS[i].reagents) or nil
end

local function RebuildRows()
    table.wipe(poisonRow)
    for i = 1, #POISONS do poisonRow[Item(i)] = i end
end

local function RebuildReagents()
    table.wipe(isReagent)
    for i = 1, #POISONS do
        for id in pairs(Recipe(i) or {}) do isReagent[id] = true end
    end
end

local function ItemName(id)
    return C_Item.GetItemNameByID(id) or ("item " .. id)
end

function EasyPoisons:FormatMoney(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    copper = copper % 100

    local text = ""
    if gold > 0 then
        text = text .. "|cFFFFD700" .. gold .. "g|r "
    end
    if silver > 0 or gold > 0 then
        text = text .. "|cFFC0C0C0" .. silver .. "s|r "
    end
    return text .. "|cFFB87333" .. copper .. "c|r"
end

-- Vendor -----------------------------------------------------------------

-- Reads the open vendor's reagents by item ID. Returns true for a poison
-- vendor: one that sells every reagent of at least one poison. A trade goods
-- vendor with vials alone does not count.
local function ScanVendor()
    for _, offer in pairs(offers) do offer.slot = nil end
    flashSlot = nil
    for slot = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(slot)
        if id == FLASH_POWDER then flashSlot = slot end
        if id and isReagent[id] then
            local info = C_MerchantFrame.GetItemInfo(slot)
            if info then
                local offer = offers[id] or {}
                offers[id] = offer
                offer.slot, offer.price = slot, info.price
                offer.bundle, offer.stock = math.max(1, info.stackCount or 1), info.numAvailable or -1
            end
        end
    end
    for i = 1, #POISONS do
        local recipe, complete = Recipe(i), true
        for id in pairs(recipe or {}) do
            if not (offers[id] and offers[id].slot) then complete = false; break end
        end
        if recipe and complete then return true end
    end
    return false
end

-- Free room in the partial stacks of each needed reagent; purchases fill
-- those before taking an empty slot.
local function CountRoom()
    table.wipe(room)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and needed[id] then
                local _, count = GetContainerItemInfo(bag, slot)
                local cap = C_Item.GetItemMaxStackSizeByID(id) or 1
                if count and count < cap then room[id] = (room[id] or 0) + cap - count end
            end
        end
    end
end

-- Fills needed and buys for the current quantities. Returns the cost, the bag
-- slots the purchase needs and the first reagent problem, if any.
local function Plan()
    table.wipe(needed)
    local problem = nil
    for i = 1, #POISONS do
        local qty = quantities[i]
        if qty > 0 then
            local recipe = Recipe(i)
            if recipe then
                for id, amount in pairs(recipe) do needed[id] = (needed[id] or 0) + amount * qty end
            else
                problem = problem or ("Open your Poisons window once to learn " .. PoisonName(i) .. ".")
            end
        end
    end
    CountRoom()

    local cost, slots = 0, 0
    buyCount = 0
    for id, total in pairs(needed) do
        -- Reagents cannot be equipped, so the carried count is the bag count.
        local missing = total - C_Item.GetItemCount(id)
        if missing > 0 then
            local offer = offers[id]
            if not (offer and offer.slot) then
                problem = problem or ("This vendor does not sell " .. ItemName(id) .. ".")
            else
                local bundles = math.ceil(missing / offer.bundle)
                if offer.stock >= 0 and bundles > offer.stock then
                    problem = problem or ("The vendor has too few " .. ItemName(id) .. ".")
                end
                local items = bundles * offer.bundle
                local cap = C_Item.GetItemMaxStackSizeByID(id) or offer.bundle
                slots = slots + math.ceil(math.max(0, items - (room[id] or 0)) / cap)
                cost = cost + bundles * offer.price
                buyCount = buyCount + 1
                local buy = buys[buyCount] or {}
                buys[buyCount] = buy
                buy.id, buy.slot, buy.bundle, buy.bundles, buy.items = id, offer.slot, offer.bundle, bundles, items
            end
        end
    end
    return cost, slots, problem
end

-- Why the order cannot be bought now, or nil when it can.
local function Blocker(cost, slots, problem)
    if not atVendor then return "Open a poison vendor to buy." end
    if problem then return problem end
    if buyCount == 0 then
        for i = 1, #POISONS do
            if quantities[i] > 0 then return "You have all the reagents." end
        end
        return ""
    end
    if cost > GetMoney() then return "Not enough money." end
    if slots > C_Container.CalculateTotalNumberOfFreeBagSlots() then return "Not enough bag space." end
end

-- Window -----------------------------------------------------------------

local function SetText(font, text)
    if font.shown ~= text then
        font.shown = text
        font:SetText(text)
    end
end

local function SetBuyEnabled(enabled)
    if frame.buy.enabled ~= enabled then
        frame.buy.enabled = enabled
        UI.SetEnabled(frame.buy, enabled)
    end
end

local function Refresh()
    refreshQueued = false
    if not (frame and frame:IsShown()) then return end
    if buying then
        -- BuyNext plans only when a purchase has landed; the cost line keeps
        -- the order's total until it ends.
        BuyNext()
        if buying then
            SetText(frame.status, "Buying...")
            SetBuyEnabled(false)
            return
        end
    end
    local cost, slots, problem = Plan()
    local blocker = Blocker(cost, slots, problem)
    SetText(frame.cost, atVendor and ("Total cost: " .. EasyPoisons:FormatMoney(cost)) or "")
    SetText(frame.status, blocker or "")
    SetBuyEnabled(not blocker)
end

-- Bursts of bag and vendor events become one refresh on the next frame.
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, Refresh)
end

local function SetQuantity(index, value)
    value = math.max(0, math.min(999, value))
    local row = rows[index]
    if row.input:GetText() ~= tostring(value) then row.input:SetText(tostring(value)) end
    if quantities[index] ~= value then
        quantities[index] = value
        QueueRefresh()
    end
end

function EasyPoisons:ResetQuantities()
    for i = 1, #POISONS do
        quantities[i] = 0
        if rows[i] then rows[i].input:SetText("0") end
    end
    QueueRefresh()
end

local function CreateRow(index, y)
    local name = "EasyPoisons_Row" .. index
    local row = UI.Row(name, frame, 28, y, 284)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(18); icon:SetHeight(18)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetJustifyH("LEFT")
    label:SetText(PoisonName(index))
    UI.Color(label, "text")
    row.label = label

    local plus = UI.Button(name .. "Plus", row, "+", 0, 0, 22, function()
        SetQuantity(index, quantities[index] + 1)
    end, { height = 20 })
    plus:ClearAllPoints()
    plus:SetPoint("RIGHT", row, "RIGHT", -2, 0)

    local input = CreateFrame("EditBox", name .. "Count", row)
    input:SetWidth(36); input:SetHeight(20)
    input:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    input:SetAutoFocus(false)
    input:SetNumeric(true)
    input:SetMaxLetters(3)
    input:SetFontObject(GameFontHighlightSmall)
    input:SetJustifyH("CENTER")
    UI.Rounded(input, "BACKGROUND", 8, UI.track)
    input:SetText("0")
    input:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    input:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    input:SetScript("OnTextChanged", function() SetQuantity(index, tonumber(this:GetText()) or 0) end)
    row.input = input

    local minus = UI.Button(name .. "Minus", row, "-", 0, 0, 22, function()
        SetQuantity(index, quantities[index] - 1)
    end, { height = 20 })
    minus:ClearAllPoints()
    minus:SetPoint("RIGHT", input, "LEFT", -4, 0)

    rows[index] = row
end

local function ShowIcons()
    for i = 1, #POISONS do
        local row = rows[i]
        if not row.iconSet then
            local texture = C_Item.GetItemIconByID(Item(i))
            if texture then row.iconSet = true end
            row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end
end

local function CreateMainFrame()
    local version = GetAddOnMetadata(addonName, "Version") .. "  by " .. GetAddOnMetadata(addonName, "Author")
    frame = UI.Window("EasyPoisonsFrame", "Easy Poisons", 340, 168 + #POISONS * 30, version)

    for i = 1, #POISONS do CreateRow(i, -56 - (i - 1) * 30) end

    local y = -56 - #POISONS * 30 - 6
    frame.flash = UI.Switch("EasyPoisons_Flash", frame, "Keep " .. FLASH_TARGET .. " Flash Powder",
        "At any vendor that sells it, your bags are topped up to " .. FLASH_TARGET .. " automatically.",
        28, y, function(on)
            EasyPoisonsDB.KeepFlashPowder = on or nil
            if on then EasyPoisons:TopUpFlashPowder() end
        end)
    y = y - 28
    frame.cost = UI.Label(frame, "", 28, y, "GameFontHighlight")
    frame.status = UI.Label(frame, "", 28, y - 20, "GameFontNormalSmall")
    frame.status:SetTextColor(1, 0.35, 0.25)

    local reset = UI.Button("EasyPoisons_Reset", frame, "Reset", 0, 0, 136, function()
        EasyPoisons:ResetQuantities()
    end, { font = "GameFontHighlight" })
    reset:ClearAllPoints()
    reset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 28, 18)
    frame.buy = UI.Button("EasyPoisons_Buy", frame, "Buy", 0, 0, 136, function()
        EasyPoisons:BuyMaterials()
    end, { font = "GameFontHighlight" })
    frame.buy:ClearAllPoints()
    frame.buy:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 18)
    UI.Select(frame.buy, true)

    frame:SetScript("OnShow", function()
        frame:RegisterEvent("BAG_UPDATE")
        UI.SetCheck(frame.flash, EasyPoisonsDB.KeepFlashPowder and true or false)
        ShowIcons()
        QueueRefresh()
    end)
    -- Closing by any route (close glyph, Escape, leaving the vendor) clears the plan.
    frame:SetScript("OnHide", function()
        frame:UnregisterEvent("BAG_UPDATE")
        if buying then StopBuying() end
        for i = 1, #POISONS do rows[i].input:ClearFocus() end
        EasyPoisons:ResetQuantities()
    end)
    frame:SetScript("OnEvent", QueueRefresh)
end

local function ShowWindow(besideVendor)
    if not frame then CreateMainFrame() end
    if besideVendor and MerchantFrame then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", -28, -12)
    end
    if frame:IsShown() then QueueRefresh() else frame:Show() end
end

-- Buying -----------------------------------------------------------------

function StopBuying(text)
    buying = false
    pending.id = nil
    if text then Print(text) end
    QueueRefresh()
end

-- Buys the order one purchase at a time: each purchase waits until its items
-- are in the bags, then the plan is made again from what the bags hold. A
-- burst of purchases in one frame lost some of them in play (2026-10-21:
-- 3 of 4 vial purchases arrived), and re-planning tops up anything missing.
function BuyNext()
    if not buying then return end
    if pending.id then
        if C_Item.GetItemCount(pending.id) < pending.want then return end
        pending.id = nil
        misses = 0
    end
    local cost, slots, problem = Plan()
    if buyCount == 0 then return StopBuying("Purchase complete.") end
    local blocker = Blocker(cost, slots, problem)
    if blocker then return StopBuying(blocker) end

    local buy = buys[1]
    -- Like the stock vendor window, buy at most one full stack per purchase.
    local cap = buy.bundle > 1 and C_Item.GetItemMaxStackSizeByID(buy.id) or GetMerchantItemMaxStack(buy.slot)
    local count = math.min(buy.bundles, math.max(1, math.floor((cap or 1) / buy.bundle)))
    pending.id, pending.want = buy.id, C_Item.GetItemCount(buy.id) + count * buy.bundle
    purchaseToken = purchaseToken + 1
    local token = purchaseToken
    BuyMerchantItem(buy.slot, count)

    -- A purchase the server refuses never arrives: try again, then give up.
    C_Timer.After(2, function()
        if not (buying and purchaseToken == token) then return end
        if C_Item.GetItemCount(pending.id) >= pending.want then return BuyNext() end
        pending.id = nil
        misses = misses + 1
        if misses >= 3 then return StopBuying("The vendor did not sell " .. ItemName(buy.id) .. ". Press Buy to try again.") end
        BuyNext()
    end)
end

-- Tops Flash Powder up to FLASH_TARGET at any vendor that sells it. At most
-- one stack is missing, so this is a single purchase.
function EasyPoisons:TopUpFlashPowder()
    if not (EasyPoisonsDB.KeepFlashPowder and atVendor and flashSlot) then return end
    local have = C_Item.GetItemCount(FLASH_POWDER)
    local info = C_MerchantFrame.GetItemInfo(flashSlot)
    if have >= FLASH_TARGET or not info then return end
    local bundle = math.max(1, info.stackCount or 1)
    local cap = C_Item.GetItemMaxStackSizeByID(FLASH_POWDER) or GetMerchantItemMaxStack(flashSlot) or 1
    local bundles = math.min(math.ceil((FLASH_TARGET - have) / bundle), math.max(1, math.floor(cap / bundle)))
    if (info.numAvailable or -1) >= 0 then bundles = math.min(bundles, info.numAvailable) end
    if bundles < 1 then return end
    if bundles * info.price > GetMoney() then return Print("Not enough money for Flash Powder.") end
    local partialRoom = have % cap > 0 and cap - have % cap or 0
    if bundles * bundle > partialRoom and C_Container.CalculateTotalNumberOfFreeBagSlots() == 0 then
        return Print("No bag space for Flash Powder.")
    end
    BuyMerchantItem(flashSlot, bundles)
    Print("Buying " .. bundles * bundle .. " " .. ItemName(FLASH_POWDER) .. ".")
end

function EasyPoisons:BuyMaterials()
    if buying then return end
    local cost, slots, problem = Plan()
    if Blocker(cost, slots, problem) then
        QueueRefresh()
        return
    end

    local parts = {}
    for i = 1, buyCount do table.insert(parts, buys[i].items .. " " .. ItemName(buys[i].id)) end
    Print("Buying " .. table.concat(parts, ", ") .. ".")
    buying, misses = true, 0
    pending.id = nil
    BuyNext()
    QueueRefresh()
end

-- Recipes ----------------------------------------------------------------

-- Moves each row up to the highest rank of its poison the window lists. Rows
-- never move down: a search or filter in the window can hide higher ranks.
local function LearnRanks()
    local best = {}
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        local itemID = GetTradeSkillItemID(i)
        if name and itemID and kind ~= "header" then
            local base, rank = SplitRank(name)
            local row = familyRow[base]
            if row and not (best[row] and best[row].rank >= rank) then
                best[row] = { itemID = itemID, name = name, rank = rank }
            end
        end
    end
    local changed = false
    for row, found in pairs(best) do
        local start = POISONS[row].itemID
        local known = ranks[start]
        if (known and found.rank > known.rank) or (not known and found.itemID ~= start) then
            ranks[start] = found
            changed = true
        end
    end
    if not changed then return false end
    RebuildRows()
    for i = 1, #rows do
        rows[i].label:SetText(PoisonName(i))
        rows[i].iconSet = nil
    end
    if frame and frame:IsShown() then ShowIcons() end
    return true
end

-- Reads the poison recipes the Poisons window shows, by created item ID.
local function LearnRecipes()
    local changed = LearnRanks()
    for i = 1, GetNumTradeSkills() do
        local row = poisonRow[GetTradeSkillItemID(i) or 0]
        if row then
            -- Saved even when it matches the table, so every learned recipe
            -- is in EasyPoisonsDB.Recipes as evidence.
            local recipe, same = {}, true
            local known = EasyPoisonsDB.Recipes[Item(row)] or {}
            for r = 1, GetTradeSkillNumReagents(i) do
                local id = GetTradeSkillReagentItemID(i, r)
                local _, _, count = GetTradeSkillReagentInfo(i, r)
                if not (id and count) then recipe = nil; break end
                recipe[id] = count
                if known[id] ~= count then same = false end
            end
            if recipe and next(recipe) then
                for id in pairs(known) do
                    if not recipe[id] then same = false end
                end
                if not same then
                    EasyPoisonsDB.Recipes[Item(row)] = recipe
                    changed = true
                end
            end
        end
    end
    if changed then
        RebuildReagents()
        if atVendor then ScanVendor() end
        QueueRefresh()
    end
end

-- Events -----------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == addonName then
        EasyPoisonsDB = EasyPoisonsDB or {}
        EasyPoisonsDB.Recipes = EasyPoisonsDB.Recipes or {}
        EasyPoisonsDB.Ranks = EasyPoisonsDB.Ranks or {}
        for i = 1, #POISONS do quantities[i] = 0 end
    elseif event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "ROGUE" then return end
        -- Ranks are per character: an alt may know lower ones.
        local character = UnitName("player") .. "-" .. GetRealmName()
        EasyPoisonsDB.Ranks[character] = EasyPoisonsDB.Ranks[character] or {}
        ranks = EasyPoisonsDB.Ranks[character]
        RebuildRows()
        RebuildReagents()
        eventFrame:RegisterEvent("MERCHANT_SHOW")
        eventFrame:RegisterEvent("MERCHANT_UPDATE")
        eventFrame:RegisterEvent("MERCHANT_CLOSED")
        eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
        eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
        EasyPoisons.isRogue = true
    elseif event == "MERCHANT_SHOW" then
        atVendor = true
        if ScanVendor() then ShowWindow(true) end
        EasyPoisons:TopUpFlashPowder()
    elseif event == "MERCHANT_UPDATE" then
        if atVendor then
            ScanVendor()
            QueueRefresh()
        end
    elseif event == "MERCHANT_CLOSED" then
        atVendor, buying = false, false
        pending.id = nil
        for _, offer in pairs(offers) do offer.slot = nil end
        flashSlot = nil
        if frame and frame:IsShown() then frame:Hide() end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        LearnRecipes()
    end
end)

SLASH_EASYPOISONS1 = "/easypoisons"
SLASH_EASYPOISONS2 = "/ep"
SlashCmdList["EASYPOISONS"] = function()
    if not EasyPoisons.isRogue then
        Print("Poisons are for rogues.")
    elseif frame and frame:IsShown() then
        frame:Hide()
    else
        ShowWindow(atVendor)
    end
end

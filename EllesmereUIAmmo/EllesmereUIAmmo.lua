if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIAmmo.lua
--  Dworak > Ammo Counter: what is left in the quiver, at a glance.
--
--    [icon]  1,240            count (Text color / Low color / Critical color)
--            Jagged Arrow     optional: the ammo's name
--
--  Bow / crossbow / gun: the equipped ammo (ammo slot) and every stack of it
--  in the bags. Thrown: the thrown stack itself. Wands use no ammo: hidden.
--  A client with no ammo slot has no ammo to count: hidden too.
--
--  Warnings when the count drops under Low / Critical, when it hits zero, and
--  when the ranged weapon needs ammo but none is equipped. A screen message
--  (RaidWarningFrame), an optional sound and an optional chat line.
--
--  Vendor: a "Restock Ammo" button under the merchant window buys up to the
--  target (Restock To, or the free room of the quiver / ammo pouch), within
--  the bag room, the money and the Max Spend cap. Auto Buy does it on open.
--  BuyMerchantItem takes a count of items, a multiple of the vendor's bundle
--  (200 arrows), at most GetMerchantItemMaxStack per call.
--
--  Its own addon: registers its row in the "Dworak" section through
--  EllesmereUIDworak. No EllesmereUI file is changed.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local DW = EllesmereUIDworak
if not DW then return end -- the Dworak core is off: nothing to register into

ns.FOLDER = ADDON_NAME

local AM_DEFAULTS = {
    profile = {
        amEnabled    = true,
        amHunterOnly = true,
        amLow        = 400,         -- shots: Low color + warning under this
        amCritical   = 100,         -- shots: Critical color + warning under this
        amLowR = 0.94, amLowG = 0.62, amLowB = 0.15,
        amCritR = 0.90, amCritG = 0.25, amCritB = 0.22,
        amOnlyLow    = false,       -- hidden while above Low
        amShowIcon   = true,
        amShowName   = false,       -- second line: the ammo's name
        amTextR = 1, amTextG = 1, amTextB = 1, -- the count above Low
        amIconSize   = 30,
        amBorderSize = 1,           -- icon border, px (0 = none)
        amBorderColor = "accent",   -- "accent" = UI Accent Color, "custom" = amBorderR/G/B
        amBorderR = 0, amBorderG = 0, amBorderB = 0,
        amFont       = "__global",
        amTextSize   = 14,
        amBgR = 0.05, amBgG = 0.05, amBgB = 0.05, amBgA = 0.6,
        amWarnScreen = true,
        amWarnSound  = true,
        amWarnChat   = false,
        amWarnLogin  = true,        -- a check a few seconds after login / zoning
        amRestock    = true,        -- the button under the merchant window
        amAutoBuy    = false,       -- buys on vendor open, no click
        amTarget     = 1000,        -- restock to this many
        amFillQuiver = true,        -- target = the quiver / pouch room instead
        amMaxGold    = 0,           -- max spend per restock, gold (0 = no cap)
        amBestAmmo   = true,        -- vendor lacks your ammo: best usable of the type
        -- amPosition (point, relPoint, x, y): set by Unlock Mode
    },
}
local DEFAULTS = AM_DEFAULTS.profile

local SV_NAME = "EllesmereUIAmmoDB"
local db = EllesmereUI.Lite.NewDB(SV_NAME, AM_DEFAULTS)

local function DB()
    local active = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    if db._profileName ~= active then
        db = EllesmereUI.Lite.NewDB(SV_NAME, AM_DEFAULTS)
    end
    return db.profile
end

local function Get(key)
    local v = DB()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local function Set(key, value)
    DB()[key] = value
end

local function Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

local function Num(v)
    if Plain(v) and type(v) == "number" then return v end
end

local function Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c and c.r then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

local function AccentHex()
    local r, g, b = Accent()
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function Say(text)
    EllesmereUI.Print(AccentHex() .. "Ammo:|r " .. text)
end

local UNLOCK_KEY  = "EUI_DworakAmmo"
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = -230 }
local PAGE        = "Ammo Counter"
local WHITE       = "Interface\\Buttons\\WHITE8x8"
local NO_ICON     = "Interface\\Icons\\INV_Ammo_Arrow_02"

-- Item classes (Enum.ItemClass / ItemWeaponSubclass / ItemProjectileSubclass)
local CLS_WEAPON, CLS_PROJECTILE = 2, 6
local SUB_BOW, SUB_GUN, SUB_THROWN, SUB_XBOW = 2, 3, 16, 18
local AMMO_ARROW, AMMO_BULLET = 2, 3
local FAMILY_QUIVER, FAMILY_POUCH = 1, 2

local RANGED_SLOT = INVSLOT_RANGED or 18
local NUM_BAGS    = NUM_BAG_SLOTS or 4

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetInfo    = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetCount   = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetFamily  = (C_Item and C_Item.GetItemFamily) or GetItemFamily
local CNumSlots  = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local CFree      = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
local CItemID    = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local band       = (bit and bit.band) or function(a, b) return (a % (b * 2) >= b) and b or 0 end

local _, CLASS = UnitClass("player")

-- Live state
local A = {}          -- the last scan (see Scan)
local S = {
    level    = "ok",  -- "ok" | "low" | "crit" | "empty" | "none" (last warned level)
    armed    = false, -- warnings are live (a few seconds after login / zoning)
    unlocked = false,
    merchant = false,
    buying   = false,
    pending  = false, -- an Update is queued
}

local frame, events, buyBtn

local function Enabled() return Get("amEnabled") == true end
local function Active()
    return Enabled() and (not Get("amHunterOnly") or CLASS == "HUNTER")
end

local function FontPath()
    local f = Get("amFont")
    if f and f ~= "__global" and EllesmereUI.ResolveFontName then
        local path = EllesmereUI.ResolveFontName(f)
        if path then return path end
    end
    return EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
end

local function Thousands(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function Money(copper)
    copper = math.floor(copper + 0.5)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    end
    return string.format("%dg %ds %dc", copper / 10000, (copper % 10000) / 100, copper % 100)
end

-------------------------------------------------------------------------------
--  Scan: what the ranged slot needs and how much of it is carried
-------------------------------------------------------------------------------
local function AmmoSlot()
    if INVSLOT_AMMO then return INVSLOT_AMMO end
    if GetInventorySlotInfo then
        local ok, id = pcall(GetInventorySlotInfo, "AMMOSLOT")
        if ok and type(id) == "number" then return id end
    end
end

local function ItemCount(id)
    local n = id and GetCount and Num(GetCount(id)) or 0
    return n or 0
end

-- Projectile stacks of a subclass in the bags (ammo carried, none equipped).
local function BagAmmo(wantSub)
    local best, total = nil, 0
    if not (CNumSlots and CItemID) then return nil, 0 end
    for bag = 0, NUM_BAGS do
        local n = Num(CNumSlots(bag)) or 0
        for slot = 1, n do
            local id = Num(CItemID(bag, slot))
            if id then
                local _, _, _, _, _, cls, sub = GetInstant(id)
                if cls == CLS_PROJECTILE and sub == wantSub then
                    best = best or id
                    total = total + 1
                end
            end
        end
    end
    return best, total
end

-- A = { kind = "ammo"|"thrown"|nil, ammoID, icon, name, count, wantSub, family, spareID }
local function Scan()
    for k in pairs(A) do A[k] = nil end
    A.count = 0
    local wid = Num(GetInventoryItemID("player", RANGED_SLOT))
    if not (wid and GetInstant) then return A end
    local _, _, _, _, _, cls, sub = GetInstant(wid)
    if cls ~= CLS_WEAPON then return A end
    if sub == SUB_THROWN then
        A.kind, A.ammoID = "thrown", wid
        A.icon = GetInventoryItemTexture("player", RANGED_SLOT)
        local c1 = Num(GetInventoryItemCount("player", RANGED_SLOT)) or 0
        A.count = math.max(c1, ItemCount(wid))
    elseif sub == SUB_BOW or sub == SUB_XBOW or sub == SUB_GUN then
        local slot = AmmoSlot()
        if not slot then return A end -- this client has no ammo slot: nothing to count
        A.kind = "ammo"
        A.wantSub = (sub == SUB_GUN) and AMMO_BULLET or AMMO_ARROW
        A.family  = (sub == SUB_GUN) and FAMILY_POUCH or FAMILY_QUIVER
        local aid = Num(GetInventoryItemID("player", slot))
        if aid then
            A.ammoID = aid
            A.icon = GetInventoryItemTexture("player", slot)
            local c1 = Num(GetInventoryItemCount("player", slot)) or 0
            A.count = math.max(c1, ItemCount(aid))
        else
            A.spareID = BagAmmo(A.wantSub)
        end
    else
        return A -- wand: no ammo
    end
    if A.ammoID and GetInfo then A.name = GetInfo(A.ammoID) end
    return A
end

local function LevelOf(a)
    if not a.kind then return "none" end
    if not a.ammoID or a.count <= 0 then return "empty" end
    if a.count <= (Get("amCritical") or 0) then return "crit" end
    if a.count <= (Get("amLow") or 0) then return "low" end
    return "ok"
end

local RANK = { none = 0, ok = 0, low = 1, crit = 2, empty = 3 }

local function LevelColor(level)
    if level == "crit" or level == "empty" then return Get("amCritR"), Get("amCritG"), Get("amCritB") end
    if level == "low" then return Get("amLowR"), Get("amLowG"), Get("amLowB") end
    return Get("amTextR"), Get("amTextG"), Get("amTextB")
end

-------------------------------------------------------------------------------
--  Warnings
-------------------------------------------------------------------------------
local function Warn(level, a)
    local text
    if level == "empty" then
        if a.ammoID then
            text = "Out of ammo"
        elseif a.spareID then
            text = "No ammo equipped (there is some in your bags)"
        else
            text = "No ammo equipped"
        end
    elseif level == "crit" then
        text = string.format("Ammo critical: %s left", Thousands(a.count))
    else
        text = string.format("Ammo low: %s left", Thousands(a.count))
    end
    local r, g, b = LevelColor(level)
    if Get("amWarnScreen") then
        if RaidNotice_AddMessage and RaidWarningFrame then
            RaidNotice_AddMessage(RaidWarningFrame, text, { r = r, g = g, b = b })
        elseif UIErrorsFrame then
            UIErrorsFrame:AddMessage(text, r, g, b)
        end
    end
    if Get("amWarnSound") and PlaySound then
        local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
        pcall(PlaySound, kit, "Master")
    end
    if Get("amWarnChat") then Say(text) end
end

-- Warn on the way down only; going up (restock, swap) just resets the level.
local function CheckLevel(a)
    local level = LevelOf(a)
    if S.armed and RANK[level] > RANK[S.level] then Warn(level, a) end
    S.level = level
end

-------------------------------------------------------------------------------
--  The widget (the live frame and the options preview are both made here)
-------------------------------------------------------------------------------
local function MakeWidget(f)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()

    -- Icon with a 1px border (accent, or the level color when low)
    f.iconBorder = f:CreateTexture(nil, "BORDER")
    f.iconBorder:SetTexture(WHITE)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetFontObject(GameFontHighlight)
    f.count:SetShadowOffset(1, -1)
    f.count:SetJustifyH("LEFT")
    f.count:SetText("")
    f.sub = f:CreateFontString(nil, "OVERLAY")
    f.sub:SetFontObject(GameFontHighlightSmall)
    f.sub:SetShadowOffset(1, -1)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetTextColor(0.7, 0.7, 0.7)
    f.sub:SetText("")
    return f
end

local PAD = 5

local function StyleWidget(f)
    f.bg:SetColorTexture(Get("amBgR"), Get("amBgG"), Get("amBgB"), Get("amBgA"))
    local size = Get("amTextSize")
    EllesmereUI.ApplyModuleFont(f.count, FontPath(), size + 2)
    EllesmereUI.ApplyModuleFont(f.sub, FontPath(), math.max(6, size - 3))
    local showIcon = Get("amShowIcon") ~= false
    local is = Get("amIconSize")
    local bs = math.max(0, math.min(math.floor((Get("amBorderSize") or 1) + 0.5), math.floor(is / 4)))
    f.iconBorder:SetShown(showIcon and bs > 0)
    f.icon:SetShown(showIcon)
    f.iconBorder:ClearAllPoints()
    f.iconBorder:SetPoint("LEFT", f, "LEFT", PAD, 0)
    f.iconBorder:SetSize(is, is)
    -- The icon sits inside the border (0: it fills the whole square).
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", f.iconBorder, "TOPLEFT", bs, -bs)
    f.icon:SetPoint("BOTTOMRIGHT", f.iconBorder, "BOTTOMRIGHT", -bs, bs)
    local left = showIcon and (PAD + is + 6) or (PAD + 2)
    f._left = left
    f._iconH = showIcon and (is + PAD * 2) or 0
    f._textSize = size
end

-- One line (the count) or two (the count + the name / a note).
local function LayoutLines(f, two)
    f.count:ClearAllPoints()
    f.sub:ClearAllPoints()
    if two then
        f.count:SetPoint("BOTTOMLEFT", f, "LEFT", f._left, 1)
        f.sub:SetPoint("TOPLEFT", f, "LEFT", f._left, -1)
        f.sub:Show()
    else
        f.count:SetPoint("LEFT", f, "LEFT", f._left, 0)
        f.sub:Hide()
    end
    f._h = math.max(f._iconH, (f._textSize + 2) + (two and f._textSize or 0) + PAD * 2)
end

-- One paint. d = { count, icon, level, name, note }
local function PaintWidget(f, d)
    local level = d.level
    local r, g, b = LevelColor(level)
    if level == "empty" then
        f.count:SetText("No ammo")
    else
        f.count:SetText(Thousands(d.count or 0))
    end
    f.count:SetTextColor(r, g, b)
    local line = d.note or (Get("amShowName") and d.name) or nil
    f.sub:SetText(line or "")
    LayoutLines(f, line ~= nil)
    f.icon:SetTexture(d.icon or NO_ICON)
    f.icon:SetDesaturated(level == "empty")
    if level == "ok" or level == "none" then
        if Get("amBorderColor") == "custom" then
            f.iconBorder:SetVertexColor(Get("amBorderR"), Get("amBorderG"), Get("amBorderB"))
        else
            f.iconBorder:SetVertexColor(Accent())
        end
    else
        f.iconBorder:SetVertexColor(r, g, b)
    end
    local textW = math.max(f.count:GetStringWidth() or 0, f.sub:IsShown() and (f.sub:GetStringWidth() or 0) or 0)
    f:SetSize(math.max(60, f._left + textW + PAD + 4), f._h)
end

local function WidgetData(a)
    local level = LevelOf(a)
    local d = { count = a.count, icon = a.icon, level = level, name = a.name }
    if level == "empty" then
        d.note = a.spareID and "equip it from your bags" or (a.kind == "thrown" and "buy more" or "restock at a vendor")
        if a.spareID then
            local tex = select(5, GetInstant(a.spareID))
            d.icon = tex or d.icon
        end
    end
    return d
end

-------------------------------------------------------------------------------
--  Position (Unlock Mode)
-------------------------------------------------------------------------------
local function SavedPos()
    local pos = Get("amPosition")
    return pos and pos.point and pos or DEFAULT_POS
end

local function Place()
    if not frame then return end
    StyleWidget(frame)
    frame:ClearAllPoints()
    local pos = SavedPos()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "EUI_DworakAmmoFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(20)
    frame:SetClampedToScreen(true)
    MakeWidget(frame)
    frame:SetSize(100, 40)
    frame:Hide()
    Place()
    return frame
end

-------------------------------------------------------------------------------
--  Vendor restock
-------------------------------------------------------------------------------
local function MerchantInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local t = C_MerchantFrame.GetItemInfo(i)
        if t then return t.price, t.stackCount, t.numAvailable, t.isUsable, t.hasExtendedCost end
    end
    if GetMerchantItemInfo then
        local _, _, price, qty, avail, _, usable, ext = GetMerchantItemInfo(i)
        return price, qty, avail, usable, ext
    end
end

local function StackSize(id)
    local s = GetInfo and select(8, GetInfo(id))
    return (type(s) == "number" and s > 0) and s or 200
end

-- Room in the quiver / pouch for the target (bags of the weapon's family).
local function QuiverRoom(family, stack)
    if not (family and CNumSlots and CFree) then return 0 end
    local slots = 0
    for bag = 1, NUM_BAGS do
        local _, fam = CFree(bag)
        fam = Num(fam) or 0
        if fam ~= 0 and band(fam, family) ~= 0 then slots = slots + (Num(CNumSlots(bag)) or 0) end
    end
    return slots * stack
end

-- Free room for this item: empty slots of bags that take it, plus the top-up
-- of a partial stack.
local function FreeRoom(id, stack, have)
    if not CFree then return math.huge end
    local itemFam = GetFamily and Num(GetFamily(id)) or 0
    local slots = 0
    for bag = 0, NUM_BAGS do
        local free, fam = CFree(bag)
        free, fam = Num(free) or 0, Num(fam) or 0
        if fam == 0 or band(fam, itemFam) ~= 0 then slots = slots + free end
    end
    local partial = (have % stack == 0) and 0 or (stack - have % stack)
    return slots * stack + partial
end

local function Target(a, stack)
    local t = Get("amTarget") or 1000
    if Get("amFillQuiver") and a.kind == "ammo" then
        local cap = QuiverRoom(a.family, stack)
        if cap > 0 then t = cap end
    end
    return t
end

-- The vendor index of the ammo to buy (the equipped one first).
local function PickMerchantItem(a)
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    local want = a.ammoID or a.spareID
    if want then
        for i = 1, n do
            if GetMerchantItemID(i) == want then return i, want end
        end
    end
    if not (Get("amBestAmmo") and a.kind == "ammo") then return end
    local best, bestID, bestLvl = nil, nil, -1
    local myLevel = UnitLevel("player") or 1
    for i = 1, n do
        local id = GetMerchantItemID(i)
        if id then
            local _, _, _, _, _, cls, sub = GetInstant(id)
            if cls == CLS_PROJECTILE and sub == a.wantSub then
                local _, _, _, usable, ext = MerchantInfo(i)
                local _, _, _, ilvl, minLvl = GetInfo(id)
                if usable ~= false and not ext and (minLvl or 0) <= myLevel and (ilvl or 0) > bestLvl then
                    best, bestID, bestLvl = i, id, ilvl or 0
                end
            end
        end
    end
    return best, bestID
end

-- plan = { index, id, name, buy, batch, cost, maxStack, have, target } or nil, reason
local function BuildPlan()
    local a = Scan()
    if not a.kind then return nil, "No ranged weapon that uses ammo" end
    local index, id = PickMerchantItem(a)
    if not index then return nil, "This vendor doesn't sell your ammo" end
    local price, batch, avail, _, ext = MerchantInfo(index)
    if ext then return nil, "This ammo costs a currency, not gold" end
    price = Num(price) or 0
    batch = math.max(1, Num(batch) or 1)
    local stack = StackSize(id)
    local have = (id == a.ammoID) and a.count or ItemCount(id)
    local target = Target(a, stack)
    local need = target - have
    if need <= 0 then
        return nil, string.format("Stocked: %s / %s", Thousands(have), Thousands(target)), true
    end
    -- Whole bundles up to the target; the last bundle may pass it, never the bag room.
    local room = FreeRoom(id, stack, have)
    local buy = math.ceil(need / batch) * batch
    if buy > room then buy = math.floor(room / batch) * batch end
    if buy <= 0 then return nil, "No bag room for more ammo" end
    if avail and avail >= 0 then buy = math.min(buy, avail * batch) end
    if price > 0 then
        local budget = GetMoney()
        local cap = (Get("amMaxGold") or 0) * 10000
        if cap > 0 then budget = math.min(budget, cap) end
        buy = math.min(buy, math.floor(budget / price) * batch)
        if buy <= 0 then return nil, (cap > 0 and GetMoney() >= price) and "Over the Max Spend cap" or "Not enough money" end
    end
    local maxStack = GetMerchantItemMaxStack and Num(GetMerchantItemMaxStack(index)) or batch
    return {
        index = index, id = id, name = (GetInfo and GetInfo(id)) or ("item " .. id),
        buy = buy, batch = batch, cost = buy / batch * price,
        maxStack = maxStack, have = have, target = target,
        swap = (a.ammoID and id ~= a.ammoID) or (not a.ammoID),
    }
end

local RefreshButton

local function Buy(plan)
    if S.buying or not plan then return end
    S.buying = true
    local per = math.max(plan.batch, math.floor((plan.maxStack or plan.batch) / plan.batch) * plan.batch)
    local left = plan.buy
    local function step()
        if not S.merchant or GetMerchantItemID(plan.index) ~= plan.id then
            S.buying = false
            Say("restock stopped (the vendor window changed).")
            return
        end
        local q = math.min(left, per)
        BuyMerchantItem(plan.index, q)
        left = left - q
        if left > 0 then
            C_Timer.After(0.3, step)
        else
            S.buying = false
            Say(string.format("bought %s %s for %s.", Thousands(plan.buy), plan.name, Money(plan.cost)))
            if plan.swap then Say("right-click the new ammo in your bags to equip it.") end
            C_Timer.After(0.5, function() if RefreshButton then RefreshButton() end end)
        end
    end
    step()
end

local function MakeButton()
    if buyBtn or not MerchantFrame then return buyBtn end
    local b = CreateFrame("Button", "EUI_DworakAmmoRestock", MerchantFrame)
    b:SetSize(170, 24)
    b:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", 0, -4)
    b:SetFrameStrata("HIGH")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.06, 0.06, 0.06, 0.92)
    b.fill = b:CreateTexture(nil, "BORDER")
    b.fill:SetAllPoints()
    b.fill:SetTexture(WHITE)
    b.edges = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE)
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        b.edges[i] = t
    end
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 5, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFontObject(GameFontHighlightSmall)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self)
        self.hover = true
        RefreshButton()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Restock Ammo")
        local p = self.plan
        if p then
            GameTooltip:AddLine(string.format("Buy %s %s", Thousands(p.buy), p.name), 1, 1, 1)
            GameTooltip:AddLine("Cost: " .. Money(p.cost), 1, 1, 1)
            GameTooltip:AddLine(string.format("Carried: %s  ->  %s (target %s)",
                Thousands(p.have), Thousands(p.have + p.buy), Thousands(p.target)), 0.7, 0.7, 0.7)
            if p.swap then GameTooltip:AddLine("Not your equipped ammo: equip it after buying.", 0.94, 0.62, 0.15, true) end
        elseif self.reason then
            GameTooltip:AddLine(self.reason, 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.hover = false
        RefreshButton()
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
        if self.plan then Buy(self.plan) end
    end)
    buyBtn = b
    return b
end

function RefreshButton()
    if not buyBtn then return end
    if not (S.merchant and Active() and Get("amRestock")) then buyBtn:Hide(); return end
    local plan, reason, stocked = BuildPlan()
    if not plan and not A.kind then buyBtn:Hide(); return end
    buyBtn.plan, buyBtn.reason = plan, reason
    local r, g, b = Accent()
    for _, t in ipairs(buyBtn.edges) do t:SetVertexColor(r, g, b, plan and 0.9 or 0.35) end
    buyBtn.fill:SetVertexColor(r, g, b, plan and (buyBtn.hover and 0.30 or 0.16) or 0)
    buyBtn.icon:SetTexture(A.icon or (plan and select(5, GetInstant(plan.id))) or NO_ICON)
    buyBtn.icon:SetDesaturated(not plan)
    if plan then
        buyBtn.text:SetText(string.format("Restock Ammo  |cffffffff+%s|r", Thousands(plan.buy)))
        buyBtn.text:SetTextColor(1, 1, 1)
    else
        buyBtn.text:SetText(stocked and "Ammo stocked" or "Restock Ammo")
        buyBtn.text:SetTextColor(0.55, 0.55, 0.55)
    end
    buyBtn:Show()
end

-------------------------------------------------------------------------------
--  Update (the live widget)
-------------------------------------------------------------------------------
local function Update()
    S.pending = false
    if not Active() then
        if frame then frame:Hide() end
        return
    end
    Build()
    local a = Scan()
    CheckLevel(a)
    if S.unlocked then return end
    if not a.kind then frame:Hide(); return end
    local d = WidgetData(a)
    PaintWidget(frame, d)
    frame:SetShown(not (Get("amOnlyLow") and d.level == "ok"))
end

local function Queue()
    if S.pending then return end
    S.pending = true
    C_Timer.After(0.1, function()
        Update()
        if S.merchant then RefreshButton() end
    end)
end

local function Arm()
    S.armed = false
    C_Timer.After(4, function()
        local a = Scan()
        S.level = Get("amWarnLogin") and "ok" or LevelOf(a)
        S.armed = true
        CheckLevel(a)
    end)
end

local function OnEvent(_, event, a1, a2)
    if event == "PLAYER_SWING" then
        -- a ranged shot used an arrow: recount (cheap, throttled)
        Queue()
    elseif event == "MERCHANT_SHOW" then
        S.merchant = true
        if not Get("amRestock") and not Get("amAutoBuy") then return end
        MakeButton()
        C_Timer.After(0.2, function()
            RefreshButton()
            if Get("amAutoBuy") and buyBtn and buyBtn.plan then Buy(buyBtn.plan) end
        end)
    elseif event == "MERCHANT_CLOSED" then
        S.merchant = false
        if buyBtn then buyBtn:Hide() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Place()
        Arm()
        Queue()
    else
        Queue()
    end
end

local UNIT_EVENTS = { "UNIT_INVENTORY_CHANGED" }
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_SWING", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE",
    "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP",
}

local RefreshPreview

local function Apply()
    if events then events:UnregisterAllEvents() end
    if not Active() then
        if frame then frame:Hide() end
        if buyBtn then buyBtn:Hide() end
        if RefreshPreview then RefreshPreview() end
        return
    end
    Build()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    for _, ev in ipairs(EVENTS) do pcall(events.RegisterEvent, events, ev) end
    for _, ev in ipairs(UNIT_EVENTS) do pcall(events.RegisterUnitEvent, events, ev, "player") end
    S.merchant = MerchantFrame and MerchantFrame:IsShown() or false
    Place()
    Update()
    if S.merchant then MakeButton(); RefreshButton() end
    if RefreshPreview then RefreshPreview() end
end

-------------------------------------------------------------------------------
--  Options preview: the widget in the content header, cycling sample states
-------------------------------------------------------------------------------
local PREVIEW_H = 90
local SAMPLES = {
    { count = 1240, level = "ok", name = "Jagged Arrow", hint = "Plenty left" },
    { level = "low", hint = "Under Low: Low color + warning" },
    { level = "crit", hint = "Under Critical: Critical color + warning" },
    { count = 0, level = "empty", note = "restock at a vendor", hint = "Out of ammo" },
}
local preview

local function SampleData(i)
    local s = SAMPLES[i]
    local d = { count = s.count, level = s.level, name = s.name or "Jagged Arrow",
                note = s.note, icon = "Interface\\Icons\\INV_Ammo_Arrow_02" }
    if s.level == "low" then d.count = math.max(1, math.floor((Get("amLow") + Get("amCritical")) / 2)) end
    if s.level == "crit" then d.count = math.max(1, math.floor(Get("amCritical") * 0.6)) end
    return d, s.hint
end

local function PreviewTick(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < 2 and self.shown then return end
    self.acc = 0
    self.shown = true
    self.i = (self.i or 0) % #SAMPLES + 1
    local d, hint = SampleData(self.i)
    PaintWidget(self.box, d)
    self.hint:SetText(Enabled() and hint or "Preview (the counter is off)")
end

function RefreshPreview()
    if not (preview and preview:IsShown()) then return end
    StyleWidget(preview.box)
    PaintWidget(preview.box, SampleData(preview.i or 1))
    preview.box:SetAlpha(Enabled() and 1 or 0.5)
end

local function HeaderBuilder(header, width)
    if not preview then
        preview = CreateFrame("Frame", nil, header)
        preview.box = MakeWidget(CreateFrame("Frame", nil, preview))
        preview.box:SetPoint("CENTER", 0, 8)
        preview.hint = preview:CreateFontString(nil, "OVERLAY")
        preview.hint:SetFontObject(GameFontDisableSmall)
        preview.hint:SetPoint("BOTTOM", preview, "BOTTOM", 0, 6)
        preview:SetScript("OnUpdate", PreviewTick)
    end
    preview:SetParent(header)
    preview:SetFrameStrata(header:GetFrameStrata())
    preview:SetFrameLevel(header:GetFrameLevel() + 5)
    preview.box:SetFrameLevel(preview:GetFrameLevel() + 1)
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", header, "TOPLEFT")
    preview:SetPoint("TOPRIGHT", header, "TOPRIGHT")
    if width and width > 0 then preview:SetWidth(width) end
    preview:SetHeight(PREVIEW_H)
    preview:Show()
    RefreshPreview()
    return PREVIEW_H
end

local function Refresh()
    if frame then
        Place()
        Update()
    end
    if S.merchant then RefreshButton() end
    RefreshPreview()
end

-------------------------------------------------------------------------------
--  Options page (Dworak > Ammo Counter)
-------------------------------------------------------------------------------
local function BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    parent._showRowDivider = true
    local function off() return not Enabled() end
    local OFF_TIP = "Ammo Counter"
    local prebuilding = EllesmereUI.IsSearchPrebuild()
    if not prebuilding then EllesmereUI:SetContentHeader(HeaderBuilder) end

    local function S_(key, after)
        return function(v)
            Set(key, v)
            if after then after() end
            Refresh()
        end
    end
    local function Swatch(region, tip, kR, kG, kB, disabled)
        if prebuilding or not region then return end
        EllesmereUI.BuildInlineSwatches(region, { {
            tooltip = tip,
            disabled = disabled or off,
            disabledTooltip = function() return off() and OFF_TIP or "Border Color: Custom" end,
            getValue = function() return Get(kR), Get(kG), Get(kB), 1 end,
            setValue = function(r, g, b)
                Set(kR, r); Set(kG, g); Set(kB, b)
                Refresh()
            end,
        } }, { disabled = off, disabledTooltip = OFF_TIP })
    end

    _, h = W:SectionHeader(parent, "AMMO COUNTER", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Ammo Counter",
          tooltip = "Arrows / bullets (or the thrown stack) you carry. "
              .. "Hidden with a wand or no ranged weapon.\nMove it in Unlock Mode.",
          getValue = function() return Enabled() end,
          setValue = function(v)
              Set("amEnabled", v)
              Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Hunters Only",
          tooltip = "Off: for every class with a bow, gun, crossbow or thrown weapon.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amHunterOnly") ~= false end,
          setValue = function(v)
              Set("amHunterOnly", v)
              Apply()
          end }
    );  y = y - h

    local lvlRow
    lvlRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Low", min = 0, max = 3000, step = 50, trackWidth = 120,
          tooltip = "Under this many shots: the Low color (swatch) and a warning.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amLow") end,
          setValue = S_("amLow") },
        { type = "slider", text = "Critical", min = 0, max = 1000, step = 25, trackWidth = 120,
          tooltip = "Under this many shots: the Critical color (swatch) and a second warning.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amCritical") end,
          setValue = S_("amCritical") }
    );  y = y - h
    if lvlRow then
        Swatch(lvlRow._leftRegion, "Low Color", "amLowR", "amLowG", "amLowB")
        Swatch(lvlRow._rightRegion, "Critical Color", "amCritR", "amCritG", "amCritB")
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Only When Low",
          tooltip = "Hidden while the count is above Low.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amOnlyLow") == true end,
          setValue = S_("amOnlyLow") },
        { type = "toggle", text = "Show Ammo Name",
          tooltip = "Second line: the ammo's name.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amShowName") == true end,
          setValue = S_("amShowName") }
    );  y = y - h

    local function iconOff() return off() or Get("amShowIcon") == false end
    local function borderOff() return iconOff() or (Get("amBorderSize") or 1) <= 0 end
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Icon",
          tooltip = "The ammo's icon, with an optional border.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amShowIcon") ~= false end,
          setValue = function(v)
              Set("amShowIcon", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "slider", text = "Icon Size", min = 12, max = 64, step = 1,
          disabled = iconOff, disabledTooltip = "Ammo Counter / Show Icon",
          getValue = function() return Get("amIconSize") end,
          setValue = S_("amIconSize") }
    );  y = y - h

    local borderRow
    borderRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Icon Border", min = 0, max = 6, step = 1,
          tooltip = "Thickness of the icon's border in pixels. 0 = no border.",
          disabled = iconOff, disabledTooltip = "Ammo Counter / Show Icon",
          getValue = function() return Get("amBorderSize") end,
          setValue = function(v)
              Set("amBorderSize", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Border Color",
          tooltip = "UI Accent Color follows Global Settings; Custom uses the color next to it. "
              .. "Under Low / Critical the border takes that level's color.",
          values = { accent = "UI Accent Color", custom = "Custom" }, order = { "accent", "custom" },
          disabled = borderOff, disabledTooltip = "Show Icon / Icon Border above 0",
          getValue = function() return Get("amBorderColor") or "accent" end,
          setValue = function(v)
              Set("amBorderColor", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    if borderRow then
        Swatch(borderRow._rightRegion, "Custom Border Color", "amBorderR", "amBorderG", "amBorderB",
            function() return borderOff() or Get("amBorderColor") ~= "custom" end)
    end

    local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Font", values = fontValues, order = fontOrder,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amFont") or "__global" end,
          setValue = S_("amFont") },
        { type = "slider", text = "Text Size", min = 8, max = 28, step = 1,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amTextSize") end,
          setValue = S_("amTextSize") }
    );  y = y - h

    local bgRow
    bgRow, h = W:DualRow(parent, y,
        { type = "colorpicker", text = "Text Color", hasAlpha = false,
          tooltip = "The count above Low (under Low / Critical it takes that level's color).",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amTextR"), Get("amTextG"), Get("amTextB"), 1 end,
          setValue = function(r, g, b)
              Set("amTextR", r); Set("amTextG", g); Set("amTextB", b)
              Refresh()
          end },
        { type = "slider", text = "Background", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the background (color: the swatch).",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return math.floor(Get("amBgA") * 100 + 0.5) end,
          setValue = function(v)
              Set("amBgA", v / 100)
              Refresh()
          end }
    );  y = y - h
    if bgRow then Swatch(bgRow._rightRegion, "Background Color", "amBgR", "amBgG", "amBgB") end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "WARNINGS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Screen Warning",
          tooltip = "A raid-warning style message when the count drops under Low, under Critical, "
              .. "to zero, or when no ammo is equipped.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amWarnScreen") ~= false end,
          setValue = S_("amWarnScreen") },
        { type = "toggle", text = "Warning Sound",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amWarnSound") ~= false end,
          setValue = S_("amWarnSound") }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Chat Message",
          tooltip = "The warning in the chat frame too.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amWarnChat") == true end,
          setValue = S_("amWarnChat") },
        { type = "toggle", text = "Check on Login",
          tooltip = "Warns a few seconds after login / zoning if you are already low.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amWarnLogin") ~= false end,
          setValue = S_("amWarnLogin") }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "VENDOR RESTOCK", y);  y = y - h

    local function rsOff() return off() or not Get("amRestock") end
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Restock Button",
          tooltip = "A button under the merchant window that buys your ammo up to the target, "
              .. "within your bag room, money and Max Spend.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("amRestock") ~= false end,
          setValue = function(v)
              Set("amRestock", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Auto Buy",
          tooltip = "Buys on vendor open, without the click.",
          disabled = rsOff, disabledTooltip = "Restock Button",
          getValue = function() return Get("amAutoBuy") == true end,
          setValue = S_("amAutoBuy") }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Fill Quiver",
          tooltip = "Target = the full capacity of your quiver / ammo pouch (slots x stack). "
              .. "Without one (or thrown): Restock To.",
          disabled = rsOff, disabledTooltip = "Restock Button",
          getValue = function() return Get("amFillQuiver") ~= false end,
          setValue = function(v)
              Set("amFillQuiver", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "slider", text = "Restock To", min = 200, max = 6000, step = 100,
          tooltip = "Buy up to this many (used when Fill Quiver is off or finds no quiver).",
          disabled = rsOff, disabledTooltip = "Restock Button",
          getValue = function() return Get("amTarget") end,
          setValue = S_("amTarget") }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Max Spend (gold)", min = 0, max = 200, step = 1,
          tooltip = "The most one restock may cost. 0 = no cap.",
          disabled = rsOff, disabledTooltip = "Restock Button",
          getValue = function() return Get("amMaxGold") end,
          setValue = S_("amMaxGold") },
        { type = "toggle", text = "Best Ammo Fallback",
          tooltip = "The vendor lacks your equipped ammo: buy the best one of the same type "
              .. "(arrows / bullets) you can use. Equip it after buying.",
          disabled = rsOff, disabledTooltip = "Restock Button",
          getValue = function() return Get("amBestAmmo") ~= false end,
          setValue = S_("amBestAmmo") }
    );  y = y - h

    return math.abs(y)
end

DW.AddModule({
    key         = "Ammo",
    title       = "Ammo Counter",
    order       = 40,
    description = "Ammo left, low-ammo warnings and vendor restock.",
    pages       = { PAGE },
    buildPage   = BuildPage,
    getHeaderBuilder = function() return HeaderBuilder end,
    onPageCacheRestore = function() RefreshPreview() end,
})

EllesmereUIAmmo = {
    Get = Get, Set = Set, Apply = Apply, Refresh = Refresh,
    Open = function() return DW.Open("Ammo") end,
}

-- /ammo opens the page; /ammo debug prints the state; /ammo test fires a warning.
SLASH_EUIAMMO1 = "/euiammo"
SLASH_EUIAMMO2 = "/ammo"
SlashCmdList.EUIAMMO = function(msg)
    msg = msg and msg:lower() or ""
    if msg:match("debug") then
        local a = Scan()
        local slot = AmmoSlot()
        Say("enabled = " .. tostring(Enabled()) .. ", active = " .. tostring(Active()) .. ", class = " .. tostring(CLASS))
        Say("ammo slot = " .. tostring(slot) .. ", ranged item = " .. tostring(GetInventoryItemID("player", RANGED_SLOT)))
        Say("kind = " .. tostring(a.kind) .. ", ammo = " .. tostring(a.ammoID) .. " (" .. tostring(a.name) .. ")"
            .. ", count = " .. tostring(a.count) .. ", level = " .. LevelOf(a))
        if a.kind == "ammo" then
            Say("quiver room = " .. QuiverRoom(a.family, a.ammoID and StackSize(a.ammoID) or 200)
                .. ", spare in bags = " .. tostring(a.spareID))
        end
        if S.merchant then
            local plan, reason = BuildPlan()
            if plan then
                Say(string.format("vendor plan: #%d %s x%s (bundle %d, max/call %d) for %s",
                    plan.index, plan.name, plan.buy, plan.batch, plan.maxStack or 0, Money(plan.cost)))
            else
                Say("vendor plan: " .. tostring(reason))
            end
        end
        return
    elseif msg:match("test") then
        local a = Scan()
        local fake = { kind = "ammo", ammoID = 1, count = math.max(1, math.floor(Get("amCritical") * 0.6)) }
        Warn("crit", a.kind and a.ammoID and a or fake)
        return
    end
    DW.Open("Ammo")
end

-- The UI Accent Color (Global Settings) repaints the icon border and the button.
if EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function() Refresh() end })
end

-------------------------------------------------------------------------------
--  Login: apply, then the Unlock Mode element
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    EllesmereUI:RegisterUnlockElements({
        EllesmereUI.MakeUnlockElement({
            key      = UNLOCK_KEY,
            label    = "Ammo Counter",
            group    = DW.UNLOCK_GROUP,
            order    = 930,
            noResize = true,
            isHidden = function() return not Active() end,
            getFrame = function()
                if not Active() then return nil end
                Build()
                return frame
            end,
            getSize = function()
                if frame then return frame:GetWidth(), frame:GetHeight() end
                return 100, 40
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                Set("amPosition", { point = point, relPoint = relPoint, x = x, y = y })
                if not (EllesmereUI.IsUnlockModeActive and EllesmereUI:IsUnlockModeActive()) then Place() end
            end,
            loadPos = SavedPos,
            clearPos = function()
                Set("amPosition", nil)
                Place()
            end,
            applyPos = function()
                if Active() then
                    Build()
                    Place()
                end
            end,
        }),
    }, ns.FOLDER)
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener(UNLOCK_KEY, function(active)
            S.unlocked = active and Active() or false
            if not frame then return end
            if S.unlocked then
                frame:Show()
                PaintWidget(frame, SampleData(1))
            else
                Update()
            end
        end)
    end
end)

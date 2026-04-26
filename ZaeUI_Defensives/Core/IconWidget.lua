-- ZaeUI_Defensives/Core/IconWidget.lua
-- Single source of truth for the cooldown icon used by FloatingDisplay and
-- FrameDisplay. Owns frame creation, the recycling pool, the cooldown swipe,
-- LibCustomGlow integration, the charge counter, and the cooldown text
-- countdown (custom font string + shared OnUpdate so we keep full control of
-- the text size — Blizzard's native countdown auto-scales above what fits in
-- a 20px icon).
-- luacheck: no self

local _, ns = ...
ns.Core = ns.Core or {}
local Util = ns.Utils and ns.Utils.Util
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local IconWidget = {}

-- Glow color palette per cooldown category. Centralized so both displays
-- show the same color for the same buff and adding a new category here
-- propagates everywhere.
local GLOW_COLORS = {
    External = { 1.00, 0.82, 0.20, 1.0 }, -- gold
    Personal = { 0.23, 0.71, 1.00, 1.0 }, -- ZaeUI cyan
    Raidwide = { 0.30, 1.00, 0.30, 1.0 }, -- green
}
-- Returned for unknown categories. Module-level constant so the unknown
-- fallback in colorFor never allocates inside the BuffStart hot path.
local GLOW_COLOR_DEFAULT = { 1, 1, 1, 1 }
IconWidget.GLOW_COLORS = GLOW_COLORS

local widgetPool = {}

-- Default options. Callers override anything they want via the opts table.
-- Sized to fit comfortably inside a 20px icon: a 4-character "X:XX" label
-- in a 7px outline font stays within the icon footprint.
local DEFAULT_OPTS = {
    size = 20,
    countFont = "NumberFontNormal",
    countAnchor = "BOTTOMRIGHT",
    countOffsetX = -2,
    countOffsetY = 1,
    timerFont = STANDARD_TEXT_FONT,
    timerSize = 7,
    timerFlags = "OUTLINE",
    timerAnchor = "CENTER",
    timerOffsetX = 0,
    timerOffsetY = 0,
}

local function colorFor(info)
    if info and info.category and GLOW_COLORS[info.category] then
        return GLOW_COLORS[info.category]
    end
    return GLOW_COLOR_DEFAULT
end

local function onTooltipEnter(self)
    if not self._spellID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self._spellID)
    GameTooltip:Show()
end

local function onTooltipLeave()
    GameTooltip:Hide()
end

-- Shared top-level OnUpdate handler. Reads its state from the icon's own
-- fields (_cdStart, _cdDur) so we never allocate a per-icon closure. Tick
-- rate is 10 Hz; the integer-second cache skips the SetText (and the format
-- it triggers) when the visible label has not changed.
local function timerOnUpdate(self, elapsed)
    self._timerAcc = (self._timerAcc or 0) + elapsed
    if self._timerAcc < 0.1 then return end
    self._timerAcc = 0
    local now = GetTime and GetTime() or 0
    local remaining = (self._cdStart or 0) + (self._cdDur or 0) - now
    if remaining <= 0 then
        if self.Text then self.Text:SetText("") end
        self._lastTimerText = nil
        self:SetScript("OnUpdate", nil)
        return
    end
    local seconds = math.floor(remaining + 0.5)
    if seconds == self._lastTimerText then return end
    local txt
    if seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = seconds - m * 60
        txt = m .. ":" .. (s < 10 and "0" or "") .. s
    else
        txt = tostring(seconds)
    end
    self.Text:SetText(txt)
    self._lastTimerText = seconds
end

local function applyCountStyle(f, opts)
    if not f.Count then return end
    local countFont  = (opts and opts.countFont)    or DEFAULT_OPTS.countFont
    local cAnchor    = (opts and opts.countAnchor)  or DEFAULT_OPTS.countAnchor
    local cX         = (opts and opts.countOffsetX) or DEFAULT_OPTS.countOffsetX
    local cY         = (opts and opts.countOffsetY) or DEFAULT_OPTS.countOffsetY
    if f._countFont ~= countFont then
        f.Count:SetFontObject(countFont)
        f._countFont = countFont
    end
    if f._countAnchor ~= cAnchor or f._countOffX ~= cX or f._countOffY ~= cY then
        f.Count:ClearAllPoints()
        f.Count:SetPoint(cAnchor, cX, cY)
        f._countAnchor, f._countOffX, f._countOffY = cAnchor, cX, cY
    end
end

local function applyTimerStyle(f, opts)
    if not f.Text then return end
    local font   = (opts and opts.timerFont)    or DEFAULT_OPTS.timerFont
    local size   = (opts and opts.timerSize)    or DEFAULT_OPTS.timerSize
    local flags  = (opts and opts.timerFlags)   or DEFAULT_OPTS.timerFlags
    local anchor = (opts and opts.timerAnchor)  or DEFAULT_OPTS.timerAnchor
    local ox     = (opts and opts.timerOffsetX) or DEFAULT_OPTS.timerOffsetX
    local oy     = (opts and opts.timerOffsetY) or DEFAULT_OPTS.timerOffsetY
    if f._timerFont ~= font or f._timerSize ~= size or f._timerFlags ~= flags then
        f.Text:SetFont(font, size, flags)
        f._timerFont, f._timerSize, f._timerFlags = font, size, flags
    end
    if f._timerAnchor ~= anchor or f._timerOffX ~= ox or f._timerOffY ~= oy then
        f.Text:ClearAllPoints()
        f.Text:SetPoint(anchor, ox, oy)
        f._timerAnchor, f._timerOffX, f._timerOffY = anchor, ox, oy
    end
end

local function buildIcon(parent, size, opts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:EnableMouse(true)
    f:SetScript("OnEnter", onTooltipEnter)
    f:SetScript("OnLeave", onTooltipLeave)
    f.Texture = f:CreateTexture(nil, "ARTWORK")
    f.Texture:SetAllPoints()
    f.Texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.Cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.Cooldown:SetAllPoints()
    f.Cooldown:EnableMouse(false)
    -- Hide the native countdown — Blizzard's auto-scaled font overflows on
    -- small icons. The custom Text region above gives us full control.
    f.Cooldown:SetHideCountdownNumbers(true)

    -- Text overlay sits one frame level above the swipe so the cooldown
    -- shadow does not dim it.
    f.TextOverlay = CreateFrame("Frame", nil, f)
    f.TextOverlay:SetAllPoints()
    f.TextOverlay:SetFrameLevel(f.Cooldown:GetFrameLevel() + 2)
    f.Text = f.TextOverlay:CreateFontString(nil, "OVERLAY")
    applyTimerStyle(f, opts)

    f.Count = f:CreateFontString(nil, "OVERLAY",
                                  (opts and opts.countFont) or DEFAULT_OPTS.countFont)
    f.Count:Hide()
    applyCountStyle(f, opts)
    return f
end

--- Acquires an icon frame from the pool (or creates one). Reparents to the
--- given frame, resizes, and re-applies count + timer styling so a frame
--- released by one display reads correctly when reused by another.
--- @param parent table Frame the icon will be parented to.
--- @param size number Icon side in pixels (overrides opts.size when given).
--- @param opts table|nil styling overrides (see DEFAULT_OPTS for keys)
--- @return table icon
function IconWidget.Acquire(parent, size, opts)
    size = size or (opts and opts.size) or DEFAULT_OPTS.size
    local n = #widgetPool
    if n > 0 then
        local f = widgetPool[n]
        widgetPool[n] = nil
        f:SetParent(parent)
        f:SetSize(size, size)
        applyCountStyle(f, opts)
        applyTimerStyle(f, opts)
        f:Show()
        return f
    end
    return buildIcon(parent, size, opts)
end

--- Releases the icon back to the pool, clearing all visual state.
--- @param icon table|nil
function IconWidget.Release(icon)
    if not icon then return end
    icon:Hide()
    icon:ClearAllPoints()
    icon:SetScript("OnUpdate", nil)
    if icon.Cooldown then icon.Cooldown:Clear() end
    if icon.Text then icon.Text:SetText("") end
    if icon.Count then icon.Count:Hide() end
    if LCG and icon._glowing then
        LCG.PixelGlow_Stop(icon)
        icon._glowing = false
        icon._glowKey = nil
    end
    icon._cdStart, icon._cdDur = nil, nil
    icon._lastTimerText = nil
    icon._spellID = nil
    widgetPool[#widgetPool + 1] = icon
end

--- Applies a (cd, info) pair: texture, cooldown swipe, timer text, charge
--- count, glow. Idempotent — safe to call repeatedly with unchanged data.
--- @param icon table
--- @param cd table CooldownStore record
--- @param info table|nil SpellData entry (used for glow color)
function IconWidget.Apply(icon, cd, info)
    if not icon or not cd then return end
    local sid = cd.effectiveID or cd.spellID
    icon._spellID = sid
    if Util and Util.GetSpellIcon then
        icon.Texture:SetTexture(Util.GetSpellIcon(sid))
    end

    local hasSwipe = cd.startedAt and cd.startedAt > 0
                     and cd.duration and cd.duration > 0
    if hasSwipe then
        -- SetCooldown restarts the swipe each call. Skip when (start,dur)
        -- did not change so the animation does not loop forever.
        if icon._cdStart ~= cd.startedAt or icon._cdDur ~= cd.duration then
            icon.Cooldown:SetCooldown(cd.startedAt, cd.duration)
            icon._cdStart = cd.startedAt
            icon._cdDur = cd.duration
            icon._lastTimerText = nil
        end
        icon._timerAcc = 0
        icon:SetScript("OnUpdate", timerOnUpdate)
    else
        icon.Cooldown:Clear()
        if icon.Text then icon.Text:SetText("") end
        icon:SetScript("OnUpdate", nil)
        icon._cdStart, icon._cdDur = nil, nil
        icon._lastTimerText = nil
    end

    if icon.Count then
        if cd.maxCharges and cd.maxCharges > 1 then
            icon.Count:SetText(tostring(cd.currentCharges or 0))
            icon.Count:Show()
        else
            icon.Count:Hide()
        end
    end

    if cd.buffActive and info then
        IconWidget.StartGlow(icon, info)
    elseif icon._glowing and not cd.buffActive then
        IconWidget.StopGlow(icon)
    end
end

--- Starts a PixelGlow on the icon if one is not already active for the
--- same category. The category-keyed guard avoids LibCustomGlow re-creating
--- its texture chain on every refresh in raid.
--- @param icon table
--- @param info table SpellData entry (must carry .category)
function IconWidget.StartGlow(icon, info)
    if not (LCG and icon and info) then return end
    local key = info.category or "_default"
    if icon._glowing and icon._glowKey == key then return end
    LCG.PixelGlow_Start(icon, colorFor(info), 8, 0.25, 10, 1)
    icon._glowing = true
    icon._glowKey = key
end

--- Stops any active PixelGlow on the icon.
--- @param icon table|nil
function IconWidget.StopGlow(icon)
    if not (LCG and icon) then return end
    if icon._glowing then
        LCG.PixelGlow_Stop(icon)
        icon._glowing = false
        icon._glowKey = nil
    end
end

ns.Core.IconWidget = IconWidget
return IconWidget

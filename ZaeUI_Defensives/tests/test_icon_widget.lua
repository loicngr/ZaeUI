local fw = require("framework")
local stubs = require("wow_stubs")

-- IconWidget interacts heavily with the Blizzard frame API. The harness
-- builds a recording mock for everything it touches: every method writes
-- into the frame's `_calls` log so tests can assert what was triggered.

local makeRecordingFrame
makeRecordingFrame = function()
    local f = { _calls = {} }
    setmetatable(f, {
        __index = function(self, k)
            -- State fields (lower-case or underscored) read as nil so we
            -- never auto-stub a flag like `_glowing` into a truthy function.
            local first = type(k) == "string" and k:sub(1, 1) or ""
            if first == "" or first == "_" or first:lower() == first then
                return nil
            end
            -- Method that returns a sub-frame mock (chained reads expect a
            -- table-like result, not a function value).
            if k == "CreateTexture" or k == "CreateFontString" then
                local fn = function()
                    return makeRecordingFrame()
                end
                rawset(self, k, fn)
                return fn
            end
            -- Methods whose return value feeds into arithmetic in the SUT
            -- and therefore must be a number.
            if k == "GetFrameLevel" then
                local fn = function() return 1 end
                rawset(self, k, fn)
                return fn
            end
            -- Generic recording no-op for capitalized method names.
            local fn = function(_, ...)
                self._calls[#self._calls + 1] = { method = k, args = { ... } }
            end
            rawset(self, k, fn)
            return fn
        end,
    })
    return f
end

local function callCount(frame, method)
    local n = 0
    for _, entry in ipairs(frame._calls) do
        if entry.method == method then n = n + 1 end
    end
    return n
end

-- Builds an env with IconWidget loaded, mocked LibCustomGlow, and a counter
-- of LCG calls so tests can verify the glow-key gate.
local function buildEnv(opts)
    stubs.reset()
    opts = opts or {}

    local glowStarts, glowStops = 0, 0
    if opts.withLCG ~= false then
        _G.LibStub = function(name, silent)
            if name == "LibCustomGlow-1.0" then
                return {
                    PixelGlow_Start = function() glowStarts = glowStarts + 1 end,
                    PixelGlow_Stop  = function() glowStops  = glowStops  + 1 end,
                }
            end
            if silent then return nil end
            return nil
        end
    else
        _G.LibStub = function() return nil end
    end

    _G.CreateFrame = function()
        return makeRecordingFrame()
    end
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

    local ns = { Core = {}, Utils = {} }
    local futil = assert(loadfile("ZaeUI_Defensives/Utils/Util.lua"))
    futil("ZaeUI_Defensives", ns)

    local ficon = assert(loadfile("ZaeUI_Defensives/Core/IconWidget.lua"))
    ficon("ZaeUI_Defensives", ns)

    return {
        IconWidget = ns.Core.IconWidget,
        ns = ns,
        glowStarts = function() return glowStarts end,
        glowStops  = function() return glowStops  end,
    }
end

fw.describe("IconWidget — pool reuse", function()
    fw.it("Release then Acquire returns the same frame instance", function()
        local env = buildEnv()
        local parent = makeRecordingFrame()
        local first = env.IconWidget.Acquire(parent, 20)
        env.IconWidget.Release(first)
        local second = env.IconWidget.Acquire(parent, 20)
        fw.assertEq(second, first, "pool must hand the released frame back")
    end)

    fw.it("Release nil is a no-op", function()
        local env = buildEnv()
        env.IconWidget.Release(nil)  -- must not throw
    end)
end)

fw.describe("IconWidget — count restyle on pool reuse", function()
    fw.it("re-applies count font and anchor when a different display reacquires", function()
        local env = buildEnv()
        local parent = makeRecordingFrame()
        local f = env.IconWidget.Acquire(parent, 20, {
            countFont = "NumberFontNormal",
            countAnchor = "BOTTOMRIGHT", countOffsetX = -2, countOffsetY = 1,
        })
        env.IconWidget.Release(f)

        local before = callCount(f.Count, "SetFontObject")
        env.IconWidget.Acquire(parent, 18, {
            countFont = "NumberFontNormalSmall",
            countAnchor = "BOTTOMRIGHT", countOffsetX = -1, countOffsetY = 1,
        })
        fw.assertTrue(callCount(f.Count, "SetFontObject") > before,
                      "font must be updated when opts changes between Acquires")
    end)

    fw.it("does not re-apply font when opts are identical", function()
        local env = buildEnv()
        local parent = makeRecordingFrame()
        local opts = {
            countFont = "NumberFontNormal",
            countAnchor = "BOTTOMRIGHT", countOffsetX = -2, countOffsetY = 1,
        }
        local f = env.IconWidget.Acquire(parent, 20, opts)
        local baseline = callCount(f.Count, "SetFontObject")
        env.IconWidget.Release(f)
        env.IconWidget.Acquire(parent, 20, opts)
        fw.assertEq(callCount(f.Count, "SetFontObject"), baseline,
                    "no extra SetFontObject when font is unchanged")
    end)
end)

fw.describe("IconWidget — Apply behaviour", function()
    fw.it("calls SetCooldown once per distinct (start, duration) pair", function()
        local env = buildEnv()
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        local cd = { spellID = 642, startedAt = 100, duration = 300, currentCharges = 0, maxCharges = 1 }

        env.IconWidget.Apply(icon, cd, { category = "Personal" })
        env.IconWidget.Apply(icon, cd, { category = "Personal" })
        fw.assertEq(callCount(icon.Cooldown, "SetCooldown"), 1,
                    "second call with identical (start,dur) must skip SetCooldown")

        cd.startedAt = 200
        env.IconWidget.Apply(icon, cd, { category = "Personal" })
        fw.assertEq(callCount(icon.Cooldown, "SetCooldown"), 2,
                    "changing startedAt must restart the swipe")
    end)

    fw.it("Clears the swipe when no cooldown is active", function()
        local env = buildEnv()
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        env.IconWidget.Apply(icon, {
            spellID = 642, startedAt = 0, duration = 0,
            currentCharges = 1, maxCharges = 1,
        }, { category = "Personal" })
        fw.assertTrue(callCount(icon.Cooldown, "Clear") >= 1,
                      "Cooldown:Clear must be invoked when not on CD")
    end)

    fw.it("Shows charge count only when maxCharges > 1", function()
        local env = buildEnv()
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        env.IconWidget.Apply(icon, {
            spellID = 45438, startedAt = 1, duration = 240,
            currentCharges = 1, maxCharges = 2,
        }, { category = "Personal" })
        fw.assertTrue(callCount(icon.Count, "Show") >= 1, "Count must be shown for multi-charge")

        env.IconWidget.Apply(icon, {
            spellID = 642, startedAt = 1, duration = 300,
            currentCharges = 0, maxCharges = 1,
        }, { category = "Personal" })
        fw.assertTrue(callCount(icon.Count, "Hide") >= 1, "Count must hide for single-charge")
    end)
end)

fw.describe("IconWidget — timer text style", function()
    fw.it("uses the small default font (7px OUTLINE) when opts omit timerSize", function()
        local env = buildEnv()
        local f = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        -- The font is set via Text:SetFont(font, size, flags); inspect the
        -- last recorded SetFont call.
        local lastSize, lastFlags
        for _, e in ipairs(f.Text._calls) do
            if e.method == "SetFont" then
                lastSize, lastFlags = e.args[2], e.args[3]
            end
        end
        fw.assertEq(lastSize, 7)
        fw.assertEq(lastFlags, "OUTLINE")
    end)

    fw.it("respects timerSize override and re-applies on pool reuse", function()
        local env = buildEnv()
        local parent = makeRecordingFrame()
        local f = env.IconWidget.Acquire(parent, 20, { timerSize = 10 })
        local sizesSeen = {}
        for _, e in ipairs(f.Text._calls) do
            if e.method == "SetFont" then sizesSeen[#sizesSeen + 1] = e.args[2] end
        end
        fw.assertEq(sizesSeen[#sizesSeen], 10, "explicit timerSize must win")

        env.IconWidget.Release(f)
        env.IconWidget.Acquire(parent, 20, { timerSize = 6 })
        local last
        for _, e in ipairs(f.Text._calls) do
            if e.method == "SetFont" then last = e.args[2] end
        end
        fw.assertEq(last, 6, "re-acquire with new size re-styles the text")
    end)

    fw.it("Apply on cooldown installs the OnUpdate timer", function()
        local env = buildEnv()
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        env.IconWidget.Apply(icon, {
            spellID = 642, startedAt = 1, duration = 300,
            currentCharges = 0, maxCharges = 1,
        }, { category = "Personal" })

        local hasOnUpdate = false
        for _, e in ipairs(icon._calls) do
            if e.method == "SetScript" and e.args[1] == "OnUpdate" and type(e.args[2]) == "function" then
                hasOnUpdate = true
            end
        end
        fw.assertTrue(hasOnUpdate, "OnUpdate must be installed when on cooldown")
    end)

    fw.it("Apply with no cooldown clears the OnUpdate timer", function()
        local env = buildEnv()
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        env.IconWidget.Apply(icon, {
            spellID = 642, startedAt = 0, duration = 0,
            currentCharges = 1, maxCharges = 1,
        }, { category = "Personal" })

        -- Last SetScript call for OnUpdate must clear it (nil).
        local lastScript
        for _, e in ipairs(icon._calls) do
            if e.method == "SetScript" and e.args[1] == "OnUpdate" then
                lastScript = e.args[2]
            end
        end
        fw.assertEq(lastScript, nil, "OnUpdate must be cleared when off cooldown")
    end)
end)

fw.describe("IconWidget — glow key gate", function()
    fw.it("StartGlow on the same category twice fires LCG only once", function()
        local env = buildEnv({ withLCG = true })
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)

        env.IconWidget.StartGlow(icon, { category = "External" })
        env.IconWidget.StartGlow(icon, { category = "External" })
        fw.assertEq(env.glowStarts(), 1, "duplicate StartGlow must be deduped by category key")
    end)

    fw.it("StartGlow on a different category triggers a fresh LCG call", function()
        local env = buildEnv({ withLCG = true })
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        env.IconWidget.StartGlow(icon, { category = "External" })
        env.IconWidget.StartGlow(icon, { category = "Personal" })
        fw.assertEq(env.glowStarts(), 2, "category change must restart the glow")
    end)

    fw.it("StopGlow clears the active flag and re-enables StartGlow", function()
        local env = buildEnv({ withLCG = true })
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        env.IconWidget.StartGlow(icon, { category = "External" })
        env.IconWidget.StopGlow(icon)
        env.IconWidget.StartGlow(icon, { category = "External" })
        fw.assertEq(env.glowStarts(), 2)
        fw.assertEq(env.glowStops(), 1)
    end)

    fw.it("StopGlow without prior StartGlow is a no-op", function()
        local env = buildEnv({ withLCG = true })
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        env.IconWidget.StopGlow(icon)
        fw.assertEq(env.glowStops(), 0)
    end)
end)

fw.describe("IconWidget — Apply integrates buff/glow lifecycle", function()
    fw.it("buffActive transition triggers a single StartGlow", function()
        local env = buildEnv({ withLCG = true })
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        local cd = { spellID = 642, startedAt = 1, duration = 300,
                     currentCharges = 0, maxCharges = 1, buffActive = true }
        env.IconWidget.Apply(icon, cd, { category = "Personal" })
        env.IconWidget.Apply(icon, cd, { category = "Personal" })
        fw.assertEq(env.glowStarts(), 1, "Apply twice with same buff must not double-glow")
    end)

    fw.it("buff drop stops the glow", function()
        local env = buildEnv({ withLCG = true })
        local icon = env.IconWidget.Acquire(makeRecordingFrame(), 20)
        env.IconWidget.Apply(icon, {
            spellID = 642, startedAt = 1, duration = 300,
            currentCharges = 0, maxCharges = 1, buffActive = true,
        }, { category = "Personal" })
        env.IconWidget.Apply(icon, {
            spellID = 642, startedAt = 1, duration = 300,
            currentCharges = 0, maxCharges = 1, buffActive = false,
        }, { category = "Personal" })
        fw.assertEq(env.glowStops(), 1, "buffActive=false must stop the glow")
    end)
end)

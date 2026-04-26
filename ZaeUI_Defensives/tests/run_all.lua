-- Run with: lua ZaeUI_Defensives/tests/run_all.lua (from repo root)
package.path = "ZaeUI_Defensives/tests/helpers/?.lua;ZaeUI_Defensives/tests/?.lua;" .. package.path

io.write("ZaeUI_Defensives test suite\n")
io.write(string.rep("=", 40) .. "\n")

-- Start with a minimal list; each task below adds its file here when it
-- introduces new tests. This avoids noisy "ERROR loading" output for files
-- that don't exist yet during early development.
local testFiles = {
    "ZaeUI_Defensives/tests/test_util.lua",
    "ZaeUI_Defensives/tests/test_migration.lua",
    "ZaeUI_Defensives/tests/test_cooldown_store.lua",
    "ZaeUI_Defensives/tests/test_talent_resolver.lua",
    "ZaeUI_Defensives/tests/test_brain_matching.lua",
    "ZaeUI_Defensives/tests/test_brain_tracking.lua",
    "ZaeUI_Defensives/tests/test_brain_roster.lua",
    "ZaeUI_Defensives/tests/test_icon_widget.lua",
}

for _, path in ipairs(testFiles) do
    io.write("\n# " .. path .. "\n")
    local fn, err = loadfile(path)
    if fn then
        local ok, runErr = pcall(fn)
        if not ok then
            io.write("ERROR running " .. path .. ": " .. tostring(runErr) .. "\n")
        end
    else
        io.write("ERROR loading " .. path .. ": " .. tostring(err) .. "\n")
    end
end

local fw = require("framework")
local allPassed = fw.summary()
os.exit(allPassed and 0 or 1)

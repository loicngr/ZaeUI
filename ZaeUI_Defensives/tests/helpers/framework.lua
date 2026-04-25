-- Micro test framework, Lua 5.1 compatible.
local M = {}

local results = { passed = 0, failed = 0, failures = {} }

function M.describe(name, fn)
    io.write("\n[" .. name .. "]\n")
    fn()
end

function M.it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        results.passed = results.passed + 1
        io.write("  ok " .. name .. "\n")
    else
        results.failed = results.failed + 1
        results.failures[#results.failures + 1] = { name = name, err = err }
        io.write("  FAIL " .. name .. "\n    " .. tostring(err) .. "\n")
    end
end

function M.assertEq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "assertEq") .. ": expected " .. tostring(expected)
              .. ", got " .. tostring(actual), 2)
    end
end

function M.assertNil(v, msg)
    if v ~= nil then
        error((msg or "assertNil") .. ": expected nil, got " .. tostring(v), 2)
    end
end

function M.assertTrue(v, msg)
    if not v then
        error((msg or "assertTrue") .. ": expected truthy, got " .. tostring(v), 2)
    end
end

function M.assertClose(actual, expected, tolerance, msg)
    tolerance = tolerance or 0.001
    if math.abs(actual - expected) > tolerance then
        error((msg or "assertClose") .. ": expected ~" .. tostring(expected)
              .. " (±" .. tolerance .. "), got " .. tostring(actual), 2)
    end
end

function M.summary()
    io.write("\n" .. string.rep("=", 40) .. "\n")
    io.write("Passed: " .. results.passed .. "\n")
    io.write("Failed: " .. results.failed .. "\n")
    if results.failed > 0 then
        io.write("\nFailures:\n")
        for _, f in ipairs(results.failures) do
            io.write("  - " .. f.name .. "\n    " .. tostring(f.err) .. "\n")
        end
    end
    return results.failed == 0
end

return M

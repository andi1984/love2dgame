-- Simple test runner — run with: lua tests/run.lua (from project root)

package.path = "./?.lua;" .. package.path

local passed = 0
local failed = 0

function describe(name, fn)
    print("\n" .. name)
    fn()
end

function it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  PASS  " .. name)
    else
        failed = failed + 1
        print("  FAIL  " .. name .. "\n        " .. tostring(err))
    end
end

function expect_true(v, msg)
    if not v then error(msg or "expected true, got " .. tostring(v)) end
end

function expect_false(v, msg)
    if v then error(msg or "expected false, got " .. tostring(v)) end
end

function expect_eq(actual, expected, msg)
    if actual ~= expected then
        error(msg or string.format("expected %s, got %s", tostring(expected), tostring(actual)))
    end
end

function expect_near(actual, expected, tolerance, msg)
    if math.abs(actual - expected) > tolerance then
        error(msg or string.format("expected ~%s (tolerance %s), got %s", tostring(expected), tostring(tolerance), tostring(actual)))
    end
end

-- Load test files
require("tests.test_track")
require("tests.test_game")
require("tests.test_car")
require("tests.test_state")
require("tests.test_menu")
require("tests.test_pause")
require("tests.test_tracks")
require("tests.test_track_spline")

-- Summary
print(string.format("\n----\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

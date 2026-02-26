-- luacheck configuration for Love2D Racing Game
-- Run: luacheck .

std = "lua54"

-- Love2D injects `love` into the global environment at runtime.
-- We declare it as a global so luacheck doesn't flag accesses to love.*
globals = { "love" }

-- Suppress warnings that are idiomatic / unavoidable in Love2D projects:
--   212 – unused argument      (Love2D callbacks have fixed signatures, e.g.
--                               keypressed(key, scancode, isrepeat) even when
--                               not all args are used)
--   213 – unused loop variable (common _ pattern)
ignore = { "212", "213" }

-- ── Test infrastructure ───────────────────────────────────────────────────────
-- run.lua *defines* the helper globals consumed by every test file.
files["tests/run.lua"] = {
    globals = {
        "describe",
        "it",
        "expect_true",
        "expect_false",
        "expect_eq",
        "expect_near",
    },
}

-- Individual test files *use* those helpers (read-only from luacheck's view).
files["tests/test_*.lua"] = {
    read_globals = {
        "describe",
        "it",
        "expect_true",
        "expect_false",
        "expect_eq",
        "expect_near",
    },
}

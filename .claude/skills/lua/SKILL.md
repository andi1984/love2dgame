# Lua Development

You are an expert Lua developer. Follow these guidelines when writing or reviewing Lua code.

## Language Fundamentals

- Use `local` for all variables and functions unless a global is explicitly needed
- Prefer `local function` over `function` for module-internal functions
- Use `do ... end` blocks to limit variable scope when appropriate
- Remember: Lua arrays are 1-indexed

## Tables

- Use tables as the primary data structure for arrays, dictionaries, objects, and modules
- Prefer `{}` constructor syntax with named fields for clarity
- Use `#` operator for array length, but be aware it only works reliably for sequences (no gaps)
- Use `table.insert`, `table.remove`, and `table.sort` for array manipulation
- For dictionary-style tables, iterate with `pairs()`; for arrays, use `ipairs()`

## Metatables and OOP

- Use metatables with `__index` for prototype-based inheritance
- Define classes using a common pattern:
  ```lua
  local MyClass = {}
  MyClass.__index = MyClass

  function MyClass.new(args)
    local self = setmetatable({}, MyClass)
    -- initialize fields
    return self
  end
  ```
- Use `self` consistently as the first parameter in methods (colon syntax `:`)
- Implement `__tostring` for meaningful string representations
- Use `__newindex` sparingly and document its behavior

## Error Handling

- Use `pcall` or `xpcall` for operations that may fail
- Return `nil, error_message` pattern for expected failures
- Use `error()` with a descriptive message for programming errors
- Use `assert()` for preconditions that should never be violated
- Prefer structured error objects over plain strings for complex error handling

## Modules

- Return a table from module files
- Use the module pattern:
  ```lua
  local M = {}
  -- define functions on M
  return M
  ```
- Avoid using the deprecated `module()` function
- Keep module interfaces small and well-defined

## Performance

- Cache frequently accessed globals in locals (e.g., `local floor = math.floor`)
- Avoid creating unnecessary tables in hot loops
- Use string.format instead of concatenation (`..`) in loops
- Pre-allocate tables when the size is known using `table.move` or manual assignment
- Use LuaJIT-compatible patterns when targeting LuaJIT (avoid `goto` in some versions, prefer FFI for C interop)
- Profile before optimizing; use `os.clock()` or dedicated profilers

## Love2D Game Development

- Structure code with `love.load`, `love.update(dt)`, and `love.draw` callbacks
- Use `dt` (delta time) for frame-rate-independent movement and animation
- Separate game logic from rendering
- Use `love.graphics.push/pop` for transform state management
- Prefer `love.filesystem` over `io` for portable file access
- Use `love.audio.newSource` with "static" for short sounds and "stream" for music
- Handle input via callbacks (`love.keypressed`, `love.mousepressed`) for events, and `love.keyboard.isDown` for continuous input
- Organize game states using a state machine pattern

## Code Style

- Use 2-space or 4-space indentation consistently (match project convention)
- Use snake_case for variables and functions
- Use PascalCase for class/module names
- Add comments for non-obvious logic
- Keep functions short and focused

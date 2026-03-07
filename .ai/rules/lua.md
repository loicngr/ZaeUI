# Lua Rules - WoW Addons

## Version

Lua 5.1 only. Do not use Lua 5.2+ features (goto, native bitwise operators, etc.).

## Naming

- **Local variables**: `camelCase` (`local playerName`, `local currentScale`)
- **Local constants**: `UPPER_SNAKE_CASE` (`local MAX_SCALE = 3.0`)
- **Local functions**: `camelCase` (`local function applyScale()`)
- **Global tables/namespaces**: `PascalCase` (`NameplateScaleDB`, `ZaeUI`)
- **Table methods**: `PascalCase` (`MyAddon:OnInitialize()`)
- **Addon prefix**: Use the addon name as prefix for globals (`SLASH_NAMEPLATESSCALE1`)
- **Unused variables**: Prefix with `_` (`for _, value in pairs(t)`)

## Scope and Globals

- **Always declare `local`** except for SavedVariables and slash commands
- Minimize globals: one global table per addon when possible
- Use `local` references for frequently called WoW API functions:
  ```lua
  local CreateFrame = CreateFrame
  local GetCVar = GetCVar
  local SetCVar = SetCVar
  ```
- Never pollute the global namespace with utility functions

## Addon Structure

```lua
-- Header: addon name and short description
-- Ex: NameplateScale: Scale up the nameplate of your current target

-- 1. Local references to WoW APIs used
local CreateFrame = CreateFrame

-- 2. Constants
local ADDON_NAME = "MyAddon"
local DEFAULT_VALUE = 1.0

-- 3. Local state variables
local isInitialized = false

-- 4. Local utility functions
local function helperFunction()
end

-- 5. Main frame and event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
end)

-- 6. Slash commands (last)
SLASH_MYADDON1 = "/cmd"
SlashCmdList["MYADDON"] = function(msg)
end
```

## Comments and Documentation

- **File header**: Always include a line describing the file
  ```lua
  -- NameplateScale: Scale up the nameplate of your current target
  -- Uses the native CVar nameplateSelectedScale
  ```
- **Sections**: Separate logical sections with a comment
  ```lua
  -- Slash command handler
  ```
- **Complex functions**: Document purpose, parameters and return value
  ```lua
  --- Apply the scale value to the targeted nameplate.
  --- @param scale number The scale factor (0.5 to 3.0)
  --- @return boolean success Whether the scale was applied
  local function applyScale(scale)
  ```
- **Inline comments**: Only when the logic is not self-evident
- **Do not comment the obvious**: No `-- increment counter` for `i = i + 1`

## Event Handling

- Always `UnregisterEvent` after a one-shot event (`ADDON_LOADED`)
- Use table-based dispatch for multiple events:
  ```lua
  local events = {}
  function events:ADDON_LOADED(addonName) end
  function events:PLAYER_LOGIN() end

  frame:SetScript("OnEvent", function(self, event, ...)
      if events[event] then
          events[event](self, ...)
      end
  end)
  ```

## SavedVariables

- Always initialize with default values in `ADDON_LOADED`
- Never write to SavedVariables before `ADDON_LOADED` has fired
- Use a single table per addon (not multiple globals)
  ```lua
  if not MyAddonDB then
      MyAddonDB = { option1 = true, option2 = 1.5 }
  end
  ```

## Performance

- Do not create tables in `OnUpdate` callbacks or frequent event handlers
- Use `local` for functions called in loops
- Avoid `string.format` in hot paths, prefer simple concatenation
- Do not use `pairs()` / `ipairs()` in `OnUpdate` if avoidable
- Limit `GetCVar` / `SetCVar` calls: cache the value locally

## Error Handling

- Validate user input (slash commands) with clear messages
- Use `tonumber()` and check for `nil` before any numeric operation
- Clamp numeric values with `math.min` / `math.max` or explicit conditions
- Do not use `pcall` unless the code is genuinely likely to fail (external libs)

## In-Game Messages

- Prefix messages with the addon name in color:
  ```lua
  print("|cff00ccff[AddonName]|r Message here")
  ```
- Messages in English
- Keep messages concise and informative

## TOC File

- `Interface`: Always set to the target version (e.g. `120000` for Midnight)
- `Title`: Human-readable addon name
- `Notes`: Short description in English
- `Author`: `ZaeUI`
- `Version`: Semantic versioning (`1.0.0`)
- `SavedVariables`: Explicitly list each persisted table
- List `.lua` files in load order

## Anti-Patterns to Avoid

- Never use `getglobal()` / `setglobal()` (deprecated)
- Never use `this` (deprecated long ago)
- Never hook Blizzard functions without a valid reason
- Do not use `RunScript()` or `loadstring()` unless exceptional
- Do not create invisible frames just to receive events if a frame already exists
- Do not use `arg1`, `arg2` etc. (pre-Lua 5.1 syntax)

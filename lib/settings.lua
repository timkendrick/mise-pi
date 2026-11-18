local file = require("file")
local json = require("json")
local shell_command = require("shell_command")
local strings = require("strings")

local M = {}

--- @return string
local function script_path()
    return file.join_path(RUNTIME.pluginDirPath, "lib", "settings.mjs")
end

---@alias PackageEntry string|{source: string}

--- Returns the source of a pi settings entry.
--- @param entry PackageEntry
--- @return string
function M.entry_source(entry)
    if type(entry) == "string" then
        return entry
    end
    return entry.source
end

--- Returns the pi settings entry for an npm package, or nil when the settings do not configure the package.
--- @param name string
--- @return PackageEntry|nil
function M.get(name)
    local output = strings.trim_space(shell_command.exec({ "node", script_path(), "get", name }))
    if output == "null" then
        return nil
    end
    local entry = json.decode(output)
    if type(entry) == "string" then
        return entry
    end
    if type(entry) ~= "table" or type(entry.source) ~= "string" then
        error("invalid pi settings entry for " .. name .. ": " .. output)
    end
    return entry
end

--- Replaces the pi settings entry for an npm package, or appends it.
--- @param name string
--- @param entry_json string
function M.set(name, entry_json)
    shell_command.exec({ "node", script_path(), "set", name, entry_json })
end

return M

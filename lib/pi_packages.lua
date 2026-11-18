local file = require("file")
local json = require("json")
local shell_command = require("shell_command")
local strings = require("strings")

local M = {}

--- @return string
local function script_path()
    return file.join_path(RUNTIME.pluginDirPath, "lib", "pi_packages.mjs")
end

--- @param args string[]
--- @param cwd string
--- @return string
local function run(args, cwd)
    local argv = { "node", script_path() }
    for _, arg in ipairs(args) do
        table.insert(argv, arg)
    end
    return shell_command.exec(argv, { cwd = cwd })
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
--- @param cwd string
--- @return PackageEntry|nil
function M.get(name, cwd)
    local output = strings.trim_space(run({ "get", name }, cwd))
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

--- Installs the source of an entry with pi, then replaces the pi settings entry for the npm package.
--- @param name string
--- @param entry_json string
--- @param cwd string
function M.install(name, entry_json, cwd)
    run({ "install", name, entry_json }, cwd)
end

--- Removes an npm package from pi if its pi settings entry has the given source.
--- @param name string
--- @param source string
--- @param cwd string
function M.remove(name, source, cwd)
    run({ "remove", name, source }, cwd)
end

return M

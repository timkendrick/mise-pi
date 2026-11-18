local json = require("json")
local shell_command = require("shell_command")

local M = {}

local NAME_CHARS = "[%w%-%._~]+"

--- Raises an error unless the value is a valid npm package name, such as "pi-goal-x" or "@narumitw/pi-lsp".
--- @param name string
function M.validate_name(name)
    local unscoped = name:match("^@" .. NAME_CHARS .. "/(" .. NAME_CHARS .. ")$") or name:match("^" .. NAME_CHARS .. "$")
    if unscoped == nil or unscoped:match("^[%._]") ~= nil then
        error("invalid npm package name: '" .. name .. "'. Use pi:<name> or pi:@<scope>/<name>")
    end
end

--- Returns the pi package source that pins one version of an npm package.
--- @param name string
--- @param version string
--- @return string
function M.source(name, version)
    return "npm:" .. name .. "@" .. version
end

--- @param value any
--- @param context string
--- @return table
local function expect_table(value, context)
    if type(value) ~= "table" then
        error("unexpected npm output: " .. context .. " is not an object")
    end
    return value
end

--- Lists the published versions of an npm package, oldest first, with their release dates and dist-tags.
--- @param name string
--- @return BackendListVersionsResult
function M.list_versions(name)
    local output = shell_command.exec({ "npm", "view", name, "versions", "time", "dist-tags", "--json" })
    local ok, data = pcall(json.decode, output)
    if not ok then
        error("unexpected npm output for " .. name .. ": " .. output)
    end
    data = expect_table(data, "the package metadata")

    -- npm prints a single version as a string instead of a list
    local published = data.versions
    if type(published) == "string" then
        published = { published }
    end
    published = expect_table(published, "versions")
    local times = expect_table(data.time or {}, "time")
    local dist_tags = expect_table(data["dist-tags"] or {}, "dist-tags")

    local versions = {}
    local known = {}
    for index, version in ipairs(published) do
        if type(version) ~= "string" then
            error("unexpected npm output: versions[" .. index .. "] is not a string")
        end
        known[version] = true
        local created_at = times[version]
        if type(created_at) == "string" then
            table.insert(versions, { version = version, created_at = created_at })
        else
            table.insert(versions, version)
        end
    end
    if #versions == 0 then
        error("no versions found for " .. name)
    end

    local aliases = {}
    for tag, version in pairs(dist_tags) do
        if tag ~= "latest" and type(version) == "string" and known[version] then
            aliases[tag] = version
        end
    end

    return { versions = versions, aliases = aliases }
end

return M

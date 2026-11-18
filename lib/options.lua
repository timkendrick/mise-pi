local json = require("json")

local M = {}

--- Resource filters of a pi package entry, in the order that pi's settings schema declares them.
local RESOURCE_KEYS = { "extensions", "skills", "prompts", "themes" }

--- Generic mise tool options that can reach the plugin. The plugin ignores them.
local MISE_KEYS = {
    version = true,
    os = true,
    depends = true,
    install_env = true,
    postinstall = true,
    lazy = true,
    lazy_bins = true,
    auto_update = true,
    minimum_release_age = true,
    prerelease = true,
    version_order = true,
}

---@class PackageOptions
---@field autoload boolean|nil
---@field resources table<string, string[]> Resource filters by resource key

--- @param value any
--- @return boolean
local function parse_autoload(value)
    if value == true or value == "true" then
        return true
    elseif value == false or value == "false" then
        return false
    end
    error("option autoload must be true or false, got: " .. tostring(value))
end

--- @param key string
--- @param value any
--- @return string[]
local function parse_patterns(key, value)
    if type(value) ~= "table" then
        error("option " .. key .. " must be a list of strings, got: " .. tostring(value))
    end
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    if count ~= #value then
        error("option " .. key .. " must be a list of strings, not a table")
    end
    local patterns = {}
    for index, pattern in ipairs(value) do
        if type(pattern) ~= "string" then
            error("option " .. key .. "[" .. index .. "] must be a string, got: " .. tostring(pattern))
        end
        table.insert(patterns, pattern)
    end
    return patterns
end

--- Validates the tool options from mise.toml.
--- @param raw table|nil
--- @return PackageOptions
function M.parse(raw)
    local resource_keys = {}
    for _, key in ipairs(RESOURCE_KEYS) do
        resource_keys[key] = true
    end

    local parsed = { autoload = nil, resources = {} }
    for key, value in pairs(raw or {}) do
        if key == "autoload" then
            parsed.autoload = parse_autoload(value)
        elseif resource_keys[key] then
            parsed.resources[key] = parse_patterns(key, value)
        elseif not MISE_KEYS[key] then
            error(
                "unknown option: "
                    .. tostring(key)
                    .. ". Supported options: autoload, "
                    .. table.concat(RESOURCE_KEYS, ", ")
            )
        end
    end
    return parsed
end

--- @param patterns string[]
--- @return string
local function encode_string_list(patterns)
    local items = {}
    for _, pattern in ipairs(patterns) do
        table.insert(items, json.encode(pattern))
    end
    return "[" .. table.concat(items, ",") .. "]"
end

--- Encodes the pi settings entry for a package source.
--- The entry is the source string when there are no options, and an object with the source and options otherwise.
--- @param source string
--- @param options PackageOptions
--- @return string
function M.encode_entry(source, options)
    local fields = {}
    if options.autoload ~= nil then
        table.insert(fields, '"autoload":' .. tostring(options.autoload))
    end
    for _, key in ipairs(RESOURCE_KEYS) do
        local patterns = options.resources[key]
        if patterns ~= nil then
            table.insert(fields, json.encode(key) .. ":" .. encode_string_list(patterns))
        end
    end
    if #fields == 0 then
        return json.encode(source)
    end
    return '{"source":' .. json.encode(source) .. "," .. table.concat(fields, ",") .. "}"
end

return M

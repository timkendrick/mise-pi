local file = require("file")
local json = require("json")

local M = {}

local RECORD_FILENAME = "pi-mise.json"

---@class InstallRecord
---@field source string Package source as written to the pi settings, such as "npm:pi-goal-x@0.34.1"

--- @param install_path string
--- @return string
local function record_path(install_path)
    return file.join_path(install_path, RECORD_FILENAME)
end

--- @param install_path string
--- @param record InstallRecord
function M.write(install_path, record)
    local path = record_path(install_path)
    local handle, err = io.open(path, "w")
    if handle == nil then
        error("could not write " .. path .. ": " .. tostring(err))
    end
    handle:write(json.encode({ source = record.source }))
    handle:close()
end

--- Reads the record of an install, or returns nil when the install did not complete.
--- @param install_path string
--- @return InstallRecord|nil
function M.read(install_path)
    local path = record_path(install_path)
    if not file.exists(path) then
        return nil
    end
    local ok, value = pcall(json.decode, file.read(path))
    if not ok or type(value) ~= "table" or type(value.source) ~= "string" then
        error("invalid install record: " .. path)
    end
    return { source = value.source }
end

return M

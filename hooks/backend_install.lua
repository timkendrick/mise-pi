local file = require("file")
local log = require("log")
local install_record = require("install_record")
local npm_package = require("npm_package")
local options = require("options")
local pi_packages = require("pi_packages")
local shell_command = require("shell_command")

--- @param path string
--- @return string
local function parent_dir(path)
    local parent = path:match("^(.*)/[^/]+/*$")
    if parent == nil or parent == "" then
        error("path has no parent directory: " .. path)
    end
    return parent
end

--- Returns true when a mise install of this tool wrote the settings entry.
--- @param entry PackageEntry
--- @param name string
--- @param install_path string
--- @return boolean
local function written_by_mise(entry, name, install_path)
    local source = pi_packages.entry_source(entry)
    local prefix = "npm:" .. name .. "@"
    if source:sub(1, #prefix) ~= prefix then
        return false
    end
    local version = source:sub(#prefix + 1)
    if version == "" or version:find("/", 1, true) ~= nil then
        return false
    end
    local record = install_record.read(file.join_path(parent_dir(install_path), version))
    return record ~= nil and record.source == source
end

--- @param entry PackageEntry
--- @return string
local function describe_entry(entry)
    if type(entry) == "string" then
        return entry
    end
    return entry.source .. " with resource filters"
end

--- Installs a pi package from npm with pi, and writes the options from mise.toml to its pi settings entry.
--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx)
    local name = ctx.tool
    npm_package.validate_name(name)
    local source = npm_package.source(name, ctx.version)
    local entry_json = options.encode_entry(source, options.parse(ctx.options))

    shell_command.make_dir(ctx.install_path)
    local existing = pi_packages.get(name, ctx.install_path)
    if existing ~= nil and not written_by_mise(existing, name, ctx.install_path) then
        log.warn(
            name
                .. " was configured in the pi settings as "
                .. describe_entry(existing)
                .. "; replacing it with pi:"
                .. name
                .. "@"
                .. ctx.version
        )
    end

    pi_packages.install(name, entry_json, ctx.install_path)
    install_record.write(ctx.install_path, { source = source })
    return {}
end

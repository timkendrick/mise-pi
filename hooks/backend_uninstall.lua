local install_record = require("install_record")
local settings = require("settings")
local shell_command = require("shell_command")

--- Removes the package from pi when the pi settings still use the version that mise removes.
--- @param ctx BackendUninstallCtx
function PLUGIN:BackendUninstall(ctx)
    local record = install_record.read(ctx.install_path)
    if record == nil then
        return
    end
    local existing = settings.get(ctx.tool)
    if existing ~= nil and settings.entry_source(existing) == record.source then
        shell_command.exec({ "pi", "remove", "npm:" .. ctx.tool }, { cwd = ctx.install_path })
    end
end

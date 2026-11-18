local install_record = require("install_record")
local pi_packages = require("pi_packages")

--- Removes the package from pi when the pi settings still use the version that mise removes.
--- @param ctx BackendUninstallCtx
function PLUGIN:BackendUninstall(ctx)
    local record = install_record.read(ctx.install_path)
    if record == nil then
        return
    end
    pi_packages.remove(ctx.tool, record.source, ctx.install_path)
end

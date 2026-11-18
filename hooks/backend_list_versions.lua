local npm_package = require("npm_package")

--- Lists the published versions of a pi package on npm.
--- @param ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx)
    npm_package.validate_name(ctx.tool)
    return npm_package.list_versions(ctx.tool)
end

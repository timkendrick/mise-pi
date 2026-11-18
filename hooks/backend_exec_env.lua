--- pi packages add nothing to the shell environment.
--- @param ctx BackendExecEnvCtx
--- @return BackendExecEnvResult
function PLUGIN:BackendExecEnv(ctx)
    return { env_vars = {} }
end

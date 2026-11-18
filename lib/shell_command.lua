local cmd = require("cmd")

local M = {}

--- Quotes a value as a single POSIX shell word.
--- @param value string
--- @return string
function M.quote(value)
    return "'" .. (string.gsub(value, "'", "'\\''")) .. "'"
end

--- Quotes each argument and joins them into a POSIX shell command line.
--- @param argv string[]
--- @return string
function M.join(argv)
    local words = {}
    for _, arg in ipairs(argv) do
        table.insert(words, M.quote(arg))
    end
    return table.concat(words, " ")
end

--- Runs a command and returns its stdout.
--- On failure, the error message includes both stdout and stderr.
--- @param argv string[]
--- @param opts? CmdExecOpts
--- @return string
function M.exec(argv, opts)
    local wrapped = "if output=$("
        .. M.join(argv)
        .. "); then printf '%s\\n' \"$output\"; "
        .. 'else status=$?; printf \'%s\\n\' "$output" >&2; exit "$status"; fi'
    return cmd.exec(wrapped, opts or {})
end

--- Creates a directory and its parent directories if they do not exist.
--- @param path string
function M.make_dir(path)
    cmd.exec("mkdir -p " .. M.quote(path))
end

return M

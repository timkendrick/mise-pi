PLUGIN = { -- luacheck: ignore
    name = "pi",
    version = "0.1.0",
    description = "Install pi coding agent packages from npm and register them in the pi settings",
    author = "Tim Kendrick",
    license = "MIT",
    homepage = "https://github.com/timkendrick/mise-pi",
    depends = { "node", "npm:@earendil-works/pi-coding-agent" },
}

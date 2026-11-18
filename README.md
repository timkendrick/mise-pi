# mise-pi

A [mise](https://mise.jdx.dev) backend plugin that manages [pi](https://pi.dev) packages declaratively.

Declare pi packages in `mise.toml` instead of running `pi install` by hand:

```toml
[tools]
"npm:@earendil-works/pi-coding-agent" = "latest"
"pi:pi-goal-x" = "latest"
"pi:@narumitw/pi-lsp" = "0.49.12"
"pi:pi-web-search" = { version = "latest", skills = [] }
"pi:@narumitw/pi-caffeinate" = { version = "latest", autoload = false }
```

mise installs each package with `pi install` and writes its entry to the pi settings. The options on each tool entry become the [resource filters](https://pi.dev/docs/packages) of the package.

## Install the plugin

```sh
mise plugin install pi https://github.com/timkendrick/mise-pi
```

Each pi package is then available as `pi:<npm package>`, such as `pi:pi-goal-x` or `pi:@narumitw/pi-lsp`. The plugin supports npm packages only.

### The pi CLI tool name

When this plugin is installed as `pi`, mise reads the bare tool name `pi` as a reference to the plugin, not to the pi CLI.

Install the CLI with its full backend name instead:

```toml
[tools]
# Before
pi = "latest"

# After
"npm:@earendil-works/pi-coding-agent" = "latest"
```

The plugin runs `pi` and `node` to install packages and to edit the pi settings. If `node` and `"npm:@earendil-works/pi-coding-agent"` are in your config, mise installs them first and puts them on `PATH` for the plugin. Otherwise the plugin uses the `pi` and `node` on your `PATH`. Version listing runs `npm`, which must be on your `PATH`.

## Versions

The plugin uses the published npm versions of the package.

| mise version | Installs |
| --- | --- |
| `0.34.1` | The version `0.34.1` |
| `0.34` | The newest published `0.34.x` version |
| `latest` | The newest published version |
| `next` | The version that the npm dist-tag `next` points at |

`mise ls-remote pi:<package>` lists the versions, oldest first. Each version has its npm release date, so [`minimum_release_age`](https://mise.jdx.dev/configuration/settings.html#minimum_release_age) works.

The dist-tags of the package, such as `next` or `beta`, are available as version aliases. The `latest` dist-tag is an exception: mise resolves `latest` to the newest published version.

## Options

The options of a tool entry configure which resources pi loads from the package. They have the same names and meanings as the fields of the [object form](https://pi.dev/docs/packages) of a pi package entry.

| Option | Type | Effect |
| --- | --- | --- |
| `extensions` | list of patterns | Load only the matching extensions |
| `skills` | list of patterns | Load only the matching skills |
| `prompts` | list of patterns | Load only the matching prompt templates |
| `themes` | list of patterns | Load only the matching themes |
| `autoload` | `true` or `false` | With `false`, load only the resources that the patterns select |

For each resource type:

- Leave out the option to load all resources of that type.
- Use `[]` to load no resources of that type.
- Use `!pattern` to exclude glob matches.
- Use `+path` to include one exact path.
- Use `-path` to exclude one exact path.

To disable a package but keep it installed, set `autoload = false` and leave out the resource options.

The plugin rejects unknown options and invalid values, for example `skill = []` instead of `skills = []`. Generic mise tool options, such as `postinstall` and `minimum_release_age`, are allowed.

### Example

This `mise.toml` entry:

```toml
[tools]
"pi:pi-web-search" = { version = "1.7.0", skills = [], extensions = ["extensions/*.ts", "!extensions/legacy.ts"] }
```

writes this entry to the `packages` list of the pi settings:

```json
{
  "source": "npm:pi-web-search@1.7.0",
  "extensions": ["extensions/*.ts", "!extensions/legacy.ts"],
  "skills": []
}
```

Without options, the entry is the source string, such as `"npm:pi-web-search@1.7.0"`.

## How install works

For `"pi:pi-web-search" = { version = "1.7.0", skills = [] }`, install does these steps:

1. Validate the package name and the options.
2. Read the current pi settings entry of the package. If the entry exists and mise did not write it, show a warning.
3. Run `pi install npm:pi-web-search@1.7.0`. pi installs the package into its package directory, `~/.pi/agent/npm`, and pins the version in its settings.
4. Replace the settings entry of the package with the entry for the options. The entry keeps its position in the `packages` list.
5. Write `pi-mise.json` in the mise install directory. This file records the settings source for uninstall.

The plugin edits the pi settings file at `$PI_CODING_AGENT_DIR/settings.json`, or at `~/.pi/agent/settings.json` when `PI_CODING_AGENT_DIR` is not set. It takes the same lock as pi while it edits the file. It keeps the other settings and their key order.

pi installs all packages into one npm directory and one settings file. mise installs tools in parallel, so the plugin runs steps 3 and 4 for one package at a time. Uninstall runs `pi remove` under the same lock. The lock is the directory `mise-pi.lock` in the pi agent directory. If the process that holds the lock stops, the next install removes the lock.

### Replace an existing entry

pi has one settings entry for each npm package. If the pi settings already configure the package, install replaces the entry and shows a warning such as:

```text
pi-web-search was configured in the pi settings as npm:pi-web-search; replacing it with pi:pi-web-search@1.7.0
```

To move a package from `pi install` to mise, add it to `mise.toml` and run `mise install`.

There is no warning when install replaces the entry of another mise install of the same tool, for example during `mise upgrade`.

## How uninstall works

`mise uninstall`, `mise upgrade` and `mise prune` run `pi remove`, but only if the pi settings still pin the version that mise removes. For example, `mise upgrade` installs the new version first. Then it removes the old version, and pi keeps the new version.

If you remove a package from `mise.toml`, run `mise prune` to remove it from pi.

## Limitations

- **Option changes:** mise does not install a version again when its options change. Run `mise install --force pi:<package>` to write the new options to the pi settings.
- **One version for each package:** pi installs one version of each package. If `mise.toml` requests more than one version of a package, the version that mise installs last is active in pi.
- **Changes in pi:** mise does not detect changes that you make with the pi CLI or `pi config`. If you run `pi remove`, run `mise install --force pi:<package>` to install the package again.
- **Updates in pi:** pi does not update pinned versions, so `pi update --extensions` does not change packages that mise installs. Use `mise upgrade` instead.
- **User settings only:** the plugin writes to the user settings of pi. It does not write project settings in `.pi/settings.json`.

## Platforms

The plugin supports macOS and Linux. It needs `pi`, `node` and `npm`. Windows is not supported.

## Development

Link your working copy:

```sh
mise plugin link --force pi .
```

| Task | Description |
| --- | --- |
| `mise run test` | Install, upgrade and remove real pi packages from npm in an isolated mise and pi setup |
| `mise run lint` | Check formatting, types, the node script, the test script and GitHub Actions workflows |
| `mise run ci` | Run all checks |

The test uses a temporary `PI_CODING_AGENT_DIR`, so it does not change your pi setup. It needs network access, `node`, `npm`, `pi` and `jq`. Use `mise run test -- --keep` to keep the temporary directory.

## License

MIT

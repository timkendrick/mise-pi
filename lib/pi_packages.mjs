#!/usr/bin/env node
// Installs and removes npm packages with pi, and edits their entries in the pi settings file.
// Concurrent installs and removals run one at a time, because pi shares one npm directory and one settings file.
// Settings edits take the same lock as pi, keep the key order of the file, and write it in the format that pi uses.

import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const USAGE = `Usage: pi_packages.mjs <command> [arguments...]

Commands:
  get <name>                   Print the pi settings entry for an npm package as JSON, or null
  install <name> <entry-json>  Install the source of the entry with pi install, then write the entry
  remove <name> <source>       Remove the package with pi remove if its entry has the given source

The settings file is $PI_CODING_AGENT_DIR/settings.json (default: ~/.pi/agent/settings.json).`;

const SETTINGS_LOCK = { staleMs: 10_000, timeoutMs: 30_000 };
const PACKAGES_LOCK = { staleMs: 10_000, timeoutMs: 30 * 60_000 };
const LOCK_RETRY_MS = 50;
const LOCK_OWNER_FILENAME = "pid";

class UsageError extends Error {}

function agentDir() {
  const configured = process.env.PI_CODING_AGENT_DIR;
  return configured ? expandHome(configured) : join(homedir(), ".pi", "agent");
}

function settingsPath() {
  return join(agentDir(), "settings.json");
}

function expandHome(path) {
  if (path === "~") return homedir();
  if (path.startsWith("~/")) return join(homedir(), path.slice(2));
  return path;
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function ageMs(path) {
  try {
    return Date.now() - statSync(path).mtimeMs;
  } catch (error) {
    if (error.code === "ENOENT") return 0;
    throw error;
  }
}

function isAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

// Runs fn while this process holds the lock directory at lockPath.
// isStale decides whether another holder of the lock is gone, so that its lock can be removed.
function withLock(lockPath, { timeoutMs, isStale, onAcquired }, fn) {
  const deadline = Date.now() + timeoutMs;
  mkdirSync(dirname(lockPath), { recursive: true });
  for (;;) {
    try {
      mkdirSync(lockPath);
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      if (isStale(lockPath)) {
        rmSync(lockPath, { recursive: true, force: true });
        continue;
      }
      if (Date.now() > deadline) {
        throw new Error(`timed out waiting for the lock ${lockPath}`);
      }
      sleep(LOCK_RETRY_MS);
    }
  }
  try {
    onAcquired?.(lockPath);
    return fn();
  } finally {
    rmSync(lockPath, { recursive: true, force: true });
  }
}

// pi locks the settings file with proper-lockfile, which creates the directory "<file>.lock".
// proper-lockfile treats a lock as stale when its modification time is older than its stale interval.
function withSettingsLock(path, fn) {
  return withLock(
    `${path}.lock`,
    { timeoutMs: SETTINGS_LOCK.timeoutMs, isStale: (lockPath) => ageMs(lockPath) > SETTINGS_LOCK.staleMs },
    fn,
  );
}

// An install can take minutes, so this lock records its owner and is stale only when the owner process is gone.
function withPackagesLock(fn) {
  const ownerPath = (lockPath) => join(lockPath, LOCK_OWNER_FILENAME);
  return withLock(
    join(agentDir(), "mise-pi.lock"),
    {
      timeoutMs: PACKAGES_LOCK.timeoutMs,
      isStale: (lockPath) => {
        const pid = readOwner(ownerPath(lockPath));
        return pid === undefined ? ageMs(lockPath) > PACKAGES_LOCK.staleMs : !isAlive(pid);
      },
      onAcquired: (lockPath) => writeFileSync(ownerPath(lockPath), String(process.pid)),
    },
    fn,
  );
}

function readOwner(path) {
  try {
    const pid = Number.parseInt(readFileSync(path, "utf8"), 10);
    return Number.isNaN(pid) ? undefined : pid;
  } catch (error) {
    if (error.code === "ENOENT") return undefined;
    throw error;
  }
}

function readSettings(path) {
  if (!existsSync(path)) return {};
  const text = readFileSync(path, "utf8");
  if (text.trim() === "") return {};
  const settings = JSON.parse(text);
  if (settings === null || typeof settings !== "object" || Array.isArray(settings)) {
    throw new Error(`${path} does not contain a JSON object`);
  }
  return settings;
}

function writeSettings(path, settings) {
  const target = existsSync(path) ? realpathSync(path) : path;
  mkdirSync(dirname(target), { recursive: true });
  const temporary = `${target}.mise-pi-${process.pid}.tmp`;
  writeFileSync(temporary, JSON.stringify(settings, null, 2));
  renameSync(temporary, target);
}

function entrySource(entry) {
  if (typeof entry === "string") return entry;
  if (entry !== null && typeof entry === "object" && typeof entry.source === "string") return entry.source;
  return undefined;
}

// Returns the package name of an npm source, such as "@scope/name" for "npm:@scope/name@1.0.0".
function npmPackageName(source) {
  if (source === undefined || !source.startsWith("npm:")) return undefined;
  const spec = source.slice("npm:".length).trim();
  const versionSeparator = spec.indexOf("@", spec.startsWith("@") ? 1 : 0);
  return versionSeparator === -1 ? spec : spec.slice(0, versionSeparator);
}

function packageEntries(settings, path) {
  const packages = settings.packages ?? [];
  if (!Array.isArray(packages)) {
    throw new Error(`packages in ${path} is not a list`);
  }
  return packages;
}

function getEntry(name) {
  const path = settingsPath();
  return withSettingsLock(path, () => {
    const packages = packageEntries(readSettings(path), path);
    return packages.find((entry) => npmPackageName(entrySource(entry)) === name) ?? null;
  });
}

function setEntry(name, entry) {
  const path = settingsPath();
  withSettingsLock(path, () => {
    const settings = readSettings(path);
    const packages = [];
    let replaced = false;
    for (const existing of packageEntries(settings, path)) {
      if (npmPackageName(entrySource(existing)) !== name) {
        packages.push(existing);
      } else if (!replaced) {
        packages.push(entry);
        replaced = true;
      }
    }
    if (!replaced) packages.push(entry);
    settings.packages = packages;
    writeSettings(path, settings);
  });
}

function runPi(args) {
  const result = spawnSync("pi", args, { stdio: ["ignore", "inherit", "inherit"] });
  if (result.error) {
    throw new Error(`could not run pi ${args.join(" ")}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`pi ${args.join(" ")} failed with exit status ${result.status ?? result.signal}`);
  }
}

function install(name, entryJson) {
  const entry = JSON.parse(entryJson);
  const source = entrySource(entry);
  if (npmPackageName(source) !== name) {
    throw new Error(`the entry ${entryJson} is not an npm source for ${name}`);
  }
  withPackagesLock(() => {
    runPi(["install", source]);
    setEntry(name, entry);
  });
}

function remove(name, source) {
  withPackagesLock(() => {
    const entry = getEntry(name);
    if (entry !== null && entrySource(entry) === source) {
      runPi(["remove", `npm:${name}`]);
    }
  });
}

function main(argv) {
  const [command, ...args] = argv;
  if (command === "--help" || command === "-h") {
    console.log(USAGE);
    return;
  }
  if (command === "get" && args.length === 1) {
    console.log(JSON.stringify(getEntry(args[0])));
    return;
  }
  if (command === "install" && args.length === 2) {
    install(args[0], args[1]);
    return;
  }
  if (command === "remove" && args.length === 2) {
    remove(args[0], args[1]);
    return;
  }
  throw new UsageError(`invalid arguments: ${argv.join(" ")}`);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(`pi_packages.mjs: ${error.message}`);
  if (error instanceof UsageError) console.error(USAGE);
  process.exit(1);
}

#!/usr/bin/env node
// Reads and updates the npm package entries in the pi settings file.
// Takes the same lock as pi, keeps the key order of the file, and writes it in the format that pi uses.

import { existsSync, mkdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const USAGE = `Usage: settings.mjs <command> [arguments...]

Commands:
  get <name>                 Print the pi settings entry for an npm package as JSON, or null
  set <name> <entry-json>    Replace the pi settings entry for an npm package, or append it

The settings file is $PI_CODING_AGENT_DIR/settings.json (default: ~/.pi/agent/settings.json).`;

const LOCK_STALE_MS = 10_000;
const LOCK_TIMEOUT_MS = 30_000;
const LOCK_RETRY_MS = 50;

class UsageError extends Error {}

function settingsPath() {
  const configured = process.env.PI_CODING_AGENT_DIR;
  const agentDir = configured ? expandHome(configured) : join(homedir(), ".pi", "agent");
  return join(agentDir, "settings.json");
}

function expandHome(path) {
  if (path === "~") return homedir();
  if (path.startsWith("~/")) return join(homedir(), path.slice(2));
  return path;
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// pi locks the settings file with proper-lockfile, which creates the directory "<file>.lock".
function withLock(path, fn) {
  const lockPath = `${path}.lock`;
  const deadline = Date.now() + LOCK_TIMEOUT_MS;
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
    return fn();
  } finally {
    rmSync(lockPath, { recursive: true, force: true });
  }
}

function isStale(lockPath) {
  try {
    return Date.now() - statSync(lockPath).mtimeMs > LOCK_STALE_MS;
  } catch (error) {
    if (error.code === "ENOENT") return false;
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
  return withLock(path, () => {
    const packages = packageEntries(readSettings(path), path);
    return packages.find((entry) => npmPackageName(entrySource(entry)) === name) ?? null;
  });
}

function setEntry(name, entryJson) {
  const entry = JSON.parse(entryJson);
  if (npmPackageName(entrySource(entry)) !== name) {
    throw new Error(`the entry ${entryJson} is not an npm source for ${name}`);
  }
  const path = settingsPath();
  withLock(path, () => {
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
  if (command === "set" && args.length === 2) {
    setEntry(args[0], args[1]);
    return;
  }
  throw new UsageError(`invalid arguments: ${argv.join(" ")}`);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(`settings.mjs: ${error.message}`);
  if (error instanceof UsageError) console.error(USAGE);
  process.exit(1);
}

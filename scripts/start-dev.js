"use strict";

const path = require("path");
const fs = require("fs");
const net = require("net");
const { spawn, execSync } = require("child_process");
const chokidar = require("chokidar");

const MOCK_PORT = 4301;

function isPortInUse(port) {
  return new Promise((resolve) => {
    const s = net.createConnection(port, "127.0.0.1");
    s.on("connect", () => {
      s.destroy();
      resolve(true);
    });
    s.on("error", () => resolve(false));
  });
}

const rootDir = path.resolve(__dirname, "..");
const envLocalPath = path.join(rootDir, ".env.local");

function loadEnvLocal() {
  const env = {};
  if (!fs.existsSync(envLocalPath)) return env;
  const raw = fs.readFileSync(envLocalPath, "utf8");
  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim().replace(/^["']|["']$/g, "");
    env[key] = value;
  }
  return env;
}

function run(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, {
      cwd: rootDir,
      stdio: "inherit",
      shell: false,
      ...opts,
    });
    child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`exit ${code}`))));
    child.on("error", reject);
  });
}

function runAsync(cmd, args, opts = {}) {
  const child = spawn(cmd, args, {
    cwd: rootDir,
    stdio: opts.stdio ?? "inherit",
    shell: false,
    ...opts,
  });
  return child;
}

function buildHelper() {
  const buildEnv = { ...process.env, KEEP_LOG: "1" };
  return run("node", ["scripts/build-dist.js"], { env: buildEnv }).then(() => run("node", ["scripts/inject-env.js", "local"]));
}

let mockProcess = null;
let swiftProcess = null;

function startMock() {
  if (mockProcess) {
    mockProcess.kill("SIGTERM");
    mockProcess = null;
  }
  isPortInUse(MOCK_PORT).then((inUse) => {
    if (inUse) {
      console.log("[start-dev] Mock server already running on port " + MOCK_PORT + ".");
      return;
    }
    const env = { ...process.env, ...loadEnvLocal() };
    console.log("[start-dev] Starting mock KOT server on port " + MOCK_PORT + "...");
    mockProcess = runAsync("node", [path.join(rootDir, "scripts", "serve-mock.js")], { env: { ...env, MOCK_PORT: String(MOCK_PORT) }, stdio: "inherit" });
    mockProcess.on("exit", (code) => {
      if (mockProcess && code !== 0) {
        console.log("[start-dev] Mock server exited: " + code);
        if (code === 1) {
          isPortInUse(MOCK_PORT).then((inUse) => {
            if (inUse) console.log("[start-dev] Port " + MOCK_PORT + " is in use — mock server may already be running.");
          });
        }
      }
      mockProcess = null;
    });
  });
}

function stopSwift() {
  return new Promise((resolve) => {
    if (!swiftProcess) {
      resolve();
      return;
    }
    const p = swiftProcess;
    swiftProcess = null;
    p.once("exit", () => resolve());
    p.kill("SIGTERM");
    setTimeout(() => resolve(), 5000);
  });
}

function getSwiftBuildBinPath() {
  try {
    const out = execSync("swift build -c debug --show-bin-path", {
      encoding: "utf8",
      cwd: rootDir,
    }).trim();
    return out || null;
  } catch {
    return null;
  }
}

function copyLocalizationToBuildDir() {
  const locDir = path.join(rootDir, "Localization");
  const buildDir = getSwiftBuildBinPath();
  if (!fs.existsSync(locDir) || !buildDir || !fs.existsSync(buildDir)) return;
  try {
    const dirs = fs.readdirSync(locDir).filter((n) => n.endsWith(".lproj"));
    for (const name of dirs) {
      const src = path.join(locDir, name);
      const dest = path.join(buildDir, name);
      if (!fs.statSync(src).isDirectory()) continue;
      if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
      for (const f of fs.readdirSync(src)) {
        fs.copyFileSync(path.join(src, f), path.join(dest, f));
      }
    }
  } catch (e) {
    console.warn("[start-dev] Could not copy localization:", e.message);
  }
}

function startSwift() {
  copyLocalizationToBuildDir();
  const swiftEnv = { ...process.env, ...loadEnvLocal() };
  console.log("[start-dev] Running Swift app (KOT_BASE_URL from .env.local)...");
  swiftProcess = runAsync("swift", ["run", "JokerOfTime"], { env: swiftEnv });
  swiftProcess.on("exit", (code) => {
    if (swiftProcess) console.log("[start-dev] Swift app exited:", code);
    swiftProcess = null;
  });
}

function restartSwift() {
  stopSwift().then(() => startSwift());
}

function debounce(fn, ms) {
  let t;
  return () => {
    clearTimeout(t);
    t = setTimeout(fn, ms);
  };
}

function main() {
  console.log("[start-dev] Building helper and injecting local env...");
  buildHelper()
    .then(async () => {
      if (!fs.existsSync(path.join(rootDir, ".dev", "cli.js"))) {
        console.error("[start-dev] Helper build failed: .dev/cli.js not found");
        process.exit(1);
      }
      const timecardPath = path.join(rootDir, "mock-site", "timecard.html");
      if (!fs.existsSync(timecardPath)) {
        console.log("[start-dev] Generating mock timecard (run 'yarn timecard <state>' to change state)...");
        await run("node", ["scripts/prep-mock-timecard.js", "working-not-clocked-in"]).catch(() => {});
      }
      startMock();
      await run("swift", ["build", "-c", "debug"]).catch(() => {});
      setTimeout(() => startSwift(), 800);

      // Swift rebuild is triggered only when tmp/swift-rebuild.trigger is touched (e.g. after you finish editing Sources/).
      const triggerDir = path.join(rootDir, "tmp");
      const swiftRebuildTrigger = path.join(triggerDir, "swift-rebuild.trigger");
      if (!fs.existsSync(triggerDir)) fs.mkdirSync(triggerDir, { recursive: true });
      fs.writeFileSync(swiftRebuildTrigger, new Date().toISOString() + "\n", "utf8");

      const DEBOUNCE_MS = 2000;

      const onTriggerChange = () => {
        console.log("[start-dev] Swift rebuild trigger — stopping Swift app, then starting new one.");
        restartSwift();
      };

      const onSrcChange = debounce(() => {
        console.log("[start-dev] src/ changed — rebuilding helper, stopping Swift app, then starting new one.");
        buildHelper()
          .then(() => restartSwift())
          .catch((err) => console.error("[start-dev]", err.message));
      }, DEBOUNCE_MS);

      chokidar
        .watch(swiftRebuildTrigger, { ignoreInitial: true })
        .on("all", () => onTriggerChange());

      chokidar
        .watch(path.join(rootDir, "src"), { ignoreInitial: true })
        .on("all", () => onSrcChange());

      // Don't watch mock-site: the server serves files from disk, so edits are reflected on the next request without restarting.
      console.log("[start-dev] Swift restart: only on touch tmp/swift-rebuild.trigger. Also watching src/.");
    })
    .catch((err) => {
      console.error("[start-dev]", err.message);
      process.exit(1);
    });
}

function cleanup() {
  if (mockProcess) {
    mockProcess.kill("SIGTERM");
    mockProcess = null;
  }
  if (swiftProcess) {
    swiftProcess.kill("SIGTERM");
    swiftProcess = null;
  }
  process.exit(0);
}

process.on("SIGINT", cleanup);
process.on("SIGTERM", cleanup);

main();

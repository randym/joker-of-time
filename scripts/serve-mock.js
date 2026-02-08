#!/usr/bin/env node
/**
 * Serves mock-site and provides POST /mock-api/clock-in and /mock-api/clock-out
 * that regenerate timecard.html so the mock stays in sync when you punch.
 * Dev only; production automation (clock.ts) never touches this.
 */
const http = require("http");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const PORT = parseInt(process.env.MOCK_PORT || "4301", 10);
const ROOT = path.join(__dirname, "..", "mock-site");
const PREP_SCRIPT = path.join(__dirname, "prep-mock-timecard.js");
const CLOCK_STATE_PATH = path.join(ROOT, ".clock-state.json");

function nowHHmm() {
  const d = new Date();
  return (
    String(d.getHours()).padStart(2, "0") +
    ":" +
    String(d.getMinutes()).padStart(2, "0")
  );
}

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css",
  ".js": "application/javascript",
  ".json": "application/json",
  ".ico": "image/x-icon",
  ".png": "image/png",
};

function serveFile(filePath, res) {
  const ext = path.extname(filePath);
  const mime = MIME[ext] || "application/octet-stream";
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { "Content-Type": mime });
    res.end(data);
  });
}

function runPrep(state, startHHmm, endHHmm) {
  const args = [PREP_SCRIPT, state];
  if (startHHmm) args.push(startHHmm);
  if (endHHmm) args.push(endHHmm);
  const result = spawnSync("node", args, {
    cwd: path.join(__dirname, ".."),
    encoding: "utf8",
  });
  return result.status === 0;
}

const server = http.createServer((req, res) => {
  if (req.method === "POST" && req.url === "/mock-api/clock-in") {
    const start = nowHHmm();
    try {
      fs.writeFileSync(CLOCK_STATE_PATH, JSON.stringify({ clockInTime: start }), "utf8");
    } catch (_) {}
    runPrep("clocked-in", start);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, state: "clocked-in", clockInTime: start }));
    return;
  }
  if (req.method === "POST" && req.url === "/mock-api/clock-out") {
    let start = null;
    try {
      const raw = fs.readFileSync(CLOCK_STATE_PATH, "utf8");
      const data = JSON.parse(raw);
      start = data.clockInTime || null;
    } catch (_) {}
    const end = nowHHmm();
    runPrep("clocked-out", start || undefined, end);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, state: "clocked-out", clockOutTime: end }));
    return;
  }
  if (req.method === "POST" && req.url === "/mock-api/reset") {
    runPrep("working-not-clocked-in");
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, state: "working-not-clocked-in" }));
    return;
  }

  const pathname = req.url.split("?")[0].split("#")[0];
  let filePath = path.join(ROOT, pathname === "/" ? "index.html" : pathname.replace(/^\//, ""));
  if (!path.extname(filePath)) filePath = path.join(filePath, "index.html");
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403);
    res.end();
    return;
  }
  serveFile(filePath, res);
});

server.listen(PORT, "127.0.0.1", () => {
  console.log("[serve-mock] Mock KOT at http://127.0.0.1:" + PORT);
  console.log("[serve-mock] POST /mock-api/clock-in, /mock-api/clock-out, /mock-api/reset to update timecard state.");
});

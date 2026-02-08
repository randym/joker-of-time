#!/usr/bin/env node
/**
 * Injects env vars from .env.<environment> (at repo root) into dist at build time.
 * Values are hard-coded so the app does not need dotenv at runtime.
 * Usage: node scripts/inject-env.js <environment>   (e.g. production | local)
 */
const fs = require("fs");
const path = require("path");

const envName = process.argv[2] || "production";
const rootDir = path.resolve(path.dirname(__filename), "..");
const envFile = path.join(rootDir, `.env.${envName}`);
const distDir = process.env.DIST_DIR
  ? path.resolve(rootDir, process.env.DIST_DIR)
  : path.join(rootDir, ".dev");

if (!fs.existsSync(envFile)) {
  console.error(`Missing env file: ${envFile}`);
  process.exit(1);
}

const raw = fs.readFileSync(envFile, "utf8");
const vars = {};
for (const line of raw.split("\n")) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#")) continue;
  const eq = trimmed.indexOf("=");
  if (eq === -1) continue;
  const key = trimmed.slice(0, eq).trim();
  const value = trimmed.slice(eq + 1).trim().replace(/^["']|["']$/g, "");
  vars[key] = value;
}

const KOT_BASE_URL = vars.KOT_BASE_URL ?? "https://s3.ta.kingoftime.jp/independent/recorder2/personal/";
const KOT_HEADLESS = vars.KOT_HEADLESS ?? "";

const replacements = [
  [/\bprocess\.env\.KOT_BASE_URL\b/g, JSON.stringify(KOT_BASE_URL)],
  [/\bprocess\.env\.KOT_HEADLESS\b/g, JSON.stringify(KOT_HEADLESS)],
];

for (const name of ["cli.js"]) {
  const file = path.join(distDir, name);
  if (!fs.existsSync(file)) continue;
  let code = fs.readFileSync(file, "utf8");
  code = code.replace(/require\("dotenv\/config"\);\n?/, "");
  for (const [re, replacement] of replacements) {
    code = code.replace(re, replacement);
  }
  fs.writeFileSync(file, code);
}

console.log(`Injected .env.${envName} into ${path.relative(rootDir, path.join(distDir, "cli.js"))} (KOT_BASE_URL, KOT_HEADLESS).`);

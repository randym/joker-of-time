#!/usr/bin/env node
/**
 * Clears stored dev credentials (UserDefaults) so you can test "no credentials" flow.
 * Usage: yarn run clear-credentials
 * Then restart the app; it will show the credentials form.
 */
const { execSync } = require("child_process");

const DOMAINS = [
  "io.github.randym.JokerOfTime", // app bundle (Info.plist)
  "JokerOfTime",                  // swift run
];
const KEYS = ["JokerOfTime.Dev.Username", "JokerOfTime.Dev.Password"];

for (const domain of DOMAINS) {
  for (const key of KEYS) {
    try {
      execSync(`defaults delete ${domain} ${key}`, { stdio: "pipe" });
    } catch (_) {
      // key or domain may not exist
    }
  }
}

console.log("Dev credentials cleared. Restart the app to see the credentials form.");

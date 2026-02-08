#!/usr/bin/env node
/**
 * Generates mock-site/timecard.html from timecard-template.html using system date (MM/DD) and state.
 * Usage: node scripts/prep-mock-timecard.js <state> [startHH:mm] [endHH:mm]
 * States: not-working | working-not-clocked-in | clocked-in | clocked-out
 * For clocked-in: optional startHH:mm (default: current time).
 * For clocked-out: startHH:mm and endHH:mm (default end: current time).
 */

const fs = require("fs");
const path = require("path");

const MOCK_SITE = path.join(__dirname, "..", "mock-site");
const TEMPLATE_PATH = path.join(MOCK_SITE, "timecard-template.html");
const OUTPUT_PATH = path.join(MOCK_SITE, "timecard.html");

const VALID_STATES = ["not-working", "working-not-clocked-in", "clocked-in", "clocked-out"];

function getTodayMMDD() {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${month}/${day}`;
}

function nowHHmm() {
  const d = new Date();
  return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
}

function cellTime(hhmm) {
  return '<span class="specific-normal_record_sign">C</span>' + hhmm + "<br>";
}

function getPlaceholders(state, startHHmm, endHHmm) {
  const today = getTodayMMDD();
  switch (state) {
    case "not-working":
      return {
        TODAY: today,
        WORK_DAY_TYPE: "法定外休日",
        START_TIMERECORD: "",
        END_TIMERECORD: "",
      };
    case "working-not-clocked-in":
      return {
        TODAY: today,
        WORK_DAY_TYPE: "平日",
        START_TIMERECORD: "",
        END_TIMERECORD: "",
      };
    case "clocked-in": {
      const start = startHHmm || nowHHmm();
      return {
        TODAY: today,
        WORK_DAY_TYPE: "平日",
        START_TIMERECORD: cellTime(start),
        END_TIMERECORD: "",
      };
    }
    case "clocked-out": {
      const start = startHHmm || "08:54";
      const end = endHHmm || nowHHmm();
      return {
        TODAY: today,
        WORK_DAY_TYPE: "平日",
        START_TIMERECORD: cellTime(start),
        END_TIMERECORD: cellTime(end),
      };
    }
    default:
      throw new Error(`Unknown state: ${state}`);
  }
}

function main() {
  const args = process.argv.slice(2);
  const state = args[0] === "set-state" ? args[1] : args[0];
  if (!state || !VALID_STATES.includes(state)) {
    console.error("Usage: node scripts/prep-mock-timecard.js <state> [startHH:mm] [endHH:mm]");
    console.error("States:", VALID_STATES.join(" | "));
    process.exit(1);
  }
  const startHHmm = args[0] === "set-state" ? args[2] : args[1];
  const endHHmm = args[0] === "set-state" ? args[3] : args[2];

  const template = fs.readFileSync(TEMPLATE_PATH, "utf8");
  const placeholders = getPlaceholders(state, startHHmm, endHHmm);
  let output = template;
  for (const [key, value] of Object.entries(placeholders)) {
    output = output.replace(new RegExp(`\\{\\{${key}\\}\\}`, "g"), value);
  }

  fs.writeFileSync(OUTPUT_PATH, output, "utf8");
  console.log("Wrote", OUTPUT_PATH, "| state:", state, "| today:", placeholders.TODAY);
}

main();

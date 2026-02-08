import * as fs from "fs";
import * as path from "path";

const LOG_DIR = "logs";
const LOG_FILE = "clocker.log";

function timestamp(): string {
  return new Date().toISOString();
}

function line(level: string, ...args: unknown[]): string {
  const msg = args.map((a) => (typeof a === "object" ? JSON.stringify(a) : String(a))).join(" ");
  return `${timestamp()} [${level}] ${msg}`;
}

function writeToFile(level: string, ...args: unknown[]): void {
  if (!process.env.JOT_DEV) return;
  try {
    const dir = path.join(process.cwd(), LOG_DIR);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const filePath = path.join(dir, LOG_FILE);
    fs.appendFileSync(filePath, line(level, ...args) + "\n");
  } catch {
    // ignore
  }
}

const isDev = process.env.JOT_DEV === "1";

// Log to stderr so stdout is reserved for JSON output (e.g. timecard-status); Swift reads only stdout for parsing.
// In production, only errors go to stderr so user logs don't fill up; info/debug are dev-only.
export function info(...args: unknown[]): void {
  if (isDev) console.error("[clock-helper]", ...args);
  writeToFile("INFO", ...args);
}

export function error(...args: unknown[]): void {
  console.error("[clock-helper]", ...args);
  writeToFile("ERROR", ...args);
}

export function debug(...args: unknown[]): void {
  if (process.env.DEBUG) {
    if (isDev) console.error("[clock-helper]", ...args);
    writeToFile("DEBUG", ...args);
  }
}

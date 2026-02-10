function timestamp(): string {
  return new Date().toISOString();
}

function line(level: string, ...args: unknown[]): string {
  const msg = args.map((a) => (typeof a === "object" ? JSON.stringify(a) : String(a))).join(" ");
  return `${timestamp()} [${level}] ${msg}`;
}

// Intentionally no-op: Node automation never writes logs directly to disk.
// Swift owns log files; we marshal diagnostics via stdout/stderr instead.
function writeToFile(_level: string, ..._args: unknown[]): void {
  // no-op
}

const isDev = process.env.JOT_DEV === "1";

// Log to stderr so stdout is reserved for JSON output (e.g. timecard-status); Swift reads only stdout for parsing.
// In production, only errors go to stderr so user logs don't fill up; info/debug are dev-only.
export function info(...args: unknown[]): void {
  if (isDev) console.error(...args);
  writeToFile("INFO", ...args);
}

export function error(...args: unknown[]): void {
  console.error(...args);
  writeToFile("ERROR", ...args);
}

export function debug(...args: unknown[]): void {
  if (process.env.DEBUG) {
    if (isDev) console.error(...args);
    writeToFile("DEBUG", ...args);
  }
}

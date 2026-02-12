#!/usr/bin/env node

import * as readline from "readline";
import {
  createBrowser,
  performClockActionWithBrowser,
  performClockActionWithPage,
  ClockAction,
  fetchTimecardStatusWithBrowser,
  fetchTimecardStatusWithPage,
  ALREADY_CLOCKED_IN,
  ALREADY_CLOCKED_OUT,
  NOT_CLOCKED_IN,
} from "./clock";
import type { Browser, BrowserContext, Page } from "playwright";
import * as log from "./log";

log.info(`Node ${process.version}`);

type Command =
  | { cmd: "timecard-status"; username: string; password: string; baseUrl?: string }
  | { cmd: "clock-in" | "clock-out"; username: string; password: string; baseUrl?: string };

let browserRef: Browser | null = null;
let daemonContextRef: BrowserContext | null = null;
let daemonPageRef: Page | null = null;

async function getOrCreateDaemonPage(): Promise<Page> {
  if (daemonPageRef && !daemonPageRef.isClosed()) return daemonPageRef;
  if (daemonContextRef) {
    try {
      await daemonContextRef.close();
    } catch {
      /* ignore */
    }
    daemonContextRef = null;
  }
  daemonPageRef = null;
  if (!browserRef) throw new Error("Daemon browser not started");
  daemonContextRef = await browserRef.newContext();
  daemonPageRef = await daemonContextRef.newPage();
  return daemonPageRef;
}

async function main() {
  const [, , rawAction] = process.argv;
  const action = rawAction as string | undefined;

  if (action === "app-start") {
    log.info("App started");
    process.exit(0);
  }

  if (action === "daemon") {
    log.info("Daemon starting (one browser, reuse for all commands)");
    browserRef = await createBrowser();
    const rl = readline.createInterface({ input: process.stdin, terminal: false });
    rl.on("line", async (line) => {
      const trimmed = line.trim();
      if (!trimmed) return;
      try {
        const body = JSON.parse(trimmed) as Command;
        const page = await getOrCreateDaemonPage();
        if (body.cmd === "timecard-status") {
          const status = await fetchTimecardStatusWithPage(page, {
            username: body.username,
            password: body.password,
            baseUrl: body.baseUrl,
          });
          console.log(JSON.stringify(status));
        } else if (body.cmd === "clock-in" || body.cmd === "clock-out") {
          await performClockActionWithPage(page, {
            action: body.cmd,
            username: body.username,
            password: body.password,
            baseUrl: body.baseUrl,
          });
          console.log(JSON.stringify({ ok: true }));
        } else {
          console.log(JSON.stringify({ error: "Unknown command: " + (body as { cmd?: string }).cmd }));
        }
      } catch (err) {
        const code =
          (err as any)?.automationCode ??
          (err instanceof Error ? err.message : "UNKNOWN_ERROR");
        const message =
          (err as any)?.automationMessage ??
          (err instanceof Error ? err.message : String(err));
        console.log(JSON.stringify({ ok: false, error: code, code, message }));
      }
    });
    rl.on("close", () => {
      daemonPageRef = null;
      daemonContextRef = null;
      if (browserRef) browserRef.close().catch(() => {});
      process.exit(0);
    });
    return;
  }

  log.info("Run started:", action ?? "(no action)");

  if (action === "timecard-status") {
    const input = await new Promise<string>((resolve) => {
      const chunks: Buffer[] = [];
      process.stdin.on("data", (chunk) => chunks.push(chunk));
      process.stdin.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    });
    const body = JSON.parse(input.trim()) as Command;
    if (body.cmd !== "timecard-status") {
      log.error("Invalid command in JSON:", body.cmd);
      process.exit(1);
    }
    browserRef = await createBrowser();
    try {
      const status = await fetchTimecardStatusWithBrowser(browserRef, {
        username: body.username,
        password: body.password,
        baseUrl: body.baseUrl,
      });
      const day = status.shouldWorkToday ? "Working day" : "Non-working day";
      const clock = status.clockedOut
        ? `done for the day (${status.clockInTime ?? "?"}–${status.clockOutTime ?? "?"})`
        : status.clockedIn
          ? `clocked in since ${status.clockInTime ?? "?"}`
          : "not clocked in";
      const when = status.todayLabel ? ` — ${status.todayLabel}` : "";
      log.info(`Time card: ${day}; ${clock}${when}`);
      console.log(JSON.stringify(status));
      process.exit(0);
    } catch (err) {
      const code =
        (err as any)?.automationCode ??
        (err instanceof Error ? err.message : "UNKNOWN_ERROR");
      const message =
        (err as any)?.automationMessage ??
        (err instanceof Error ? err.message : String(err));
      log.error("timecard-status failed:", message);
      console.log(JSON.stringify({ ok: false, error: code, code, message }));
      process.exit(1);
    } finally {
      await browserRef.close();
    }
  }

  if (action !== "clock-in" && action !== "clock-out") {
    log.error("Usage: automation <clock-in|clock-out|timecard-status|daemon>");
    process.exit(1);
  }

  const input = await new Promise<string>((resolve) => {
    const chunks: Buffer[] = [];
    process.stdin.on("data", (chunk) => chunks.push(chunk));
    process.stdin.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
  });
  const body = JSON.parse(input.trim()) as Command;
  if (body.cmd !== action) {
    log.error("Command mismatch: expected", action, "got", body.cmd);
    process.exit(1);
  }

  browserRef = await createBrowser();
  try {
    await performClockActionWithBrowser(browserRef, {
      action: body.cmd,
      username: body.username,
      password: body.password,
      baseUrl: body.baseUrl,
    });
    log.info("Clock action completed:", action);
    process.exit(0);
  } catch (err) {
    log.error("Clock action failed:", err instanceof Error ? err.message : err);
    process.exit(1);
  } finally {
    await browserRef.close();
  }
}

main();

/**
 * King of Time automation. All runs start at the recorder URL (KOT_BASE_URL).
 *
 * Two flows only:
 * 1. Status: ensureLoggedIn → navigate to time card → getTimecardStatus (fetchTimecardStatus).
 * 2. Clock:  ensureLoggedIn → click clock-in or clock-out button (performClockAction). No timecard, no second navigation.
 */
import { webkit, Browser, Page } from "playwright";
import * as log from "./log";

export type ClockAction = "clock-in" | "clock-out";

export interface ClockOptions {
  action: ClockAction;
  username: string;
  password: string;
}

const DEFAULT_KOT_URL =
  "https://s3.ta.kingoftime.jp/independent/recorder2/personal/";

export function getKotUrl(override?: string): string {
  return override ?? process.env.KOT_BASE_URL ?? DEFAULT_KOT_URL;
}

export async function createBrowser(): Promise<Browser> {
  const headless = process.env.KOT_HEADLESS !== "false";
  return webkit.launch({ headless });
}

/** Max time we wait for any page or target; if KOT is slower, treat as failure. */
const PAGE_LOAD_TIMEOUT_MS = 5000;

/** Proceed as soon as we have a response (commit); then we only wait for the target element. Page load can be ~4ms. */
const WAIT_UNTIL = "commit" as const;

const RECORDER_SELECTOR = "#employee_name, ul#buttons .record-clock-in";
// From mock-site/reference/kot-login-page-sample.html: ID input has id="id" (no name), password has id="password", submit is a div not button.
const LOGIN_USER_SELECTOR = "input#id, input[name='login_id']";
const LOGIN_PASS_SELECTOR = "input#password, input[name='password']";
const LOGIN_BUTTON_SELECTOR =
  "button[type='submit'], input[type='submit'], .btn-control-inner .btn-control-message, .btn-control-inner";

/** After goto(commit), wait for either recorder or login form — whichever is visible first. Must use "visible" so we don't mistake a hidden/template element on the login page for the recorder. */
async function waitForRecorderOrLoginForm(page: Page): Promise<"recorder" | "login_form"> {
  const recorder = page.locator(RECORDER_SELECTOR).first();
  const loginForm = page.locator(LOGIN_USER_SELECTOR).first();
  const recorderPromise = recorder
    .waitFor({ state: "visible", timeout: PAGE_LOAD_TIMEOUT_MS })
    .then(() => "recorder" as const)
    .catch(() => null);
  const loginPromise = loginForm
    .waitFor({ state: "visible", timeout: PAGE_LOAD_TIMEOUT_MS })
    .then(() => "login_form" as const)
    .catch(() => null);
  const result = await Promise.race([recorderPromise, loginPromise]);
  if (result === null) {
    throw new Error("Page did not show recorder or login form within timeout.");
  }
  return result;
}

/** Goto recorder URL and wait for recorder or login form. Returns true if already on recorder (session valid). Use to restore from saved storage state. */
export async function tryRestoreSession(page: Page, baseUrl?: string): Promise<boolean> {
  const kotUrl = getKotUrl(baseUrl);
  await page.goto(kotUrl, { waitUntil: WAIT_UNTIL, timeout: PAGE_LOAD_TIMEOUT_MS });
  const landing = await waitForRecorderOrLoginForm(page);
  return landing === "recorder";
}

function isTimeoutError(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return /timeout|Timeout|ETIMEDOUT|ENOTFOUND|ECONNREFUSED|network/i.test(msg);
}

function throwAutomationError(code: string, err: unknown): never {
  const detail = err instanceof Error ? err.message : String(err);
  const e = new Error(code);
  (e as any).automationCode = code;
  (e as any).automationMessage = detail;
  throw e;
}

/** Start at recorder URL; if not already logged in, find login form and submit. Leaves page on recorder. */
async function ensureLoggedIn(page: Page, username: string, password: string, baseUrl?: string): Promise<void> {
  const kotUrl = getKotUrl(baseUrl);
  const t0 = Date.now();
  log.info("Request URL:", kotUrl);
  try {
    await page.goto(kotUrl, { waitUntil: WAIT_UNTIL, timeout: PAGE_LOAD_TIMEOUT_MS });
  } catch (err) {
    if (isTimeoutError(err)) throwAutomationError(NETWORK_ERROR, err);
    throw err;
  }
  const tGoto = Date.now() - t0;
  log.info("Response URL:", page.url(), `(${tGoto}ms)`);

  let landing: "recorder" | "login_form";
  try {
    landing = await waitForRecorderOrLoginForm(page);
  } catch (err) {
    if (isTimeoutError(err)) throwAutomationError(NETWORK_ERROR, err);
    throw err;
  }
  const tTarget = Date.now() - t0 - tGoto;
  log.info(landing === "recorder" ? "Recorder visible" : "Login form visible", `(${tTarget}ms)`);
  if (landing === "recorder") {
    log.info("Already logged in, skipping login", `(ensureLoggedIn ${Date.now() - t0}ms total)`);
    return;
  }

  const tBeforeFill = Date.now();
  const userEl = page.locator(LOGIN_USER_SELECTOR).first();
  const passEl = page.locator(LOGIN_PASS_SELECTOR).first();
  await userEl.fill(username);
  await passEl.fill(password);
  log.info("Login form filled", `(${Date.now() - tBeforeFill}ms)`);

  const btn = page.locator(LOGIN_BUTTON_SELECTOR).first();
  log.info("Login submitted");
  const tBeforeRecorder = Date.now();
  try {
    await Promise.all([
      page.waitForURL((u) => u.href.includes("recorder"), { timeout: PAGE_LOAD_TIMEOUT_MS }),
      btn.click(),
    ]);
  } catch (err) {
    if (isTimeoutError(err)) throw new Error(LOGIN_FAILED);
    throw err;
  }
  log.info("URL after login:", page.url(), `(${Date.now() - tBeforeRecorder}ms)`);
  log.info("Login succeeded, on recorder", `(ensureLoggedIn ${Date.now() - t0}ms total)`);
}

async function clickClockButton(page: Page, action: ClockAction) {
  const t0 = Date.now();
  const selector =
    action === "clock-in"
      ? "ul#buttons .record-clock-in"
      : "ul#buttons .record-clock-out";
  log.info("Clicking button:", selector);
  const locator = page.locator(selector).first();
  await locator.waitFor({ state: "visible", timeout: PAGE_LOAD_TIMEOUT_MS });
  await locator.click();
  log.info("Clock button clicked", `(${Date.now() - t0}ms)`);
}

// Recorder page: menu trigger (KOT recorder: #menu_icon / .menu-icon; KOT timecard page: .htBlock-header_menuButton.menu-main a, メニュー)
const RECORDER_MENU_TRIGGER_SELECTOR =
  "#menu_icon, .menu-icon, .htBlock-header_menuButton.menu-main a, a:has-text('メニュー')";
// Time card link: in menu (ul#menu with タイムカード or href containing page_id)
const TIMECARD_LINK_SELECTOR =
  "ul#menu a:has-text('タイムカード'), a[href*='page_id=/working/monthly_individual_working_list']";

/** Open menu (upper right), click タイムカード link, wait for navigation. From kot-recorder-page-sample. Let the browser handle clicks. */
export async function navigateToTimecard(page: Page): Promise<void> {
  const t0 = Date.now();
  // Wait for recorder page to be ready so the menu is in the DOM (real KOT may render it via JS).
  await page.waitForLoadState("domcontentloaded", { timeout: PAGE_LOAD_TIMEOUT_MS });
  log.info("Opening menu (upper right)");
  const menuTrigger = page.locator(RECORDER_MENU_TRIGGER_SELECTOR).first();
  await menuTrigger.waitFor({ state: "visible", timeout: PAGE_LOAD_TIMEOUT_MS });
  await menuTrigger.click();
  log.info("Clicking time card link");
  const timecardLink = page.locator(TIMECARD_LINK_SELECTOR).first();
  await timecardLink.waitFor({ state: "visible", timeout: PAGE_LOAD_TIMEOUT_MS });
  // Use waitForURL (not waitForNavigation) — more reliable in WebKit; commit/load can misbehave.
  await Promise.all([
    page.waitForURL(
      (u) => u.href.includes("timecard") || u.href.includes("monthly_individual_working_list"),
      { timeout: PAGE_LOAD_TIMEOUT_MS }
    ),
    timecardLink.click(),
  ]);
  await page.waitForLoadState("domcontentloaded", { timeout: PAGE_LOAD_TIMEOUT_MS });
  log.info("Time card URL:", page.url(), `(navigateToTimecard ${Date.now() - t0}ms)`);
}

/** Today's date in MM/DD format to match time card cell text (e.g. "02/06" or "02/06（金）"). */
function getTodayMMDD(): string {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${month}/${day}`;
}

const TIME_PATTERN = /\d{1,2}:\d{2}/;

function extractTimeFromCell(text: string): string | null {
  const match = text.match(TIME_PATTERN);
  return match ? match[0] : null;
}

export interface TimecardStatus {
  shouldWorkToday: boolean;
  clockedIn: boolean;
  clockInTime: string | null;
  clockedOut: boolean;
  clockOutTime: string | null;
  todayLabel?: string;
}

/** Time card table column selectors (data-ht-sort-index / class fallbacks). */
const COL = {
  date: "td[data-ht-sort-index='WORK_DAY'], td.htBlock-scrollTable_day",
  workDayType: "td[data-ht-sort-index='WORK_DAY_TYPE'], td.work_day_type",
  start: "td[data-ht-sort-index='START_TIMERECORD']",
  end: "td[data-ht-sort-index='END_TIMERECORD']",
} as const;

/** Parse time card page for today's row. Page must already be on the time card view. */
export async function getTimecardStatus(page: Page): Promise<TimecardStatus> {
  const t0 = Date.now();
  const todayMMDD = getTodayMMDD();
  // Real KOT may use .htBlock-adjastableTableF_inner table (see reference/README).
  const table = page.locator(".htBlock-adjastableTableF table, .htBlock-adjastableTableF_inner table").first();
  await table.waitFor({ state: "visible", timeout: PAGE_LOAD_TIMEOUT_MS });
  const rows = table.locator("tbody tr");
  const count = await rows.count();
  for (let i = 0; i < count; i++) {
    const row = rows.nth(i);
    const dateText = (await row.locator(COL.date).first().textContent())?.trim() ?? "";
    if (!dateText.includes(todayMMDD)) continue;
    const workDayType = (await row.locator(COL.workDayType).first().textContent())?.trim() ?? "";
    const startText = (await row.locator(COL.start).first().textContent())?.trim() ?? "";
    const endText = (await row.locator(COL.end).first().textContent())?.trim() ?? "";
    const clockInTime = extractTimeFromCell(startText);
    const clockOutTime = extractTimeFromCell(endText);
    // Working day = only 平日 or blank. Full parse of mock-site/reference/kot-timecard-full.html
    // (all 31 data rows with WORK_DAY_TYPE): only these values appear in that column:
    //   平日 (working), 法定休日 (non-working), 法定外休日 (non-working).
    // Blank = future working day or same day before clock-in → treat as working.
    // Any other value (e.g. flex, 有休) = non-working.
    const shouldWorkToday = workDayType === "平日" || workDayType === "";
    log.info("Time card parsed", `(getTimecardStatus ${Date.now() - t0}ms)`);
    return {
      shouldWorkToday,
      clockedIn: clockInTime !== null,
      clockInTime,
      clockedOut: clockOutTime !== null,
      clockOutTime,
      todayLabel: dateText,
    };
  }
  log.info("Time card parsed (no today row)", `(getTimecardStatus ${Date.now() - t0}ms)`);
  return {
    shouldWorkToday: false,
    clockedIn: false,
    clockInTime: null,
    clockedOut: false,
    clockOutTime: null,
    todayLabel: undefined,
  };
}

/** Status flow: start at recorder, ensure logged in, navigate to time card, pull data. */
export async function fetchTimecardStatus(options: {
  username: string;
  password: string;
}): Promise<TimecardStatus> {
  const browser = await createBrowser();
  try {
    return await fetchTimecardStatusWithBrowser(browser, options);
  } finally {
    await browser.close();
  }
}

/** Same as fetchTimecardStatus but reuses an existing browser (no launch cost). Use from daemon. */
export async function fetchTimecardStatusWithBrowser(
  browser: Browser,
  options: { username: string; password: string; baseUrl?: string }
): Promise<TimecardStatus> {
  const context = await browser.newContext();
  const page = await context.newPage();
  try {
    return await fetchTimecardStatusWithPage(page, options);
  } finally {
    await context.close();
  }
}

/** Reuse a single page (stay logged in). Use from daemon for speed: no new context, no login every time. */
export async function fetchTimecardStatusWithPage(
  page: Page,
  options: { username: string; password: string; baseUrl?: string }
): Promise<TimecardStatus> {
  const t0 = Date.now();
  await ensureLoggedIn(page, options.username, options.password, options.baseUrl);
  try {
    await navigateToTimecard(page);
    const status = await getTimecardStatus(page);
    log.info("fetchTimecardStatus done", `(${Date.now() - t0}ms total)`);
    return status;
  } catch (err) {
    if (isTimeoutError(err)) throwAutomationError(NETWORK_ERROR, err);
    throw err;
  }
}

/** Known error messages for guards so the app can show a specific message. */
export const ALREADY_CLOCKED_IN = "ALREADY_CLOCKED_IN";
export const ALREADY_CLOCKED_OUT = "ALREADY_CLOCKED_OUT";
export const NOT_CLOCKED_IN = "NOT_CLOCKED_IN";
export const LOGIN_FAILED = "LOGIN_FAILED";
export const NETWORK_ERROR = "NETWORK_ERROR";

/** Clock flow: start at recorder, ensure logged in, find and click the clock-in or clock-out button. */
export async function performClockAction(options: ClockOptions): Promise<void> {
  const browser = await createBrowser();
  try {
    await performClockActionWithBrowser(browser, options);
  } finally {
    await browser.close();
  }
}

export interface ClockOptionsWithBaseUrl extends ClockOptions {
  baseUrl?: string;
}

/** Same as performClockAction but reuses an existing browser (no launch cost). Use from daemon. */
export async function performClockActionWithBrowser(browser: Browser, options: ClockOptionsWithBaseUrl): Promise<void> {
  const context = await browser.newContext();
  const page = await context.newPage();
  try {
    await performClockActionWithPage(page, options);
  } finally {
    await context.close();
  }
}

/** Reuse a single page (stay logged in). Use from daemon for speed. */
export async function performClockActionWithPage(page: Page, options: ClockOptionsWithBaseUrl): Promise<void> {
  const t0 = Date.now();
  const { action, username, password, baseUrl } = options;
  try {
    await ensureLoggedIn(page, username, password, baseUrl);
    await clickClockButton(page, action);
    log.info("Action completed:", action, `(performClockAction ${Date.now() - t0}ms total)`);
  } catch (err) {
    if (err instanceof Error && [ALREADY_CLOCKED_IN, ALREADY_CLOCKED_OUT, NOT_CLOCKED_IN].includes(err.message)) {
      throw err;
    }
    log.error("performClockAction failed:", err instanceof Error ? err.message : err);
    throw err;
  }
}

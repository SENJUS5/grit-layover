// GRIT runs on India time: every date the app shows is in IST (Asia/Kolkata),
// matching the database's ist_date() / ist_today().

const IST = "Asia/Kolkata";

const parts = (date: Date, options: Intl.DateTimeFormatOptions, timeZone = IST) =>
  Object.fromEntries(
    new Intl.DateTimeFormat("en-GB", { timeZone, ...options }).formatToParts(date).map((p) => [p.type, p.value]),
  );

/** "Sat 14 Nov, 10:30" */
export function formatDateTime(iso: string): string {
  const p = parts(new Date(iso), { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  return `${p.weekday} ${p.day} ${p.month}, ${p.hour}:${p.minute}`;
}

/** "Sat 14 Nov 2026" */
export function formatDate(iso: string): string {
  const p = parts(new Date(iso), { weekday: "short", day: "numeric", month: "short", year: "numeric" });
  return `${p.weekday} ${p.day} ${p.month} ${p.year}`;
}

/** "10:30" */
export function formatTime(iso: string): string {
  const p = parts(new Date(iso), { hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  return `${p.hour}:${p.minute}`;
}

/** A date-only value ("2026-11-15") as "Sun 15 Nov", or with the year. */
export function formatDay(day: string, withYear = false): string {
  const p = parts(new Date(`${day}T00:00:00Z`), { weekday: "short", day: "numeric", month: "short", year: "numeric" }, "UTC");
  return withYear ? `${p.weekday} ${p.day} ${p.month} ${p.year}` : `${p.weekday} ${p.day} ${p.month}`;
}

/** "31 Dec 2026" (for deadlines). */
export function formatDeadline(day: string): string {
  const p = parts(new Date(`${day}T00:00:00Z`), { day: "numeric", month: "short", year: "numeric" }, "UTC");
  return `${p.day} ${p.month} ${p.year}`;
}

/** The IST calendar day ("YYYY-MM-DD") of a moment. */
export function istDay(moment: string | number): string {
  const p = parts(new Date(moment), { year: "numeric", month: "2-digit", day: "2-digit" });
  return `${p.year}-${p.month}-${p.day}`;
}

/** Calendar arithmetic on "YYYY-MM-DD" values. */
export function addDays(day: string, days: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** An IST wall-clock time as a timestamp the database accepts: "2026-11-15T10:30:00+05:30". */
export function istToIso(day: string, time: string): string {
  return `${day}T${time}:00+05:30`;
}

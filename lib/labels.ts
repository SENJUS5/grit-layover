import type { JourneyState, ListName, Outcome, PassbookRow, RequirementRow } from "./types";

/** "Qualiflyers" -> "Qualiflyer" */
export const listSingular = (list: ListName) => (list === "Qualiflyers" ? "Qualiflyer" : "Pre-Qualiflyer");

/** "Qualiflyer #2", or a plain note when the student is not on the leaderboard. */
export function standing(list: ListName | null, rank: number | null): string {
  return list && rank ? `${listSingular(list)} #${rank}` : "Not on the leaderboard";
}

export const OUTCOMES: { value: Outcome; label: string }[] = [
  { value: "pass", label: "Pass" },
  { value: "fail", label: "Fail" },
  { value: "retake_later", label: "Retake later" },
  { value: "no_show", label: "No-show" },
  { value: "technical_issue", label: "Technical issue" },
];

export const outcomeLabel = (outcome: Outcome) => OUTCOMES.find((o) => o.value === outcome)?.label ?? outcome;

/** Outcomes that carry a retake date (the database enforces the same rule). */
export const hasCooldown = (outcome: Outcome) => outcome === "fail" || outcome === "retake_later" || outcome === "no_show";

const MEDALS = { gold: "Gold", silver: "Silver", try_again: "Try again" } as const;

/** What a Miles passbook row was for. Removal rows never name the cause. */
export function passbookLabel(row: PassbookRow): string {
  const badge = `${row.badge_track} ${row.badge_level}`;
  const medal = row.medal ? MEDALS[row.medal] : "";
  switch (row.reason) {
    case "skill_medal":
      return `${row.skill_name} L${row.skill_level} · ${medal}`;
    case "medal_upgrade":
      return `${row.skill_name} L${row.skill_level} · upgraded to ${medal}`;
    case "badge_bonus":
      return `${badge} badge`;
    case "badge_revoked":
      return `${badge} badge removed`;
    case "bonus_milestone":
      return row.note ?? "Bonus Miles";
  }
}

export type Tone = "yellow" | "blue" | "red" | "purple" | "muted";

export const STATE_TONE: Record<JourneyState, Tone> = {
  "Ready to book": "yellow",
  Passed: "yellow",
  Booked: "blue",
  "Project pending": "blue",
  "Waiting for result": "purple",
  "Under review": "purple",
  "Retake later": "red",
  "Not eligible": "red",
  Revoked: "red",
  "Not ready": "muted",
};

/** ["A"] -> "A", ["A", "B"] -> "A and B", ["A", "B", "C"] -> "A, B and C" */
export function joinAnd(items: string[]): string {
  if (items.length <= 1) return items[0] ?? "";
  return `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;
}

/** "3 of 4 skills cleared — clear UI Engineering L2 to book" */
export function readiness(requirements: RequirementRow[]): string {
  const cleared = requirements.filter((r) => r.is_cleared).length;
  const missing = requirements.filter((r) => !r.is_cleared).map((r) => `${r.skill_name} L${r.required_level}`);
  if (missing.length === 0) return `All ${requirements.length} skills cleared`;
  return `${cleared} of ${requirements.length} skills cleared — clear ${joinAnd(missing)} to book`;
}

/** One requirement's progress, in words. */
export function requirementStatus(r: RequirementRow): string {
  if (r.is_cleared) return `Cleared at L${r.best_cleared_level}`;
  if (r.best_attempted_level !== null && r.best_attempted_level >= r.required_level) {
    return `Tried L${r.required_level}: needs gold or silver`;
  }
  if (r.best_cleared_level !== null) return `Cleared up to L${r.best_cleared_level}`;
  return "Not cleared yet";
}

/** Numbers from numeric columns ("75.00" or 75) as short text: "75", "72.5". */
export const num = (value: number | string) => String(Number(value));

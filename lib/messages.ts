// =============================================================================
// Every message a student reads, in one place, so the wording is easy to edit.
//
// Writing rules: simple words, short, kind, specific.
// A light travel theme ("layover", "flight") is fine in the positive messages
// only. "Your badge has been removed" has no jokes, no blame words, and never
// promises an appeal.
// =============================================================================

import { standing } from "./labels";
import { formatDate, formatDay, formatDeadline } from "./time";
import type { JourneyRow, Overview, TimelineEvent } from "./types";

// Real GRIT support address from GRIT Terms & Conditions, clause 16.8 (data errors).
export const SUPPORT_EMAIL = "niat.grit@nxtwave.tech";

export type Message = {
  id: string;
  title: string;
  /** When it happened (ISO), used for sorting and the date line. */
  at: string;
  tone: "good" | "neutral" | "care";
  body: string[];
  /** A button under the text. */
  action?: { href: string; label: string };
  /** Small print under the message. */
  note?: string;
};

export const TITLES = {
  result: "Here's your result",
  onTheWay: "Your result is on the way",
  removed: "Your badge has been removed",
};

/** Under a didn't-pass or technical-issue result, while the student can book that badge right now. */
export const OPEN_SLOTS = { href: "/interviews", label: "See open slots" };

/** Private notice on the student's own Dashboard while a case is open (never on public screens). */
export const UNDER_REVIEW_NOTICE = {
  title: "Under review",
  body:
    "One of your interviews is being reviewed. Your badges and Miles still count, and you can keep booking. " +
    "The final steps of your trip are on hold until the review is done. Only you can see this notice.",
};

// ----------------------------------------------------------- 1. Your result

function passed(ev: TimelineEvent, ctx: Context): string[] {
  const badge = `${ev.track} ${ev.levels[0]}`;
  const lines = [
    `Well done, you passed ${badge}!`,
    `Your badge counts from your interview day, ${formatDate(ev.interview_held_at!)}.`,
  ];
  if (ev.bonus_miles) lines.push(`+${ev.bonus_miles} Miles are now in your passbook.`);
  if (!ctx.stillHeld(ev)) {
    lines.push("This badge was removed later. See the message about it.");
    return lines;
  }
  if (ctx.overview?.list) lines.push(`You're now ${standing(ctx.overview.list, ctx.overview.list_rank)} on the leaderboard.`);
  if (ctx.overview) {
    lines.push(
      `Trip checklist: "One badge by ${formatDeadline(ctx.overview.badge_deadline)}" is ticked. ` +
        `${tripDone(ctx.overview)} of 5 done, and the final interview round comes later.`,
    );
  }
  lines.push("Enjoy the layover. Your next flight is the final round.");
  return lines;
}

function notPassed(ev: TimelineEvent, ctx: Context): string[] {
  const badge = `${ev.track} ${ev.levels[0]}`;
  const held = formatDate(ev.interview_held_at!);
  // The student waits only while the retake date is still ahead: the same test
  // the database uses to refuse a booking (retake_after > IST today). A
  // corrected pass and a technical issue have no retake date at all.
  const retakeFrom = ev.retake_after && ev.retake_after > ctx.today ? ev.retake_after : null;
  const later = ev.outcome === "retake_later" && retakeFrom !== null;

  const opening = ev.corrected
    ? `Your result for ${badge} was corrected. ` +
      (ev.outcome === "no_show"
        ? `It now shows that you missed the interview on ${held}.`
        : later
          ? "Your interviewer would like you to try again a little later."
          : "You didn't pass this time.")
    : ev.outcome === "no_show"
      ? `We missed you at your ${badge} interview on ${held}.`
      : later
        ? `Your interviewer would like you to try ${badge} again a little later.`
        : `You didn't pass ${badge} this time.`;

  const lines = [opening];
  if (ev.feedback) lines.push(`Feedback from your interviewer: "${ev.feedback}"`);
  if (ev.corrected && ev.correction_reason) lines.push(`Reason for the correction: ${ev.correction_reason}`);
  lines.push(retakeFrom ? `You can book again from ${formatDay(retakeFrom, true)}.` : "You can book again any time.");
  // "Use the time" needs a wait, and "the points above" needs feedback.
  lines.push(
    retakeFrom && ev.feedback
      ? "Your skill Miles and cleared skills stay as they are. Use the time to practise the points above."
      : "Your skill Miles and cleared skills stay as they are.",
  );
  return lines;
}

function technicalIssue(ev: TimelineEvent): string[] {
  const badge = `${ev.track} ${ev.levels[0]}`;
  const lines = [
    `Your ${badge} interview on ${formatDate(ev.interview_held_at!)} couldn't go ahead because of a technical issue.`,
    "That's not on you, and it won't count against you.",
    "You can book a new slot any time.",
  ];
  if (ev.feedback) lines.splice(1, 0, `Note from your interviewer: "${ev.feedback}"`);
  return lines;
}

// ------------------------------------------------- 2. Result on the way

function onTheWay(row: JourneyRow): string[] {
  const day = formatDate(row.slot_starts_at!);
  return [
    `Your ${row.track} ${row.level} interview on ${day} is done. Your interviewer will add the result soon.`,
    `If you pass, your badge counts from your interview day (${day}), not from the day the result is entered.`,
    "You've landed. Sit tight while your result taxis in.",
  ];
}

// --------------------------------------------- 3. Your badge has been removed

function removed(ev: TimelineEvent, ctx: Context): string[] {
  const [first, ...others] = ev.levels;
  const badge = `${ev.track} ${first}`;
  const lines = [
    ev.cause === "result_corrected"
      ? `Your ${badge} badge has been removed because your interview result was corrected.`
      : ev.cause === "malpractice"
        ? `Your ${badge} badge has been removed after a review of your interview.`
        : `Your ${badge} badge has been removed.`,
  ];
  if (others.length > 0) {
    const names = others.map((level) => `${ev.track} ${level}`).join(" and ");
    lines.push(
      `Badges are earned in order, so your ${names} ${others.length > 1 ? "badges have" : "badge has"} been removed too.`,
    );
  }

  const o = ctx.overview;
  if (ev.miles_change) {
    lines.push(`Miles: ${ev.miles_change} (you now have ${o ? o.total_miles : "fewer"} Miles).`);
  }
  if (o) {
    lines.push(
      o.list
        ? `Leaderboard: you're now ${standing(o.list, o.list_rank)}.`
        : "Leaderboard: you're not on the leaderboard for now.",
    );
    lines.push(
      o.badge_by_deadline
        ? `Trip checklist: you still hold a badge from before ${formatDeadline(o.badge_deadline)}.`
        : `Trip checklist: "One badge by ${formatDeadline(o.badge_deadline)}" is no longer ticked.`,
    );
    if (ev.cause === "result_corrected") lines.push("You can book this interview again any time.");
    else if (!o.conduct_ok) lines.push("Booking is paused for now. The GRIT team will tell you when you can book again.");
  }
  return lines;
}

// ------------------------------------------------------------ assembling

type Context = {
  overview: Overview | null;
  /** Today in India time ("YYYY-MM-DD"). */
  today: string;
  stillHeld: (ev: TimelineEvent) => boolean;
  /** The badge's journey state is "Ready to book": the student can book it right now. */
  canBookNow: (ev: TimelineEvent) => boolean;
};

const tripDone = (o: Overview) =>
  [o.attendance_ok, o.registered_ok, o.conduct_ok, o.badge_by_deadline].filter(Boolean).length;

/** The student's inbox, newest first. Messages are built from data, never stored. */
export function buildMessages(input: {
  overview: Overview | null;
  journey: JourneyRow[];
  timeline: TimelineEvent[];
  /** Today in India time ("YYYY-MM-DD"). */
  today: string;
}): Message[] {
  const ctx: Context = {
    overview: input.overview,
    today: input.today,
    stillHeld: (ev) =>
      input.journey.some(
        (j) => j.track === ev.track && j.level === ev.levels[0] && (j.state === "Passed" || j.state === "Under review"),
      ),
    canBookNow: (ev) =>
      input.journey.some((j) => j.track === ev.track && j.level === ev.levels[0] && j.state === "Ready to book"),
  };

  const messages: Message[] = [];
  for (const ev of input.timeline) {
    if (ev.kind === "badge_removed") {
      messages.push({
        id: `removed:${ev.track}:${ev.happened_at}`,
        title: TITLES.removed,
        at: ev.happened_at,
        tone: "care",
        body: removed(ev, ctx),
        note: `If something here looks wrong in your data, write to ${SUPPORT_EMAIL}.`,
      });
    } else if (ev.outcome) {
      const body =
        ev.outcome === "pass" ? passed(ev, ctx) : ev.outcome === "technical_issue" ? technicalIssue(ev) : notPassed(ev, ctx);
      messages.push({
        id: `result:${ev.track}:${ev.levels[0]}:${ev.interview_held_at}`,
        title: TITLES.result,
        at: ev.happened_at,
        tone: ev.outcome === "pass" ? "good" : "neutral",
        body,
        action: ev.outcome !== "pass" && ctx.canBookNow(ev) ? OPEN_SLOTS : undefined,
      });
    }
  }
  for (const row of input.journey) {
    if (row.state === "Waiting for result" && row.slot_starts_at) {
      messages.push({
        id: `waiting:${row.badge_id}`,
        title: TITLES.onTheWay,
        at: row.slot_starts_at,
        tone: "neutral",
        body: onTheWay(row),
      });
    }
  }
  return messages.sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
}

import { ArrowRight } from "lucide-react";
import { joinAnd, standing } from "@/lib/labels";
import { formatDateTime, formatDeadline } from "@/lib/time";
import type { LastChange } from "@/lib/types";
import { Card } from "./ui";

function Change({ label, before, after, note }: { label: string; before: string; after: string; note?: string }) {
  return (
    <div className="rounded-xl bg-surface-2 px-3 py-2.5">
      <dt className="text-xs font-semibold uppercase tracking-wider text-muted">{label}</dt>
      <dd className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 font-semibold">
        <span className="text-muted line-through decoration-muted/60">{before}</span>
        <ArrowRight size={16} className="text-muted" aria-label="to" />
        <span>{after}</span>
        {note && <span className="text-sm font-medium text-muted">({note})</span>}
      </dd>
    </div>
  );
}

/** Before and after the student's latest badge change: Miles, leaderboard place, and the badge condition. */
export function WhatChanged({ change, deadline }: { change: LastChange; deadline: string }) {
  const earned = change.change === "badge_earned";
  const badges = change.levels.map((level) => `${change.track} ${level}`);
  const delta = change.miles_after - change.miles_before;
  const tick = (held: boolean) => (held ? "Ticked" : "Not ticked");

  return (
    <Card tone={earned ? "yellow" : undefined} className="mb-6">
      <div className="flex flex-wrap items-baseline justify-between gap-x-3">
        <h2 className="text-lg font-bold">What changed</h2>
        <p className="text-sm text-muted">{formatDateTime(change.happened_at)}</p>
      </div>
      <p className="mt-1 text-sm">
        {earned
          ? `You earned ${badges[0]}.`
          : `${joinAnd(badges)} ${badges.length > 1 ? "were" : "was"} removed.`}
      </p>
      <dl className="mt-3 grid gap-2 sm:grid-cols-3">
        <Change
          label="Miles"
          before={String(change.miles_before)}
          after={String(change.miles_after)}
          note={`${delta > 0 ? "+" : ""}${delta}`}
        />
        <Change
          label="Leaderboard"
          before={standing(change.list_before, change.rank_before)}
          after={standing(change.list_after, change.rank_after)}
        />
        <Change
          label={`One badge by ${formatDeadline(deadline)}`}
          before={tick(change.deadline_badge_before)}
          after={tick(change.deadline_badge_after)}
        />
      </dl>
    </Card>
  );
}

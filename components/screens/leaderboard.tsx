"use client";

import { useState } from "react";
import useSWR from "swr";
import { RoleGate } from "@/components/role-gate";
import { Card, Empty, ErrorNote, firstError, Loading, PageHeader, Pill, TableWrap, td, th } from "@/components/ui";
import * as api from "@/lib/api";
import { useLeaderboard } from "@/lib/hooks";
import { listSingular, standing } from "@/lib/labels";
import { useNow } from "@/lib/use-now";
import type { Actor, ListName } from "@/lib/types";

const LISTS: { name: ListName; blurb: string }[] = [
  { name: "Qualiflyers", blurb: "Students holding at least one badge." },
  { name: "Pre-Qualiflyers", blurb: "Registered students without a badge yet." },
];

const RECENT_MS = 7 * 24 * 60 * 60 * 1000;

export function LeaderboardScreen() {
  return (
    <RoleGate allow={["student", "interviewer", "admin"]}>{(actor) => <Leaderboard key={actor.id} actor={actor} />}</RoleGate>
  );
}

function Leaderboard({ actor }: { actor: Actor }) {
  const board = useLeaderboard();
  const me = actor.role === "student" ? actor.id : null;
  // Same key as the Dashboard's "What changed" card.
  const lastChange = useSWR(me ? ["last-change", me] : null, () => api.studentLastChange(actor, me!));
  const now = useNow();
  const [tab, setTab] = useState<ListName | null>(null);

  const error = firstError(board, lastChange);
  if (error) return <ErrorNote message={error} />;
  if (!board.data || (me && lastChange.data === undefined)) return <Loading />;

  const all = board.data;
  const mine = all.find((r) => r.student_id === me);
  const shown = tab ?? mine?.list ?? "Qualiflyers";
  const rows = all.filter((r) => r.list === shown);
  const change = lastChange.data ?? null;
  const recent = change !== null && now !== null && now - Date.parse(change.happened_at) < RECENT_MS;
  const before = recent ? standing(change.list_before, change.rank_before) : null;
  const moved = recent && (change.list_before !== change.list_after || change.rank_before !== change.rank_after);

  return (
    <>
      <PageHeader title="Leaderboard" subtitle="Ranked by Miles, then highest badge, then skill depth, then who got there first." />

      {me && (
        <Card tone={mine ? "yellow" : undefined} className="mb-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted">You</p>
          <p className="mt-1 text-xl font-bold">
            {mine ? `${standing(mine.list, mine.list_rank)} · ${mine.total_miles} Miles` : "Not on the leaderboard right now"}
          </p>
          {moved && <p className="mt-1 text-sm text-muted">Before your latest badge change: {before}</p>}
        </Card>
      )}

      <div role="tablist" aria-label="Leaderboard lists" className="mb-4 flex flex-wrap gap-2">
        {LISTS.map(({ name }) => {
          const count = all.filter((r) => r.list === name).length;
          return (
            <button
              key={name}
              type="button"
              role="tab"
              aria-selected={shown === name}
              onClick={() => setTab(name)}
              className="rounded-full border border-line bg-surface-2 px-4 py-2 text-sm font-semibold text-muted transition hover:text-fg aria-selected:border-yellow aria-selected:bg-yellow aria-selected:text-bg"
            >
              {name} <span className="opacity-70">{count}</span>
            </button>
          );
        })}
      </div>
      <p className="mb-3 text-sm text-muted">{LISTS.find((l) => l.name === shown)?.blurb}</p>

      {rows.length === 0 ? (
        <Empty>Nobody here yet.</Empty>
      ) : (
        <Card className="p-0 md:p-0">
          <TableWrap>
            <table className="w-full min-w-[34rem]">
              <thead className="border-b border-line">
                <tr>
                  <th className={`${th} w-14`}>#</th>
                  <th className={th}>Student</th>
                  {shown === "Qualiflyers" && <th className={th}>Highest badge</th>}
                  <th className={`${th} text-right`}>Skill depth</th>
                  <th className={`${th} text-right`}>Miles</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {rows.map((r) => {
                  const isMe = r.student_id === me;
                  return (
                    <tr key={r.student_id} className={isMe ? "bg-yellow/10" : undefined} aria-current={isMe ? "true" : undefined}>
                      <td className={`${td} text-lg font-bold ${isMe ? "text-yellow" : ""}`}>{r.list_rank}</td>
                      <td className={td}>
                        <p className="flex flex-wrap items-center gap-2 font-semibold">
                          {r.name}
                          {isMe && <Pill tone="yellow">You</Pill>}
                        </p>
                        <p className="text-xs text-muted">
                          Batch {r.batch} · {r.campus} · Section {r.section}
                        </p>
                        {isMe && moved && <p className="text-xs text-muted">Was {before}</p>}
                      </td>
                      {shown === "Qualiflyers" && <td className={td}>{r.highest_badge ?? "—"}</td>}
                      <td className={`${td} text-right tabular-nums`}>{r.skill_depth}</td>
                      <td className={`${td} text-right text-base font-bold tabular-nums`}>{r.total_miles}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </TableWrap>
        </Card>
      )}
      {shown === "Pre-Qualiflyers" && (
        <p className="mt-3 text-xs text-muted">Earn a badge to move up to the {listSingular("Qualiflyers")} list.</p>
      )}
    </>
  );
}

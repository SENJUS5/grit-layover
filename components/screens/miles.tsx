"use client";

import { RoleGate } from "@/components/role-gate";
import { Card, Empty, ErrorNote, firstError, Loading, PageHeader, StatTile, TableWrap, td, th } from "@/components/ui";
import { useOverview, usePassbook } from "@/lib/hooks";
import { passbookLabel, standing } from "@/lib/labels";
import { formatDate } from "@/lib/time";
import type { Actor, PassbookRow } from "@/lib/types";

export function MilesScreen() {
  return <RoleGate allow={["student"]}>{(student) => <Miles key={student.id} student={student} />}</RoleGate>;
}

const ROW_TONE: Partial<Record<PassbookRow["reason"], string>> = {
  badge_bonus: "bg-yellow/10",
  badge_revoked: "bg-red/10",
};

function Miles({ student }: { student: Actor }) {
  const overview = useOverview(student);
  const passbook = usePassbook(student);

  const error = firstError(overview, passbook);
  if (error) return <ErrorNote message={error} />;
  if (overview.data === undefined || passbook.data === undefined) return <Loading />;
  const o = overview.data;

  return (
    <>
      <PageHeader title="Miles" subtitle="Your passbook: every Mile in and out, newest first." />
      <div className="mb-6 grid grid-cols-2 gap-3">
        <StatTile label="Total Miles" value={o?.total_miles ?? 0} />
        <StatTile label="Leaderboard" value={o ? standing(o.list, o.list_rank) : "—"} href="/leaderboard" />
      </div>

      {passbook.data.length === 0 ? (
        <Empty>No Miles yet. Clear skills in contests to earn your first Miles.</Empty>
      ) : (
        <Card className="p-0 md:p-0">
          <TableWrap>
            <table className="w-full min-w-[30rem]">
              <thead className="border-b border-line">
                <tr>
                  <th className={th}>Date</th>
                  <th className={th}>What for</th>
                  <th className={`${th} text-right`}>Miles</th>
                  <th className={`${th} text-right`}>Balance</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {passbook.data.map((row) => (
                  <tr key={row.entry_id} className={ROW_TONE[row.reason]}>
                    <td className={`${td} whitespace-nowrap text-muted`}>{formatDate(row.effective_at)}</td>
                    <td className={td}>{passbookLabel(row)}</td>
                    <td
                      className={`${td} whitespace-nowrap text-right font-semibold ${row.amount < 0 ? "text-red-soft" : "text-yellow"}`}
                    >
                      {row.amount > 0 ? `+${row.amount}` : row.amount}
                    </td>
                    <td className={`${td} text-right tabular-nums`}>{row.balance}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        </Card>
      )}
      <p className="mt-3 text-xs text-muted">
        Miles from a badge are dated by the interview, so the passbook follows the day each Mile was earned.
      </p>
    </>
  );
}

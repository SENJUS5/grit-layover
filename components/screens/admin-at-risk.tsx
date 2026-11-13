"use client";

import { RoleGate } from "@/components/role-gate";
import { Card, Empty, ErrorNote, firstError, Loading, PageHeader, StatTile, TableWrap, td, th } from "@/components/ui";
import { useAtRisk, useSettings } from "@/lib/hooks";
import { formatDeadline } from "@/lib/time";

export function AdminAtRiskScreen() {
  return <RoleGate allow={["admin"]}>{() => <AtRisk />}</RoleGate>;
}

function AtRisk() {
  const rows = useAtRisk();
  const settings = useSettings();

  const error = firstError(rows, settings);
  if (error) return <ErrorNote message={error} />;
  if (!rows.data || !settings.data) return <Loading />;

  const daysLeft = rows.data[0]?.days_left;

  return (
    <>
      <PageHeader title="At risk" subtitle="Registered students with no badge yet and no interview booked." />
      <div className="mb-6 grid grid-cols-2 gap-3">
        <StatTile label="Students at risk" value={rows.data.length} />
        <StatTile
          label="Badge deadline"
          value={formatDeadline(settings.data.badge_deadline)}
          sub={daysLeft !== undefined ? `${daysLeft} days left` : undefined}
        />
      </div>
      {rows.data.length === 0 ? (
        <Empty>Nobody is at risk right now.</Empty>
      ) : (
        <Card className="p-0 md:p-0">
          <TableWrap>
            <table className="w-full min-w-[36rem]">
              <thead className="border-b border-line">
                <tr>
                  <th className={th}>Student</th>
                  <th className={th}>Track</th>
                  <th className={th}>What is in the way</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {rows.data.map((r) => (
                  <tr key={r.student_id}>
                    <td className={td}>
                      <p className="font-semibold">{r.name}</p>
                      <p className="text-xs text-muted">
                        Batch {r.batch} · {r.campus} · Section {r.section}
                      </p>
                    </td>
                    <td className={td}>{r.primary_track}</td>
                    <td className={td}>
                      {r.not_eligible_reason ? (
                        <span className="text-red-soft">{r.not_eligible_reason}</span>
                      ) : (
                        <span className="text-muted">Can book, has not booked yet</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        </Card>
      )}
    </>
  );
}

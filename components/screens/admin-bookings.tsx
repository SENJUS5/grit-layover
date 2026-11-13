"use client";

import { RoleGate } from "@/components/role-gate";
import { Card, Empty, ErrorNote, Loading, PageHeader, Pill, SectionTitle, StatTile, TableWrap, td, th } from "@/components/ui";
import { useBookingStatus } from "@/lib/hooks";
import { STATE_TONE } from "@/lib/labels";
import { formatDateTime } from "@/lib/time";
import type { BookingStatusRow, JourneyState } from "@/lib/types";

export function AdminBookingsScreen() {
  return <RoleGate allow={["admin"]}>{() => <Bookings />}</RoleGate>;
}

function Bookings() {
  const status = useBookingStatus();
  if (status.error) return <ErrorNote message={status.error instanceof Error ? status.error.message : String(status.error)} />;
  if (!status.data) return <Loading />;

  const booked = status.data.filter((r) => r.is_booked);
  const notBooked = status.data.filter((r) => !r.is_booked);

  return (
    <>
      <PageHeader title="Bookings" subtitle="Every eligible student's next badge in their track, and whether it is booked." />
      <div className="grid grid-cols-2 gap-3">
        <StatTile label="Not booked yet" value={notBooked.length} />
        <StatTile label="Booked" value={booked.length} />
      </div>
      <SectionTitle count={notBooked.length}>Not booked yet</SectionTitle>
      <StatusTable rows={notBooked} empty="Every eligible student has booked." />
      <SectionTitle count={booked.length}>Booked</SectionTitle>
      <StatusTable rows={booked} empty="No bookings yet." />
    </>
  );
}

function StatusTable({ rows, empty }: { rows: BookingStatusRow[]; empty: string }) {
  if (rows.length === 0) return <Empty>{empty}</Empty>;
  return (
    <Card className="p-0 md:p-0">
      <TableWrap>
        <table className="w-full min-w-[40rem]">
          <thead className="border-b border-line">
            <tr>
              <th className={th}>Student</th>
              <th className={th}>Next badge</th>
              <th className={th}>State</th>
              <th className={th}>Interview</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {rows.map((r) => (
              <tr key={r.student_id}>
                <td className={td}>
                  <p className="font-semibold">{r.name}</p>
                  <p className="text-xs text-muted">
                    Batch {r.batch} · {r.campus} · Section {r.section}
                  </p>
                </td>
                <td className={td}>{r.next_badge ? `${r.primary_track} ${r.next_badge}` : r.primary_track}</td>
                <td className={td}>
                  <Pill tone={STATE_TONE[r.journey_state as JourneyState] ?? "yellow"}>{r.journey_state}</Pill>
                </td>
                <td className={td}>
                  {r.slot_starts_at ? (
                    <>
                      <p>{formatDateTime(r.slot_starts_at)}</p>
                      <p className="text-xs text-muted">{r.interviewer_name}</p>
                    </>
                  ) : (
                    <span className="text-muted">—</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </TableWrap>
    </Card>
  );
}

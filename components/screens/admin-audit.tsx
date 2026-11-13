"use client";

import { useState } from "react";
import { RoleGate } from "@/components/role-gate";
import { Card, Empty, ErrorNote, Field, inputClass, Loading, PageHeader, Pill } from "@/components/ui";
import { useAuditLog, usePeople } from "@/lib/hooks";
import { formatDateTime } from "@/lib/time";
import type { Actor, AuditRow } from "@/lib/types";

// The tables 002_functions.sql audits.
const TABLES = [
  "bookings",
  "interview_results",
  "badge_awards",
  "miles_ledger",
  "malpractice_cases",
  "students",
  "slots",
  "project_submissions",
  "skill_results",
  "interviewers",
  "program_settings",
];

const ACTION = { INSERT: "Added", UPDATE: "Changed", DELETE: "Deleted" } as const;
const SKIP = new Set(["id", "created_at", "updated_at"]);

export function AdminAuditScreen() {
  return <RoleGate allow={["admin"]}>{(admin) => <Audit admin={admin} />}</RoleGate>;
}

function Audit({ admin }: { admin: Actor }) {
  const [table, setTable] = useState("");
  const log = useAuditLog(admin, table || null);
  const nameOf = usePeople();

  return (
    <>
      <PageHeader title="Audit log" subtitle="Every change to the data: who made it, when, and the values before and after. Newest first." />
      <div className="mb-4 max-w-xs">
        <Field label="Table">
          <select className={inputClass} value={table} onChange={(e) => setTable(e.target.value)}>
            <option value="">All tables</option>
            {TABLES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </Field>
      </div>
      {log.error ? (
        <ErrorNote message={log.error instanceof Error ? log.error.message : String(log.error)} />
      ) : !log.data ? (
        <Loading />
      ) : log.data.length === 0 ? (
        <Empty>No changes recorded.</Empty>
      ) : (
        <>
          <p className="mb-3 text-sm text-muted">Showing the latest {log.data.length} changes.</p>
          <Card className="p-0 md:p-0">
            <ul className="divide-y divide-line">
              {log.data.map((row) => (
                <AuditItem key={row.id} row={row} who={who(row, nameOf)} />
              ))}
            </ul>
          </Card>
        </>
      )}
    </>
  );
}

function who(row: AuditRow, nameOf: (id: string | null) => string): string {
  if (row.actor_role === "system") return "System (direct SQL, e.g. the seed)";
  return `${nameOf(row.actor_id)} · ${row.actor_role}`;
}

const show = (value: unknown) => {
  const text = value === null || value === undefined ? "—" : typeof value === "string" ? value : JSON.stringify(value);
  return text.length > 60 ? `${text.slice(0, 57)}…` : text;
};

/** The fields an UPDATE changed, or the main fields of an INSERT/DELETE. */
function details(row: AuditRow): { field: string; before?: string; after: string }[] {
  if (row.action === "UPDATE" && row.before && row.after) {
    return Object.keys(row.after)
      .filter((k) => !SKIP.has(k) && JSON.stringify(row.before![k]) !== JSON.stringify(row.after![k]))
      .map((k) => ({ field: k, before: show(row.before![k]), after: show(row.after![k]) }));
  }
  const values = row.after ?? row.before ?? {};
  return Object.entries(values)
    .filter(([k, v]) => !SKIP.has(k) && v !== null)
    .slice(0, 6)
    .map(([k, v]) => ({ field: k, after: show(v) }));
}

function AuditItem({ row, who }: { row: AuditRow; who: string }) {
  return (
    <li className="px-4 py-3">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <Pill tone={row.action === "INSERT" ? "blue" : row.action === "UPDATE" ? "purple" : "red"}>{ACTION[row.action]}</Pill>
        <span className="font-semibold">{row.table_name}</span>
        <span className="font-mono text-xs text-muted">{row.record_id?.slice(0, 8)}</span>
        <span className="ml-auto text-sm text-muted">{formatDateTime(row.created_at)}</span>
      </div>
      <p className="mt-1 text-sm text-muted">By {who}</p>
      <ul className="mt-2 flex flex-wrap gap-1.5">
        {details(row).map((d) => (
          <li key={d.field} className="rounded-lg bg-surface-2 px-2 py-1 text-xs">
            <span className="text-muted">{d.field}: </span>
            {d.before !== undefined && (
              <>
                <span className="text-muted line-through">{d.before}</span> →{" "}
              </>
            )}
            <span>{d.after}</span>
          </li>
        ))}
      </ul>
    </li>
  );
}

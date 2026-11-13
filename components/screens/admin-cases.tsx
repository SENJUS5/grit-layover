"use client";

import { useState, type FormEvent } from "react";
import { RoleGate } from "@/components/role-gate";
import {
  Button,
  Card,
  DoneNote,
  Empty,
  ErrorNote,
  Field,
  firstError,
  inputClass,
  Loading,
  Meta,
  PageHeader,
  Pill,
  SectionTitle,
  textareaClass,
} from "@/components/ui";
import * as api from "@/lib/api";
import { useActiveAwards, useCases, useOverdueCases, usePeople } from "@/lib/hooks";
import { useAction, useFlash } from "@/lib/use-action";
import { formatDate, formatDateTime } from "@/lib/time";
import type { ActiveAward, Actor, CaseRow } from "@/lib/types";

export function AdminCasesScreen() {
  return <RoleGate allow={["admin"]}>{(admin) => <Cases admin={admin} />}</RoleGate>;
}

function Cases({ admin }: { admin: Actor }) {
  const cases = useCases(admin);
  const overdue = useOverdueCases();
  const awards = useActiveAwards(admin);
  const nameOf = usePeople();
  const flash = useFlash();

  const error = firstError(cases, overdue, awards);
  if (error) return <ErrorNote message={error} />;
  if (!cases.data || !overdue.data || !awards.data) return <Loading />;

  const open = cases.data.filter((c) => c.status === "open");
  const decided = cases.data.filter((c) => c.status !== "open");
  // Students still blocked by a confirmed case: one restore per student.
  const blocked = new Map<string, CaseRow[]>();
  for (const c of decided) {
    if (c.status === "confirmed" && !c.eligibility_restored_at) {
      blocked.set(c.student_id, [...(blocked.get(c.student_id) ?? []), c]);
    }
  }

  return (
    <>
      <PageHeader title="Malpractice cases" subtitle="Only admins see this screen. Students, interviewers and the leaderboard never do." />
      <DoneNote message={flash.message} />

      <SectionTitle count={overdue.data.length}>Overdue</SectionTitle>
      {overdue.data.length === 0 ? (
        <Empty>No case is past its review date.</Empty>
      ) : (
        <Card tone="red" className="p-0 md:p-0">
          <ul className="divide-y divide-line">
            {overdue.data.map((c) => (
              <li key={c.case_id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3">
                <div>
                  <p className="font-semibold">{c.student_name}</p>
                  <p className="text-sm text-muted">
                    {c.track} {c.level} · due {formatDate(c.review_due_at)}
                  </p>
                </div>
                <Pill tone="red">
                  {c.days_overdue} {c.days_overdue === 1 ? "day" : "days"} overdue
                </Pill>
              </li>
            ))}
          </ul>
        </Card>
      )}

      <SectionTitle count={open.length}>Open cases</SectionTitle>
      {open.length === 0 ? (
        <Empty>No open cases.</Empty>
      ) : (
        <div className="space-y-3">
          {open.map((c) => (
            <OpenCase key={c.case_id} item={c} admin={admin} flaggedBy={nameOf(c.flagged_by)} onDone={flash.show} />
          ))}
        </div>
      )}

      <SectionTitle count={blocked.size}>Booking blocked</SectionTitle>
      {blocked.size === 0 ? (
        <Empty>No student is blocked by a confirmed case.</Empty>
      ) : (
        <div className="space-y-3">
          {[...blocked].map(([studentId, list]) => (
            <Restore key={studentId} studentId={studentId} cases={list} admin={admin} onDone={flash.show} />
          ))}
        </div>
      )}

      <SectionTitle>Open a case</SectionTitle>
      <FlagForm awards={awards.data.filter((a) => !a.has_open_case)} admin={admin} onDone={flash.show} />

      <SectionTitle count={decided.length}>Decided</SectionTitle>
      {decided.length === 0 ? (
        <Empty>No decided cases yet.</Empty>
      ) : (
        <div className="space-y-3">
          {decided.map((c) => (
            <Card key={c.case_id}>
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div>
                  <h3 className="font-bold">{c.student_name}</h3>
                  <p className="text-sm text-muted">
                    {c.track} {c.level}
                  </p>
                </div>
                <Pill tone={c.status === "confirmed" ? "red" : "muted"}>{c.status === "confirmed" ? "Confirmed" : "Dismissed"}</Pill>
              </div>
              <div className="mt-2 space-y-1">
                <Meta label="Evidence">{c.evidence}</Meta>
                <Meta label={`Decided ${c.decided_at ? formatDate(c.decided_at) : ""} by ${nameOf(c.decided_by)}`}>
                  {c.decision_note}
                </Meta>
                {c.eligibility_restored_at && (
                  <Meta label={`Eligibility restored ${formatDate(c.eligibility_restored_at)} by ${nameOf(c.eligibility_restored_by)}`}>
                    {c.restore_note}
                  </Meta>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}
    </>
  );
}

function OpenCase(props: { item: CaseRow; admin: Actor; flaggedBy: string; onDone: (m: string) => void }) {
  const { item: c, admin } = props;
  const [note, setNote] = useState("");
  const act = useAction();

  async function decide(decision: "confirmed" | "dismissed") {
    const ok = await act.run(() => api.decideCase(admin, c.case_id, decision, note.trim()));
    if (!ok) return;
    props.onDone(
      decision === "confirmed"
        ? `Confirmed: ${c.student_name}'s ${c.track} ${c.level} badge was removed, with any later badge in the track. Booking is blocked until you restore eligibility.`
        : `Dismissed: ${c.student_name}'s case is closed and nothing changed for them.`,
    );
  }

  return (
    <Card tone={c.is_overdue ? "red" : "purple"}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h3 className="text-lg font-bold">{c.student_name}</h3>
          <p className="text-sm text-muted">
            {c.track} {c.level} · flagged by {props.flaggedBy} on {formatDateTime(c.flagged_at)}
          </p>
        </div>
        <Pill tone={c.is_overdue ? "red" : "purple"}>
          {c.is_overdue ? "Overdue" : `Review by ${formatDate(c.review_due_at)}`}
        </Pill>
      </div>
      <p className="mt-3 rounded-xl bg-surface-2 px-3 py-2 text-sm">{c.evidence}</p>
      <div className="mt-4 space-y-3">
        <Field label="Decision note" hint="Required. Confirming removes the badge (and later ones in the track) and its Miles, and blocks booking.">
          <textarea className={textareaClass} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
        <div className="flex flex-wrap gap-2">
          <Button variant="danger" disabled={act.pending} onClick={() => decide("confirmed")}>
            Confirm
          </Button>
          <Button variant="secondary" disabled={act.pending} onClick={() => decide("dismissed")}>
            Dismiss
          </Button>
        </div>
        <ErrorNote message={act.error} />
      </div>
    </Card>
  );
}

function Restore(props: { studentId: string; cases: CaseRow[]; admin: Actor; onDone: (m: string) => void }) {
  const [note, setNote] = useState("");
  const act = useAction();
  const name = props.cases[0].student_name;

  async function restore(e: FormEvent) {
    e.preventDefault();
    const ok = await act.run(() => api.restoreEligibility(props.admin, props.studentId, note.trim()));
    if (ok) props.onDone(`Restored: ${name} can book again and is back on the leaderboard. Removed badges stay removed.`);
  }

  return (
    <Card>
      <h3 className="text-lg font-bold">{name}</h3>
      <p className="text-sm text-muted">
        Confirmed case on {props.cases.map((c) => `${c.track} ${c.level}`).join(", ")}. Booking is blocked and they are off the
        leaderboard.
      </p>
      <form onSubmit={restore} className="mt-4 space-y-3">
        <Field label="Why restore eligibility?" hint="Required. Removed badges stay removed; the student can earn them again.">
          <input className={inputClass} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
        <Button type="submit" disabled={act.pending}>
          {act.pending ? "Restoring…" : "Restore eligibility"}
        </Button>
        <ErrorNote message={act.error} />
      </form>
    </Card>
  );
}

function FlagForm({ awards, admin, onDone }: { awards: ActiveAward[]; admin: Actor; onDone: (m: string) => void }) {
  const [awardId, setAwardId] = useState("");
  const [evidence, setEvidence] = useState("");
  const act = useAction();
  const award = awards.find((a) => a.award_id === awardId);

  async function flag(e: FormEvent) {
    e.preventDefault();
    const ok = await act.run(() => api.flagMalpractice(admin, awardId, evidence.trim()));
    if (ok) {
      setAwardId("");
      setEvidence("");
      onDone(
        `Case opened for ${award?.student_name}'s ${award?.track} ${award?.level} badge. The badge still counts until you decide.`,
      );
    }
  }

  return (
    <Card>
      <p className="text-sm text-muted">
        The badge keeps counting while the case is open, and the student keeps their place on the leaderboard. They see a
        private &ldquo;Under review&rdquo; notice, and their final steps wait for your decision.
      </p>
      <form onSubmit={flag} className="mt-4 space-y-3">
        <Field label="Badge">
          <select className={inputClass} value={awardId} onChange={(e) => setAwardId(e.target.value)}>
            <option value="">Choose a badge…</option>
            {awards.map((a) => (
              <option key={a.award_id} value={a.award_id}>
                {a.student_name} · {a.track} {a.level} · earned {formatDate(a.awarded_at)}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Evidence" hint="What was seen, when, and by whom.">
          <textarea className={textareaClass} value={evidence} onChange={(e) => setEvidence(e.target.value)} />
        </Field>
        <Button type="submit" variant="danger" disabled={!awardId || act.pending}>
          {act.pending ? "Opening…" : "Open a case"}
        </Button>
        <ErrorNote message={act.error} />
      </form>
    </Card>
  );
}

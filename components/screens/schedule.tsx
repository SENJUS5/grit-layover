"use client";

import { useId, useState, type FormEvent } from "react";
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
  RadioPills,
  SectionTitle,
  textareaClass,
} from "@/components/ui";
import * as api from "@/lib/api";
import { useInterviewerResults, useSchedule, useSettings } from "@/lib/hooks";
import { hasCooldown, OUTCOMES, outcomeLabel } from "@/lib/labels";
import { useNow } from "@/lib/use-now";
import { useAction, useFlash } from "@/lib/use-action";
import { addDays, formatDate, formatDateTime, formatDay, formatTime, istDay } from "@/lib/time";
import type { Actor, InterviewerResult, Outcome, ScheduleRow } from "@/lib/types";

export function ScheduleScreen() {
  return <RoleGate allow={["interviewer"]}>{(me) => <Schedule key={me.id} interviewer={me} />}</RoleGate>;
}

function Schedule({ interviewer }: { interviewer: Actor }) {
  const schedule = useSchedule(interviewer);
  const results = useInterviewerResults(interviewer);
  const settings = useSettings();
  const flash = useFlash();
  const now = useNow();

  const error = firstError(schedule, results, settings);
  if (error) return <ErrorNote message={error} />;
  if (!schedule.data || !results.data || !settings.data || now === null) return <Loading />;

  const today = istDay(now);
  const gap = settings.data.retake_gap_days;
  // Every started interview without a result, including earlier days that were missed.
  const needsResult = schedule.data.filter((r) => r.booking_status === "active" && Date.parse(r.starts_at) <= now);
  const todays = schedule.data.filter((r) => r.ist_day === today);
  const later = schedule.data.filter((r) => r.ist_day > today);
  const recordedToday = results.data.filter((r) => r.can_correct_today);
  const earlier = results.data.filter((r) => !r.can_correct_today).slice(0, 10);

  return (
    <>
      <PageHeader title="Schedule" subtitle={`${formatDay(today, true)} · all times are India time`} />
      <DoneNote message={flash.message} />

      <SectionTitle count={needsResult.length}>Needs a result</SectionTitle>
      {needsResult.length === 0 ? (
        <Empty>Nothing waiting. An interview shows up here once it has started.</Empty>
      ) : (
        <div className="space-y-3">
          {needsResult.map((row) => (
            <ResultEntry key={row.booking_id} row={row} interviewer={interviewer} retakeGap={gap} onDone={flash.show} />
          ))}
        </div>
      )}

      <SectionTitle count={todays.length}>Today</SectionTitle>
      {todays.length === 0 ? (
        <Empty>No interviews booked today.</Empty>
      ) : (
        <Card className="p-0 md:p-0">
          <ul className="divide-y divide-line">
            {todays.map((row) => (
              <ScheduleItem key={row.booking_id} row={row} now={now} />
            ))}
          </ul>
        </Card>
      )}

      <SectionTitle count={recordedToday.length}>Results you recorded today</SectionTitle>
      <p className="-mt-1 mb-3 text-sm text-muted">
        You can correct these until midnight, India time. After that, please ask an admin.
      </p>
      {recordedToday.length === 0 ? (
        <Empty>None yet today.</Empty>
      ) : (
        <div className="space-y-3">
          {recordedToday.map((r) => (
            <RecordedResult key={r.result_id} result={r} interviewer={interviewer} retakeGap={gap} onDone={flash.show} />
          ))}
        </div>
      )}

      <SectionTitle count={later.length}>Coming up</SectionTitle>
      {later.length === 0 ? (
        <Empty>No bookings on later days yet.</Empty>
      ) : (
        <Card className="p-0 md:p-0">
          <ul className="divide-y divide-line">
            {later.map((row) => (
              <ScheduleItem key={row.booking_id} row={row} now={now} withDay />
            ))}
          </ul>
        </Card>
      )}

      {earlier.length > 0 && (
        <>
          <SectionTitle>Earlier results</SectionTitle>
          <Card className="p-0 md:p-0">
            <ul className="divide-y divide-line">
              {earlier.map((r) => (
                <li key={r.result_id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3">
                  <div>
                    <p className="font-semibold">{r.student_name}</p>
                    <p className="text-sm text-muted">
                      {r.track} {r.level} · {formatDate(r.interview_held_at)}
                    </p>
                  </div>
                  <Pill tone={r.outcome === "pass" ? "yellow" : "muted"}>{outcomeLabel(r.outcome)}</Pill>
                </li>
              ))}
            </ul>
          </Card>
        </>
      )}
    </>
  );
}

function ScheduleItem({ row, now, withDay = false }: { row: ScheduleRow; now: number; withDay?: boolean }) {
  const started = Date.parse(row.starts_at) <= now;
  return (
    <li className="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3">
      <p className="w-28 shrink-0 font-semibold tabular-nums">
        {withDay ? formatDay(row.ist_day) : `${formatTime(row.starts_at)}–${formatTime(row.ends_at)}`}
        {withDay && <span className="block text-sm font-normal text-muted">{formatTime(row.starts_at)}</span>}
      </p>
      <div className="min-w-0 flex-1">
        <p className="font-semibold">{row.student_name}</p>
        <p className="text-sm text-muted">
          {row.track} {row.level}
        </p>
      </div>
      {row.outcome ? (
        <Pill tone={row.outcome === "pass" ? "yellow" : "muted"}>{outcomeLabel(row.outcome)}</Pill>
      ) : started ? (
        <Pill tone="red">Needs a result</Pill>
      ) : (
        <Pill tone="blue">Upcoming</Pill>
      )}
    </li>
  );
}

/** One started interview and the form to record its result. */
function ResultEntry(props: { row: ScheduleRow; interviewer: Actor; retakeGap: number; onDone: (m: string) => void }) {
  const { row, interviewer } = props;
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [feedback, setFeedback] = useState("");
  const [retake, setRetake] = useState("");
  const act = useAction();
  const name = useId();
  const heldDay = istDay(row.starts_at);
  const cooldown = outcome !== null && hasCooldown(outcome);

  async function save(e: FormEvent) {
    e.preventDefault();
    if (!outcome) return;
    const ok = await act.run(() =>
      api.recordResult(interviewer, row.booking_id, interviewer.id, outcome, feedback.trim(), cooldown && retake ? retake : null),
    );
    if (ok) {
      props.onDone(
        `Saved: ${outcomeLabel(outcome)} for ${row.student_name} (${row.track} ${row.level}). They can see it now.`,
      );
    }
  }

  return (
    <Card tone="red">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h3 className="text-lg font-bold">{row.student_name}</h3>
          <p className="text-sm text-muted">
            {row.track} {row.level} · {formatDateTime(row.starts_at)}
          </p>
        </div>
      </div>
      <form onSubmit={save} className="mt-4 space-y-4">
        <RadioPills legend="Outcome" name={name} options={OUTCOMES} value={outcome} onChange={setOutcome} />
        <Field label="Feedback for the student" hint="They read this in their result message. Be specific and kind.">
          <textarea className={textareaClass} value={feedback} onChange={(e) => setFeedback(e.target.value)} />
        </Field>
        {cooldown && (
          <Field
            label="Can book again from (optional)"
            hint={`Leave empty for the usual ${props.retakeGap} days: ${formatDay(addDays(heldDay, props.retakeGap), true)}.`}
          >
            <input
              type="date"
              className={`${inputClass} max-w-52`}
              min={addDays(heldDay, 1)}
              value={retake}
              onChange={(e) => setRetake(e.target.value)}
            />
          </Field>
        )}
        <Button type="submit" disabled={!outcome || act.pending}>
          {act.pending ? "Saving…" : "Save result"}
        </Button>
        <ErrorNote message={act.error} />
      </form>
    </Card>
  );
}

/** A result recorded today, with the same-day correction form. */
function RecordedResult(props: { result: InterviewerResult; interviewer: Actor; retakeGap: number; onDone: (m: string) => void }) {
  const { result: r, interviewer } = props;
  const [open, setOpen] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [reason, setReason] = useState("");
  const [retake, setRetake] = useState("");
  const act = useAction();
  const name = useId();
  const wasPass = r.outcome === "pass";
  // The database's rule: a corrected pass never carries a retake date.
  const cooldown = !wasPass && outcome !== null && hasCooldown(outcome);
  const heldDay = istDay(r.interview_held_at);

  async function save(e: FormEvent) {
    e.preventDefault();
    if (!outcome) return;
    const ok = await act.run(() => api.correctResult(interviewer, r.result_id, outcome, reason.trim(), cooldown && retake ? retake : null));
    if (ok) {
      setOpen(false);
      setOutcome(null);
      setReason("");
      setRetake("");
      props.onDone(`Corrected: ${r.student_name}'s ${r.track} ${r.level} result is now ${outcomeLabel(outcome)}.`);
    }
  }

  return (
    <Card>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h3 className="text-lg font-bold">{r.student_name}</h3>
          <p className="text-sm text-muted">
            {r.track} {r.level} · held {formatDateTime(r.interview_held_at)}
          </p>
        </div>
        <Pill tone={r.outcome === "pass" ? "yellow" : "muted"}>{outcomeLabel(r.outcome)}</Pill>
      </div>
      <div className="mt-2 space-y-1">
        {r.feedback && <Meta label="Feedback">{r.feedback}</Meta>}
        {r.retake_after && <Meta label="Can book again from">{formatDay(r.retake_after, true)}</Meta>}
        {r.corrected_at && (
          <Meta label={`Corrected ${formatTime(r.corrected_at)}`}>{r.correction_reason}</Meta>
        )}
      </div>

      {!open ? (
        <Button variant="secondary" className="mt-4" onClick={() => setOpen(true)}>
          Correct this result
        </Button>
      ) : (
        <form onSubmit={save} className="mt-4 space-y-4 border-t border-line pt-4">
          <RadioPills
            legend="Change the outcome to"
            name={name}
            options={OUTCOMES.filter((o) => o.value !== r.outcome)}
            value={outcome}
            onChange={setOutcome}
          />
          {wasPass && (
            <p className="rounded-xl bg-red/10 px-3 py-2 text-sm text-red-soft">
              Changing a pass removes this badge and its Miles, and any later badge in the same track. The student can book
              again any time.
            </p>
          )}
          <Field label="Reason for the correction" hint="The student will see this reason.">
            <input className={inputClass} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
          {cooldown && (
            <Field
              label="Can book again from (optional)"
              hint={`Leave empty for the usual ${props.retakeGap} days: ${formatDay(addDays(heldDay, props.retakeGap), true)}.`}
            >
              <input
                type="date"
                className={`${inputClass} max-w-52`}
                min={addDays(heldDay, 1)}
                value={retake}
                onChange={(e) => setRetake(e.target.value)}
              />
            </Field>
          )}
          <div className="flex flex-wrap gap-2">
            <Button type="submit" variant={wasPass ? "danger" : "primary"} disabled={!outcome || act.pending}>
              {act.pending ? "Saving…" : "Save correction"}
            </Button>
            <Button
              variant="ghost"
              onClick={() => {
                setOpen(false);
                act.reset();
              }}
            >
              Never mind
            </Button>
          </div>
          <ErrorNote message={act.error} />
        </form>
      )}
    </Card>
  );
}

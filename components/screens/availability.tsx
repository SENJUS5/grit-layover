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
  PageHeader,
  Pill,
  SectionTitle,
} from "@/components/ui";
import * as api from "@/lib/api";
import { useInterviewerSlots, useSettings } from "@/lib/hooks";
import { useNow } from "@/lib/use-now";
import { useAction, useFlash } from "@/lib/use-action";
import { addDays, formatDay, formatTime, istDay, istToIso } from "@/lib/time";
import type { Actor, InterviewerSlot } from "@/lib/types";

export function AvailabilityScreen() {
  return <RoleGate allow={["interviewer"]}>{(me) => <Availability key={me.id} interviewer={me} />}</RoleGate>;
}

function Availability({ interviewer }: { interviewer: Actor }) {
  const slots = useInterviewerSlots(interviewer);
  const settings = useSettings();
  const flash = useFlash();
  const now = useNow();
  const create = useAction();
  const [day, setDay] = useState<string | null>(null);
  const [time, setTime] = useState("10:00");

  const error = firstError(slots, settings);
  if (error) return <ErrorNote message={error} />;
  if (!slots.data || !settings.data || now === null) return <Loading />;

  const today = istDay(now);
  const chosenDay = day ?? addDays(today, 1);
  const minutes = settings.data.slot_minutes;

  async function add(e: FormEvent) {
    e.preventDefault();
    const ok = await create.run(() => api.createSlot(interviewer, interviewer.id, istToIso(chosenDay, time)));
    if (ok) flash.show(`Slot added: ${formatDay(chosenDay)}, ${time} for ${minutes} minutes. Students can book it now.`);
  }

  const days = new Map<string, InterviewerSlot[]>();
  for (const slot of slots.data) days.set(slot.ist_day, [...(days.get(slot.ist_day) ?? []), slot]);

  return (
    <>
      <PageHeader title="Availability" subtitle="Add the slots students can book. All times are India time." />
      <DoneNote message={flash.message} />

      <Card>
        <h2 className="text-lg font-bold">Add a slot</h2>
        <form onSubmit={add} className="mt-3 flex flex-wrap items-end gap-3">
          <Field label="Day">
            <input
              type="date"
              className={inputClass}
              min={today}
              value={chosenDay}
              onChange={(e) => setDay(e.target.value)}
              required
            />
          </Field>
          <Field label="Start time">
            <input type="time" className={inputClass} value={time} onChange={(e) => setTime(e.target.value)} required />
          </Field>
          <Button type="submit" disabled={create.pending}>
            {create.pending ? "Adding…" : `Add ${minutes}-minute slot`}
          </Button>
        </form>
        <ErrorNote message={create.error} />
      </Card>

      <SectionTitle count={slots.data.length}>Your slots from today</SectionTitle>
      {slots.data.length === 0 ? (
        <Empty>No slots yet. Add one above.</Empty>
      ) : (
        <div className="space-y-5">
          {[...days].map(([d, list]) => (
            <div key={d}>
              <h3 className="mb-2 text-sm font-semibold text-muted">{formatDay(d, true)}</h3>
              <Card className="p-0 md:p-0">
                <ul className="divide-y divide-line">
                  {list.map((slot) => (
                    <SlotItem key={slot.slot_id} slot={slot} interviewer={interviewer} now={now} onDone={flash.show} />
                  ))}
                </ul>
              </Card>
            </div>
          ))}
        </div>
      )}
    </>
  );
}

function SlotItem(props: { slot: InterviewerSlot; interviewer: Actor; now: number; onDone: (m: string) => void }) {
  const { slot, interviewer } = props;
  const [withdrawing, setWithdrawing] = useState(false);
  const [reason, setReason] = useState("");
  const act = useAction();
  const started = Date.parse(slot.starts_at) <= props.now;
  const booked = slot.booking_status === "active";
  const canWithdraw = slot.status === "open" && !started && slot.booking_status !== "completed";
  const when = `${formatDay(slot.ist_day)}, ${formatTime(slot.starts_at)}`;

  async function withdraw(e: FormEvent) {
    e.preventDefault();
    const ok = await act.run(() => api.withdrawSlot(interviewer, slot.slot_id, interviewer.id, reason.trim()));
    if (ok) {
      props.onDone(
        booked
          ? `Withdrawn: ${when}. ${slot.student_name}'s booking was cancelled with your reason, and they can book another slot.`
          : `Withdrawn: ${when}.`,
      );
    }
  }

  return (
    <li className="px-4 py-3">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1">
        <p className="w-28 shrink-0 font-semibold tabular-nums">
          {formatTime(slot.starts_at)}–{formatTime(slot.ends_at)}
        </p>
        <div className="min-w-0 flex-1 text-sm">
          {slot.status === "withdrawn" ? (
            <span className="text-muted">Reason: {slot.withdraw_reason}</span>
          ) : slot.booking_status ? (
            <span>
              <strong>{slot.student_name}</strong>{" "}
              <span className="text-muted">
                · {slot.track} {slot.level}
              </span>
            </span>
          ) : (
            <span className="text-muted">{started ? "Not booked" : "Open for booking"}</span>
          )}
        </div>
        {slot.status === "withdrawn" ? (
          <Pill>Withdrawn</Pill>
        ) : slot.booking_status === "completed" ? (
          <Pill>Done</Pill>
        ) : booked ? (
          <Pill tone="blue">Booked</Pill>
        ) : started ? (
          <Pill>Ended</Pill>
        ) : (
          <Pill tone="yellow">Open</Pill>
        )}
        {canWithdraw && !withdrawing && (
          <Button variant="ghost" className="px-2" onClick={() => setWithdrawing(true)}>
            Withdraw
          </Button>
        )}
      </div>
      {withdrawing && (
        <form onSubmit={withdraw} className="mt-3 space-y-3 rounded-xl bg-surface-2 p-3">
          {booked && (
            <p className="text-sm text-red-soft">
              {slot.student_name} has booked this slot. Their booking will be cancelled and they will see your reason.
            </p>
          )}
          <Field label="Why are you withdrawing this slot?">
            <input className={inputClass} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
          <div className="flex flex-wrap gap-2">
            <Button type="submit" variant="danger" disabled={act.pending}>
              {act.pending ? "Withdrawing…" : "Withdraw slot"}
            </Button>
            <Button
              variant="ghost"
              onClick={() => {
                setWithdrawing(false);
                act.reset();
              }}
            >
              Keep it
            </Button>
          </div>
          <ErrorNote message={act.error} />
        </form>
      )}
    </li>
  );
}

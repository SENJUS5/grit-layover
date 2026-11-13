"use client";

import { Circle, CircleCheck } from "lucide-react";
import Link from "next/link";
import { useId, useState, type FormEvent } from "react";
import { RoleGate } from "@/components/role-gate";
import {
  Button,
  Card,
  DoneNote,
  Empty,
  ErrorNote,
  ExternalLink,
  Field,
  firstError,
  inputClass,
  Loading,
  PageHeader,
  Pill,
  SectionTitle,
} from "@/components/ui";
import * as api from "@/lib/api";
import { useAvailableSlots, useBookings, useJourney, useProjects, useRequirements, useSettings } from "@/lib/hooks";
import { readiness, requirementStatus, STATE_TONE } from "@/lib/labels";
import { useNow } from "@/lib/use-now";
import { useAction, useFlash } from "@/lib/use-action";
import { formatDate, formatDateTime, formatDay, formatTime } from "@/lib/time";
import type { Actor, AvailableSlot, BookingRow, JourneyRow, ProjectRow, RequirementRow } from "@/lib/types";

export function InterviewsScreen() {
  return <RoleGate allow={["student"]}>{(student) => <Interviews key={student.id} student={student} />}</RoleGate>;
}

function Interviews({ student }: { student: Actor }) {
  const journey = useJourney(student);
  const requirements = useRequirements(student);
  const projects = useProjects(student);
  const bookings = useBookings(student);
  const slots = useAvailableSlots();
  const settings = useSettings();
  const flash = useFlash();
  const now = useNow();

  const error = firstError(journey, requirements, projects, bookings, slots, settings);
  if (error) return <ErrorNote message={error} />;
  if (!journey.data || !requirements.data || !projects.data || !bookings.data || !slots.data || !settings.data || now === null) {
    return <Loading />;
  }

  const openSlots = slots.data;
  const primaryTrack = journey.data[0]?.primary_track;
  const track = journey.data.filter((j) => j.track === primaryTrack);
  // The badge to work on: the first one in the track the student does not hold.
  const next = track.find((j) => j.state !== "Passed" && j.state !== "Under review");
  const otherBookings = bookings.data.filter((b) => b.badge_id !== next?.badge_id);

  return (
    <>
      <PageHeader title="Interviews" subtitle="Check you are ready, then book, move or cancel your badge interview." />
      <DoneNote message={flash.message} />

      {next ? (
        <NextBadge
          key={next.badge_id}
          student={student}
          row={next}
          previous={track.find((j) => j.sequence === next.sequence - 1)}
          requirements={requirements.data.filter((r) => r.badge_id === next.badge_id)}
          project={projects.data.find((p) => p.badge_id === next.badge_id)}
          booking={bookings.data.find((b) => b.badge_id === next.badge_id)}
          slots={openSlots}
          noticeHours={settings.data.min_booking_notice_hours}
          now={now}
          onDone={flash.show}
        />
      ) : (
        <Card className="mt-6">
          <h2 className="text-lg font-bold">You hold every open {primaryTrack} badge</h2>
          <p className="mt-1 text-sm text-muted">The next levels open later. Your badges are on your Dashboard.</p>
        </Card>
      )}

      {otherBookings.length > 0 && (
        <>
          <SectionTitle count={otherBookings.length}>Other bookings</SectionTitle>
          <div className="space-y-3">
            {otherBookings.map((b) => (
              <BookingPanel key={b.badge_id} student={student} booking={b} slots={openSlots} now={now} onDone={flash.show} />
            ))}
          </div>
        </>
      )}
    </>
  );
}

function NextBadge(props: {
  student: Actor;
  row: JourneyRow;
  previous?: JourneyRow;
  requirements: RequirementRow[];
  project?: ProjectRow;
  booking?: BookingRow;
  slots: AvailableSlot[];
  noticeHours: number;
  now: number;
  onDone: (message: string) => void;
}) {
  const { student, row, booking, onDone } = props;
  const book = useAction();
  const badge = `${row.track} ${row.level}`;

  async function bookSlot(slot: AvailableSlot) {
    const ok = await book.run(() => api.bookSlot(student, student.id, row.badge_id, slot.slot_id));
    if (ok) onDone(`Booked: ${badge} on ${formatDateTime(slot.starts_at)} with ${slot.interviewer_name}.`);
  }

  return (
    <Card tone={row.state === "Ready to book" ? "yellow" : undefined} className="mt-2">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-muted">Your next badge</p>
          <h2 className="text-2xl font-bold">{badge}</h2>
        </div>
        <Pill tone={STATE_TONE[row.state]}>{row.state}</Pill>
      </div>

      {/* Readiness */}
      <h3 className="mt-5 font-semibold">{readiness(props.requirements)}</h3>
      {!row.previous_badge_held && props.previous && (
        <p className="mt-1 text-sm text-red-soft">
          Earn {row.track} {props.previous.level} first. Badges in a track are earned in order.
        </p>
      )}
      <ul className="mt-2 grid gap-1.5 sm:grid-cols-2">
        {props.requirements.map((r) => (
          <li key={r.skill_name} className="flex items-start gap-2 rounded-xl bg-surface-2 px-3 py-2">
            {r.is_cleared ? (
              <CircleCheck size={18} className="mt-0.5 shrink-0 text-yellow" aria-label="Cleared" />
            ) : (
              <Circle size={18} className="mt-0.5 shrink-0 text-muted" aria-label="Not cleared" />
            )}
            <div>
              <p className="text-sm font-semibold">
                {r.skill_name} L{r.required_level}
              </p>
              <p className="text-xs text-muted">{requirementStatus(r)}</p>
            </div>
          </li>
        ))}
      </ul>

      {props.project && <ProjectBox key={props.project.submission_id ?? "new"} student={student} project={props.project} onDone={onDone} />}

      {/* Booking */}
      <div className="mt-6 border-t border-line pt-5">
        {booking ? (
          <BookingPanel student={student} booking={booking} slots={props.slots} now={props.now} onDone={onDone} />
        ) : row.state === "Ready to book" ? (
          <>
            <h3 className="font-semibold">Pick a slot</h3>
            <p className="mb-3 text-sm text-muted">Open slots, in India time. Book at least {props.noticeHours} hours ahead.</p>
            <SlotPicker slots={props.slots} confirmLabel="Book this slot" pending={book.pending} onConfirm={bookSlot} />
            <ErrorNote message={book.error} />
          </>
        ) : row.state === "Retake later" ? (
          <p className="text-sm">
            You can book again from <strong>{formatDay(row.retake_after!, true)}</strong>. Your interviewer&apos;s feedback is
            in{" "}
            <Link href="/messages" className="underline">
              Messages
            </Link>
            .
          </p>
        ) : row.state === "Not eligible" ? (
          <p className="text-sm">Booking is closed for now: {row.not_eligible_reason}.</p>
        ) : row.state === "Revoked" ? (
          <p className="text-sm">Booking is paused for now. The GRIT team will tell you when you can book again.</p>
        ) : row.state === "Project pending" ? (
          <p className="text-sm text-muted">Slots open for booking once your project is approved.</p>
        ) : (
          <p className="text-sm text-muted">Slots open for booking once every skill above is cleared.</p>
        )}
      </div>
    </Card>
  );
}

function ProjectBox({ student, project, onDone }: { student: Actor; project: ProjectRow; onDone: (m: string) => void }) {
  const [link, setLink] = useState("");
  const act = useAction();
  const badge = `${project.track} ${project.level}`;

  async function submit(e: FormEvent) {
    e.preventDefault();
    const ok = await act.run(() => api.submitProject(student, student.id, project.badge_id, link.trim()));
    if (ok) onDone(`Project sent for ${badge}. An interviewer will review it.`);
  }

  return (
    <div className="mt-5 rounded-xl border border-line p-4">
      <h3 className="font-semibold">Project</h3>
      {project.status === "approved" ? (
        <p className="mt-1 text-sm">
          <CircleCheck size={16} className="mr-1 inline text-yellow" aria-hidden />
          Approved on {formatDate(project.reviewed_at!)}.
        </p>
      ) : project.status === "submitted" ? (
        <p className="mt-1 text-sm text-muted">
          Sent on {formatDate(project.submitted_at!)}: <ExternalLink href={project.link!} />. Waiting for review.
        </p>
      ) : (
        <form onSubmit={submit} className="mt-2 space-y-3">
          {project.status === "rejected" && (
            <p className="text-sm">
              Your last project was not approved
              {project.review_note ? (
                <>
                  : <span className="text-muted">&ldquo;{project.review_note}&rdquo;</span>
                </>
              ) : (
                "."
              )}{" "}
              Send a new link when it is ready.
            </p>
          )}
          <Field label="Link to your project" hint="For example your GitHub repository or a video of the robot working.">
            <input
              className={inputClass}
              value={link}
              onChange={(e) => setLink(e.target.value)}
              inputMode="url"
              autoComplete="url"
              placeholder="https://"
            />
          </Field>
          <Button type="submit" disabled={act.pending}>
            {act.pending ? "Sending…" : "Submit project"}
          </Button>
          <ErrorNote message={act.error} />
        </form>
      )}
    </div>
  );
}

/** A booked interview, with reschedule and cancel until it starts. */
function BookingPanel(props: { student: Actor; booking: BookingRow; slots: AvailableSlot[]; now: number; onDone: (m: string) => void }) {
  const { student, booking, onDone } = props;
  const [mode, setMode] = useState<"idle" | "reschedule" | "cancel">("idle");
  const [reason, setReason] = useState("");
  const act = useAction();
  const reasonId = useId();
  const badge = `${booking.track} ${booking.level}`;
  const started = Date.parse(booking.starts_at) <= props.now;

  function close() {
    setMode("idle");
    act.reset();
  }

  async function move(slot: AvailableSlot) {
    const ok = await act.run(() => api.rescheduleBooking(student, booking.booking_id, slot.slot_id));
    if (ok) {
      setMode("idle");
      onDone(`Moved: ${badge} is now on ${formatDateTime(slot.starts_at)} with ${slot.interviewer_name}.`);
    }
  }

  async function cancel(e: FormEvent) {
    e.preventDefault();
    const ok = await act.run(() => api.cancelBooking(student, booking.booking_id, reason.trim()));
    if (ok) onDone(`Cancelled: your ${badge} interview on ${formatDateTime(booking.starts_at)}. You can book a new slot any time.`);
  }

  return (
    <div className="rounded-xl border border-blue/50 bg-blue/10 p-4">
      <p className="text-xs font-semibold uppercase tracking-wider text-blue-soft">{started ? "Interview held" : "Booked"}</p>
      <p className="mt-1 text-lg font-bold">
        {formatDateTime(booking.starts_at)}–{formatTime(booking.ends_at)}
      </p>
      <p className="text-sm text-muted">
        {badge} with {booking.interviewer_name}
      </p>

      {started ? (
        <p className="mt-3 text-sm">Your interviewer will add the result soon. It will show up in Messages.</p>
      ) : mode === "idle" ? (
        <div className="mt-4 flex flex-wrap gap-2">
          <Button variant="secondary" onClick={() => setMode("reschedule")}>
            Reschedule
          </Button>
          <Button variant="ghost" onClick={() => setMode("cancel")}>
            Cancel interview
          </Button>
        </div>
      ) : mode === "reschedule" ? (
        <div className="mt-4">
          <p className="mb-3 text-sm text-muted">Pick a new slot. Your current slot stays booked until the move is done.</p>
          <SlotPicker slots={props.slots} confirmLabel="Move my interview here" pending={act.pending} onConfirm={move} />
          <ErrorNote message={act.error} />
          <Button variant="ghost" className="mt-3" onClick={close}>
            Keep my current slot
          </Button>
        </div>
      ) : (
        <form onSubmit={cancel} className="mt-4 space-y-3">
          <label htmlFor={reasonId} className="block text-sm font-medium">
            Why are you cancelling?
          </label>
          <input
            id={reasonId}
            className={inputClass}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="For example: exam clash"
          />
          <div className="flex flex-wrap gap-2">
            <Button type="submit" variant="danger" disabled={act.pending}>
              {act.pending ? "Cancelling…" : "Cancel interview"}
            </Button>
            <Button variant="ghost" onClick={close}>
              Keep it
            </Button>
          </div>
          <ErrorNote message={act.error} />
        </form>
      )}
    </div>
  );
}

/** Open slots grouped by IST day. Pick one, then confirm. */
function SlotPicker(props: {
  slots: AvailableSlot[];
  confirmLabel: string;
  pending: boolean;
  onConfirm: (slot: AvailableSlot) => void;
}) {
  const [picked, setPicked] = useState<string | null>(null);
  const chosen = props.slots.find((s) => s.slot_id === picked);

  if (props.slots.length === 0) {
    return <Empty>No open slots right now. New slots show up here as interviewers add them.</Empty>;
  }

  const days = new Map<string, AvailableSlot[]>();
  for (const slot of props.slots) days.set(slot.ist_day, [...(days.get(slot.ist_day) ?? []), slot]);

  return (
    <div className="space-y-4">
      {[...days].map(([day, list]) => (
        <div key={day}>
          <h4 className="mb-2 text-sm font-semibold text-muted">{formatDay(day)}</h4>
          <div className="flex flex-wrap gap-2">
            {list.map((s) => (
              <button
                key={s.slot_id}
                type="button"
                aria-pressed={picked === s.slot_id}
                onClick={() => setPicked(s.slot_id)}
                className="rounded-full border border-line bg-surface-2 px-3 py-1.5 text-sm font-semibold transition hover:border-muted aria-pressed:border-yellow aria-pressed:bg-yellow aria-pressed:text-bg"
              >
                {formatTime(s.starts_at)}
                <span className="font-normal opacity-80"> · {s.interviewer_name}</span>
              </button>
            ))}
          </div>
          {chosen && chosen.ist_day === day && (
            <div className="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-yellow/50 bg-yellow/10 p-3">
              <p className="text-sm">
                <strong>
                  {formatDay(day)}, {formatTime(chosen.starts_at)}–{formatTime(chosen.ends_at)}
                </strong>{" "}
                with {chosen.interviewer_name}
              </p>
              <Button disabled={props.pending} onClick={() => props.onConfirm(chosen)}>
                {props.pending ? "Saving…" : props.confirmLabel}
              </Button>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

"use client";

import { ShieldQuestion } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { RoleGate } from "@/components/role-gate";
import { TripChecklist } from "@/components/trip-checklist";
import { ButtonLink, Card, ErrorNote, firstError, Loading, PageHeader, Pill, SectionTitle, StatTile } from "@/components/ui";
import { WhatChanged } from "@/components/what-changed";
import { homeFor, useActor } from "@/lib/actor";
import { useJourney, useLastChange, useOverview, useProjects, useRequirements } from "@/lib/hooks";
import { readiness, STATE_TONE } from "@/lib/labels";
import { UNDER_REVIEW_NOTICE } from "@/lib/messages";
import { formatDate, formatDateTime, formatDay } from "@/lib/time";
import type { Actor, JourneyRow, ProjectRow, RequirementRow } from "@/lib/types";

export function HomeScreen() {
  const { actor } = useActor();
  const router = useRouter();
  // "/" is the student Dashboard; interviewers and the admin have their own home.
  const elsewhere = actor && actor.role !== "student" ? homeFor(actor.role) : null;
  useEffect(() => {
    if (elsewhere) router.replace(elsewhere);
  }, [elsewhere, router]);
  if (elsewhere) return <Loading />;
  return <RoleGate allow={["student"]}>{(student) => <Dashboard key={student.id} student={student} />}</RoleGate>;
}

function Dashboard({ student }: { student: Actor }) {
  const overview = useOverview(student);
  const journey = useJourney(student);
  const lastChange = useLastChange(student);
  const requirements = useRequirements(student);
  const projects = useProjects(student);

  const error = firstError(overview, journey, lastChange, requirements, projects);
  if (error) return <ErrorNote message={error} />;
  if (
    overview.data === undefined ||
    journey.data === undefined ||
    lastChange.data === undefined ||
    requirements.data === undefined ||
    projects.data === undefined
  ) {
    return <Loading />;
  }
  const o = overview.data;
  if (!o) return <ErrorNote message="This student is not in the database any more. Choose someone else in View as." />;

  const reqs = requirements.data;
  const projs = projects.data;
  const track = journey.data.filter((j) => j.track === o.primary_track);
  const onHold = journey.data.some((j) => j.final_steps_on_hold);

  return (
    <>
      <PageHeader title={`Hi, ${o.name.split(" ")[0]}`} subtitle={`${o.primary_track} track`} />

      {onHold && (
        // Private: only on the student's own Dashboard, never on shared screens.
        <Card tone="purple" className="mb-6">
          <h2 className="flex items-center gap-2 text-lg font-bold">
            <ShieldQuestion size={20} className="text-purple-soft" aria-hidden />
            {UNDER_REVIEW_NOTICE.title}
          </h2>
          <p className="mt-1 text-sm text-muted">{UNDER_REVIEW_NOTICE.body}</p>
        </Card>
      )}

      {lastChange.data && <WhatChanged change={lastChange.data} deadline={o.badge_deadline} />}

      <div className="grid grid-cols-2 gap-3">
        <StatTile label="Miles" value={o.total_miles} sub="Open passbook" href="/miles" />
        <StatTile
          label="Leaderboard"
          value={o.list ? `#${o.list_rank}` : "—"}
          sub={o.list ?? "Not on the leaderboard"}
          href="/leaderboard"
        />
      </div>

      <SectionTitle>Your {o.primary_track} journey</SectionTitle>
      <div className="grid gap-3 md:grid-cols-2">
        {track.map((row) => (
          <JourneyCard
            key={row.badge_id}
            row={row}
            previous={track.find((j) => j.sequence === row.sequence - 1)}
            requirements={reqs.filter((r) => r.badge_id === row.badge_id)}
            project={projs.find((p) => p.badge_id === row.badge_id)}
          />
        ))}
      </div>

      <SectionTitle>Trip checklist</SectionTitle>
      <TripChecklist overview={o} />
    </>
  );
}

type Step = { text: string; action?: { href: string; label: string; primary?: boolean } };

/** What this badge means for the student right now, and the one thing to do next. */
function nextStep(row: JourneyRow, previous: JourneyRow | undefined, reqs: RequirementRow[], project?: ProjectRow): Step {
  switch (row.state) {
    case "Passed":
      return { text: "Badge earned. It counts towards your trip." };
    case "Under review":
      return { text: "Badge earned. It still counts while the review is open." };
    case "Revoked":
      return {
        text: "This badge was removed. Booking is paused for now.",
        action: { href: "/messages", label: "Read the message" },
      };
    case "Not eligible":
      return { text: `Booking is closed for now: ${row.not_eligible_reason}.` };
    case "Not ready":
      if (!row.previous_badge_held && previous) return { text: `Earn ${row.track} ${previous.level} first.` };
      return { text: `${readiness(reqs)}.`, action: { href: "/interviews", label: "See your skills" } };
    case "Project pending":
      if (project?.status === "submitted") return { text: "Your project is waiting for review. Booking opens once it is approved." };
      return {
        text: project?.status === "rejected" ? "Your project was not approved yet. See the note and send a new link." : "Submit your project to unlock booking.",
        action: { href: "/interviews", label: "Submit project", primary: true },
      };
    case "Ready to book":
      return { text: "All skills cleared.", action: { href: "/interviews", label: "Book your interview", primary: true } };
    case "Booked":
      return {
        text: `Interview ${formatDateTime(row.slot_starts_at!)} with ${row.interviewer_name}.`,
        action: { href: "/interviews", label: "Reschedule or cancel" },
      };
    case "Waiting for result":
      return {
        text: `Interview on ${formatDate(row.slot_starts_at!)}. Your result is on the way.`,
        action: { href: "/messages", label: "Open messages" },
      };
    case "Retake later":
      return {
        text: `You can book again from ${formatDay(row.retake_after!, true)}.`,
        action: { href: "/messages", label: "Read your feedback" },
      };
  }
}

function JourneyCard(props: { row: JourneyRow; previous?: JourneyRow; requirements: RequirementRow[]; project?: ProjectRow }) {
  const { row } = props;
  const step = nextStep(row, props.previous, props.requirements, props.project);
  return (
    <Card tone={row.state === "Ready to book" ? "yellow" : undefined}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted">Badge {row.sequence}</p>
          <h3 className="text-xl font-bold">{row.level}</h3>
        </div>
        <Pill tone={STATE_TONE[row.state]}>{row.state}</Pill>
      </div>
      <p className="mt-2 text-sm text-muted">{step.text}</p>
      {step.action && (
        <ButtonLink href={step.action.href} variant={step.action.primary ? "primary" : "secondary"} className="mt-4">
          {step.action.label}
        </ButtonLink>
      )}
    </Card>
  );
}

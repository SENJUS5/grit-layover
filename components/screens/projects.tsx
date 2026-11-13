"use client";

import { useState } from "react";
import { RoleGate } from "@/components/role-gate";
import { Button, Card, DoneNote, Empty, ErrorNote, ExternalLink, Field, inputClass, Loading, PageHeader } from "@/components/ui";
import * as api from "@/lib/api";
import { useProjectQueue } from "@/lib/hooks";
import { useAction, useFlash } from "@/lib/use-action";
import { formatDateTime } from "@/lib/time";
import type { Actor, ProjectQueueRow } from "@/lib/types";

export function ProjectsScreen() {
  return <RoleGate allow={["interviewer", "admin"]}>{(actor) => <Projects key={actor.id} actor={actor} />}</RoleGate>;
}

function Projects({ actor }: { actor: Actor }) {
  const queue = useProjectQueue(actor);
  const flash = useFlash();

  if (queue.error) return <ErrorNote message={queue.error instanceof Error ? queue.error.message : String(queue.error)} />;
  if (!queue.data) return <Loading />;

  return (
    <>
      <PageHeader title="Project review" subtitle="Robotics badges need an approved project before the student can book." />
      <DoneNote message={flash.message} />
      {queue.data.length === 0 ? (
        <Empty>No projects waiting for review.</Empty>
      ) : (
        <div className="space-y-3">
          {queue.data.map((item) => (
            <ProjectReview key={item.submission_id} item={item} actor={actor} onDone={flash.show} />
          ))}
        </div>
      )}
    </>
  );
}

function ProjectReview({ item, actor, onDone }: { item: ProjectQueueRow; actor: Actor; onDone: (m: string) => void }) {
  const [note, setNote] = useState("");
  const act = useAction();
  const badge = `${item.track} ${item.level}`;

  async function decide(decision: "approved" | "rejected") {
    const ok = await act.run(() => api.reviewProject(actor, item.submission_id, decision, note.trim()));
    if (!ok) return;
    onDone(
      decision === "approved"
        ? `Approved: ${item.student_name}'s ${badge} project. They can book the interview now.`
        : `Sent back: ${item.student_name} can send a new link for ${badge}.`,
    );
  }

  return (
    <Card>
      <h2 className="text-lg font-bold">{item.student_name}</h2>
      <p className="text-sm text-muted">
        {badge} · sent {formatDateTime(item.submitted_at)}
      </p>
      <p className="mt-2 text-sm">
        <ExternalLink href={item.link} />
      </p>
      <div className="mt-4 space-y-3">
        <Field label="Note for the student" hint="Optional when approving. If you send it back, say what to fix.">
          <input className={inputClass} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
        <div className="flex flex-wrap gap-2">
          <Button disabled={act.pending} onClick={() => decide("approved")}>
            Approve
          </Button>
          <Button variant="secondary" disabled={act.pending} onClick={() => decide("rejected")}>
            Send back
          </Button>
        </div>
        <ErrorNote message={act.error} />
      </div>
    </Card>
  );
}

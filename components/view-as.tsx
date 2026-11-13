"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";
import useSWR from "swr";
import { ADMIN, homeFor, setActor, useActor } from "@/lib/actor";
import * as api from "@/lib/api";
import type { Actor, Role } from "@/lib/types";

/** The "View as" switcher: any seeded student, an active interviewer, or the admin. */
export function ViewAs({ large = false }: { large?: boolean }) {
  const { actor, ready } = useActor();
  const router = useRouter();
  const students = useSWR(ready ? ["directory"] : null, api.getStudentDirectory);
  const interviewers = useSWR(ready ? ["interviewers"] : null, api.getInterviewers);

  function choose(value: string) {
    const [role, id] = value.split("|") as [Role, string];
    const name =
      role === "student"
        ? students.data?.find((s) => s.student_id === id)?.name
        : role === "interviewer"
          ? interviewers.data?.find((i) => i.id === id)?.name
          : ADMIN.name;
    if (!name) return;
    const next: Actor = { role, id, name };
    setActor(next);
    // Same role (e.g. one student to another): stay on this screen. New role: go to its home.
    if (actor?.role !== role) router.push(homeFor(role));
  }

  // After a re-seed the saved choice can point at someone who no longer
  // exists (ids change). Forget it, so the welcome chooser shows instead.
  const stale =
    actor !== null &&
    students.data !== undefined &&
    interviewers.data !== undefined &&
    (actor.role === "student"
      ? !students.data.some((s) => s.student_id === actor.id)
      : actor.role === "interviewer" && !interviewers.data.some((i) => i.id === actor.id));
  useEffect(() => {
    if (stale) setActor(null);
  }, [stale]);

  const value = actor && !stale ? `${actor.role}|${actor.id}` : "";
  const loadError = students.error ?? interviewers.error;

  return (
    <label className={large ? "block" : "flex min-w-0 items-center gap-2"}>
      <span className={large ? "mb-1 block text-sm font-medium" : "hidden text-sm text-muted sm:inline"}>View as</span>
      <select
        value={value}
        onChange={(e) => choose(e.target.value)}
        disabled={!ready || !students.data || !interviewers.data}
        className={
          large
            ? "w-full rounded-xl border border-line bg-surface-2 px-3 py-2.5 text-fg"
            : "max-w-[60vw] truncate rounded-full border border-line bg-surface-2 px-3 py-1.5 text-sm font-semibold text-fg sm:max-w-none"
        }
        aria-label="View as"
      >
        <option value="" disabled>
          {loadError ? "Could not load people" : "Choose who you are…"}
        </option>
        <optgroup label="Students">
          {students.data?.map((s) => (
            <option key={s.student_id} value={`student|${s.student_id}`}>
              {s.name} · student
            </option>
          ))}
        </optgroup>
        <optgroup label="Interviewers">
          {interviewers.data?.map((i) => (
            <option key={i.id} value={`interviewer|${i.id}`}>
              {i.name} · interviewer
            </option>
          ))}
        </optgroup>
        <optgroup label="Admin">
          <option value={`admin|${ADMIN.id}`}>Admin</option>
        </optgroup>
      </select>
      {large && loadError && (
        <span className="mt-2 block text-sm text-red-soft">{loadError instanceof Error ? loadError.message : String(loadError)}</span>
      )}
    </label>
  );
}

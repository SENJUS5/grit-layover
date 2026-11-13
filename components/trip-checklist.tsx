import { Circle, CircleCheck, Clock } from "lucide-react";
import { num } from "@/lib/labels";
import { formatDeadline } from "@/lib/time";
import type { Overview } from "@/lib/types";
import { Card, Pill } from "./ui";

type Item = { label: string; detail: string; state: "done" | "todo" | "later" };

/** GRIT's five conditions for the trip, from the student's real data. */
export function TripChecklist({ overview: o }: { overview: Overview }) {
  const items: Item[] = [
    {
      label: `${num(o.min_attendance_pct)}% attendance`,
      detail: `You're at ${num(o.attendance_pct)}%`,
      state: o.attendance_ok ? "done" : "todo",
    },
    {
      label: "Semester registration",
      detail: o.registered_ok ? "Approved" : "Not approved yet",
      state: o.registered_ok ? "done" : "todo",
    },
    {
      label: "Code of conduct",
      detail: o.conduct_ok ? "In good standing" : "On hold for now",
      state: o.conduct_ok ? "done" : "todo",
    },
    {
      label: `One badge by ${formatDeadline(o.badge_deadline)}`,
      detail: o.badge_by_deadline ? "You hold a badge from an interview on or before the deadline" : "No badge yet",
      state: o.badge_by_deadline ? "done" : "todo",
    },
    { label: "Final interview round", detail: "Comes after the badge rounds", state: "later" },
  ];
  const done = items.filter((i) => i.state === "done").length;

  return (
    <Card>
      <p className="text-sm text-muted">
        <strong className="text-fg">{done} of 5</strong> done
      </p>
      <ul className="mt-2 divide-y divide-line">
        {items.map((item) => (
          <li key={item.label} className="flex items-center gap-3 py-3">
            {item.state === "done" ? (
              <CircleCheck className="shrink-0 text-yellow" size={22} aria-hidden />
            ) : item.state === "later" ? (
              <Clock className="shrink-0 text-muted" size={22} aria-hidden />
            ) : (
              <Circle className="shrink-0 text-muted" size={22} aria-hidden />
            )}
            <div className="min-w-0 flex-1">
              <p className="font-semibold">{item.label}</p>
              <p className="text-sm text-muted">{item.detail}</p>
            </div>
            <Pill tone={item.state === "done" ? "yellow" : "muted"}>
              {item.state === "done" ? "Done" : item.state === "later" ? "Pending" : "Not yet"}
            </Pill>
          </li>
        ))}
      </ul>
    </Card>
  );
}

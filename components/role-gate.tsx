"use client";

import type { ReactNode } from "react";
import { homeFor, useActor } from "@/lib/actor";
import type { Actor, Role } from "@/lib/types";
import { ButtonLink, Card } from "./ui";
import { ViewAs } from "./view-as";

const ROLE_NAMES: Record<Role, string> = { student: "students", interviewer: "interviewers", admin: "admins" };

export function Welcome() {
  return (
    <Card className="mx-auto mt-8 max-w-lg">
      <h1 className="text-2xl font-bold">Welcome to GRIT Layover</h1>
      <p className="mt-2 text-muted">
        This prototype has no login. Choose who you are: a student, an interviewer or the admin. You can switch at any
        time from <strong className="text-fg">View as</strong> at the top.
      </p>
      <div className="mt-5">
        <ViewAs large />
      </div>
    </Card>
  );
}

/** Shows the screen only to the roles it is for, and hands it the current actor. */
export function RoleGate({ allow, children }: { allow: Role[]; children: (actor: Actor) => ReactNode }) {
  const { actor } = useActor();
  if (!actor) return <Welcome />;
  if (!allow.includes(actor.role)) {
    return (
      <Card className="mx-auto mt-8 max-w-lg">
        <h1 className="text-xl font-bold">This screen is for {allow.map((r) => ROLE_NAMES[r]).join(" and ")}</h1>
        <p className="mt-2 text-muted">
          You are viewing as {actor.name}. Switch in <strong className="text-fg">View as</strong>, or go to your own home.
        </p>
        <ButtonLink href={homeFor(actor.role)} className="mt-4">
          Go to my home
        </ButtonLink>
      </Card>
    );
  }
  return <>{children(actor)}</>;
}

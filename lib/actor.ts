"use client";

import { useMemo, useSyncExternalStore } from "react";
import type { Actor, Role } from "./types";

// The "View as" choice, kept in localStorage so it survives reloads. There is
// no login in this prototype: the database checks each role's rights, but it
// trusts the app about who the user is (see supabase/migrations/004_security.sql).

const KEY = "grit-layover:view-as";
const SERVER = "server"; // what the server render sees: nothing chosen yet
const listeners = new Set<() => void>();
let memory: string | null = null; // used when localStorage is unavailable

function read(): string {
  try {
    return window.localStorage.getItem(KEY) ?? "";
  } catch {
    return memory ?? "";
  }
}

function subscribe(onChange: () => void) {
  listeners.add(onChange);
  window.addEventListener("storage", onChange);
  return () => {
    listeners.delete(onChange);
    window.removeEventListener("storage", onChange);
  };
}

function parse(raw: string): Actor | null {
  try {
    const value = JSON.parse(raw) as Partial<Actor>;
    const roles: Role[] = ["student", "interviewer", "admin"];
    if (value && roles.includes(value.role as Role) && typeof value.id === "string" && typeof value.name === "string") {
      return { role: value.role as Role, id: value.id, name: value.name };
    }
  } catch {
    // Not set, or unreadable: treat as not chosen.
  }
  return null;
}

export function setActor(actor: Actor | null) {
  const raw = actor ? JSON.stringify(actor) : null;
  try {
    if (raw === null) window.localStorage.removeItem(KEY);
    else window.localStorage.setItem(KEY, raw);
  } catch {
    memory = raw;
  }
  listeners.forEach((listener) => listener());
}

/**
 * The current actor. `ready` is false during the server render and the first
 * hydration pass, so role-dependent UI only ever renders in the browser.
 */
export function useActor(): { actor: Actor | null; ready: boolean } {
  const raw = useSyncExternalStore(subscribe, read, () => SERVER);
  const actor = useMemo(() => (raw === SERVER ? null : parse(raw)), [raw]);
  return { actor, ready: raw !== SERVER };
}

export const ADMIN: Actor = { role: "admin", id: "admin-demo", name: "Admin" };

export function homeFor(role: Role): string {
  return role === "student" ? "/" : role === "interviewer" ? "/interviewer" : "/admin";
}

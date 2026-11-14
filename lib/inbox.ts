"use client";

import { useSyncExternalStore } from "react";
import useSWR from "swr";
import * as api from "./api";
import { buildMessages } from "./messages";
import { istDay } from "./time";
import type { Actor } from "./types";
import { useNow } from "./use-now";

// The "new" dot on Messages. Messages are computed from data, so "read" is
// simply the newest message time this browser has seen, kept in localStorage.

const listeners = new Set<() => void>();
const keyFor = (studentId: string) => `grit-layover:messages-seen:${studentId}`;

function subscribe(onChange: () => void) {
  listeners.add(onChange);
  return () => listeners.delete(onChange);
}

export function readSeen(studentId: string): string {
  try {
    return window.localStorage.getItem(keyFor(studentId)) ?? "";
  } catch {
    return "";
  }
}

export function markMessagesSeen(studentId: string, newestAt: string) {
  try {
    window.localStorage.setItem(keyFor(studentId), newestAt);
  } catch {
    // Storage unavailable: the dot just stays.
  }
  listeners.forEach((listener) => listener());
}

/** The student's messages (shared SWR keys with the Messages screen). */
export function useMessages(actor: Actor | null) {
  const id = actor?.role === "student" ? actor.id : null;
  const overview = useSWR(id ? ["overview", id] : null, () => api.studentOverview(actor!, id!));
  const journey = useSWR(id ? ["journey", id] : null, () => api.getJourney(id!));
  const timeline = useSWR(id ? ["timeline", id] : null, () => api.studentTimeline(actor!, id!));
  // Today's date decides whether a retake date is still ahead. Like the data,
  // it is only known in the browser (null during the server render).
  const now = useNow();
  const ready = now !== null && overview.data !== undefined && journey.data && timeline.data;
  return {
    messages: ready
      ? buildMessages({
          overview: overview.data ?? null,
          journey: journey.data!,
          timeline: timeline.data!,
          today: istDay(now!),
        })
      : undefined,
    error: overview.error ?? journey.error ?? timeline.error,
  };
}

/** True when the newest message is newer than the last one shown on the Messages screen. */
export function useHasNewMessages(actor: Actor | null): boolean {
  const { messages } = useMessages(actor);
  const seen = useSyncExternalStore(
    subscribe,
    () => (actor?.role === "student" ? readSeen(actor.id) : ""),
    () => "",
  );
  const newest = messages?.[0]?.at;
  return Boolean(newest && (!seen || Date.parse(newest) > Date.parse(seen)));
}

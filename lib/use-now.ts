"use client";

import { useSyncExternalStore } from "react";

// The current time, to the minute, for screens that compare against "now"
// (e.g. "needs a result" = the slot has started). It is null during the server
// render, so the time is only ever read in the browser.

const MINUTE = 60_000;

function subscribe(onChange: () => void) {
  const timer = setInterval(onChange, 15_000);
  return () => clearInterval(timer);
}

const getSnapshot = () => Math.floor(Date.now() / MINUTE) * MINUTE;
const getServerSnapshot = () => null;

export function useNow(): number | null {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

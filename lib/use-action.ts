"use client";

import { useCallback, useRef, useState } from "react";
import { useSWRConfig } from "swr";

type ActionState = { pending: boolean; error: string | null; done: string | null };

/**
 * Runs one write (a database function call). On success every screen's data
 * is re-read, so all views reflect the change; on failure the database's
 * message is kept as-is for the user.
 *
 * One write at a time: buttons are disabled while `pending`, and a second call
 * that arrives before the button re-renders (a fast double-click) is ignored.
 */
export function useAction() {
  const { mutate } = useSWRConfig();
  const [state, setState] = useState<ActionState>({ pending: false, error: null, done: null });
  const running = useRef(false);

  const run = useCallback(
    async (write: () => Promise<unknown>, doneMessage: string | null = null): Promise<boolean> => {
      if (running.current) return false;
      running.current = true;
      try {
        setState({ pending: true, error: null, done: null });
        try {
          await write();
        } catch (e) {
          setState({ pending: false, error: e instanceof Error ? e.message : String(e), done: null });
          return false;
        }
        await mutate(() => true);
        setState({ pending: false, error: null, done: doneMessage });
        return true;
      } finally {
        running.current = false;
      }
    },
    [mutate],
  );

  const reset = useCallback(() => setState({ pending: false, error: null, done: null }), []);

  return { ...state, run, reset };
}

/**
 * A success note at the top of a screen. It outlives the form that caused it
 * (which often disappears once the data changes), and the page scrolls up so
 * the note and the updated data are in view.
 */
export function useFlash() {
  const [message, setMessage] = useState<string | null>(null);
  const show = useCallback((text: string) => {
    setMessage(text);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }, []);
  return { message, show };
}

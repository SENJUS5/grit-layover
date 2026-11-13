"use client";

import type { ReactNode } from "react";
import { SWRConfig } from "swr";

export function Providers({ children }: { children: ReactNode }) {
  return (
    // Database errors (rule checks, permissions) do not fix themselves, so no retries.
    <SWRConfig value={{ shouldRetryOnError: false, revalidateOnFocus: true }}>{children}</SWRConfig>
  );
}

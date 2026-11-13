import Link from "next/link";
import { cloneElement, useId, type ButtonHTMLAttributes, type ComponentProps, type ReactElement, type ReactNode } from "react";
import type { Tone } from "@/lib/labels";

const cx = (...classes: (string | false | null | undefined)[]) => classes.filter(Boolean).join(" ");

export function PageHeader({ title, subtitle, children }: { title: string; subtitle?: ReactNode; children?: ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="text-2xl font-bold tracking-tight md:text-3xl">{title}</h1>
        {subtitle && <p className="mt-1 text-muted">{subtitle}</p>}
      </div>
      {children}
    </div>
  );
}

export function Card({ children, className, tone }: { children: ReactNode; className?: string; tone?: Tone }) {
  const edge = {
    yellow: "border-yellow/60",
    blue: "border-blue/60",
    red: "border-red/60",
    purple: "border-purple",
    muted: "border-line",
  };
  return (
    <section className={cx("rounded-2xl border bg-surface p-4 md:p-5", tone ? edge[tone] : "border-line", className)}>
      {children}
    </section>
  );
}

export function SectionTitle({ children, count }: { children: ReactNode; count?: number }) {
  return (
    <h2 className="mb-3 mt-8 flex items-center gap-2 text-lg font-semibold first:mt-0">
      {children}
      {count !== undefined && <span className="rounded-full bg-surface-2 px-2 text-sm font-medium text-muted">{count}</span>}
    </h2>
  );
}

const PILL_TONE: Record<Tone, string> = {
  yellow: "bg-yellow text-bg",
  blue: "bg-blue/25 text-blue-soft",
  red: "bg-red/20 text-red-soft",
  purple: "bg-purple/40 text-purple-soft",
  muted: "bg-surface-2 text-muted",
};

export function Pill({ tone = "muted", children }: { tone?: Tone; children: ReactNode }) {
  return (
    <span className={cx("inline-flex shrink-0 items-center rounded-full px-2.5 py-0.5 text-xs font-semibold", PILL_TONE[tone])}>
      {children}
    </span>
  );
}

type Variant = "primary" | "secondary" | "danger" | "ghost";
const BUTTON =
  "inline-flex items-center justify-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-50";
const VARIANT: Record<Variant, string> = {
  primary: "bg-yellow text-bg hover:bg-yellow/90",
  secondary: "border border-line bg-surface-2 text-fg hover:border-muted",
  danger: "bg-red text-fg hover:bg-red/90",
  ghost: "text-muted hover:text-fg",
};

export function Button({
  variant = "primary",
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  return <button type="button" className={cx(BUTTON, VARIANT[variant], className)} {...props} />;
}

export function ButtonLink({
  variant = "primary",
  className,
  ...props
}: ComponentProps<typeof Link> & { variant?: Variant }) {
  return <Link className={cx(BUTTON, VARIANT[variant], className)} {...props} />;
}

export const inputClass =
  "w-full rounded-xl border border-line bg-surface-2 px-3 py-2 text-sm text-fg placeholder:text-muted/70 focus:border-yellow focus:outline-none";

/** A labelled input. The hint sits outside the label (so it is not part of the input's name) and is linked to it. */
export function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: ReactElement<{ "aria-describedby"?: string }>;
}) {
  const hintId = useId();
  return (
    <div>
      <label className="block">
        <span className="mb-1 block text-sm font-medium">{label}</span>
        {hint ? cloneElement(children, { "aria-describedby": hintId }) : children}
      </label>
      {hint && (
        <p id={hintId} className="mt-1 text-xs text-muted">
          {hint}
        </p>
      )}
    </div>
  );
}

/** A database message, shown exactly as written. */
export function ErrorNote({ message }: { message: string | null | undefined }) {
  if (!message) return null;
  return (
    <p role="alert" className="mt-3 rounded-xl border border-red/50 bg-red/10 px-3 py-2 text-sm text-red-soft">
      {message}
    </p>
  );
}

export function DoneNote({ message }: { message: string | null | undefined }) {
  if (!message) return null;
  return (
    <p role="status" className="mt-3 rounded-xl border border-yellow/40 bg-yellow/10 px-3 py-2 text-sm text-yellow">
      {message}
    </p>
  );
}

export function Loading({ label = "Loading…" }: { label?: string }) {
  return <p className="animate-pulse py-6 text-sm text-muted">{label}</p>;
}

/** For any SWR read: loading text, the error as-is, or the content. */
export function Async<T>({
  data,
  error,
  children,
}: {
  data: T | undefined;
  error: unknown;
  children: (data: T) => ReactNode;
}) {
  if (error) return <ErrorNote message={error instanceof Error ? error.message : String(error)} />;
  if (data === undefined) return <Loading />;
  return <>{children(data)}</>;
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="rounded-xl border border-dashed border-line px-4 py-6 text-center text-sm text-muted">{children}</p>;
}

export function StatTile({ label, value, sub, href }: { label: string; value: ReactNode; sub?: ReactNode; href?: string }) {
  const body = (
    <>
      <p className="text-xs font-semibold uppercase tracking-wider text-muted">{label}</p>
      <p className="mt-1 text-2xl font-bold">{value}</p>
      {sub && <p className="mt-1 text-sm text-muted">{sub}</p>}
    </>
  );
  const box = "block rounded-2xl border border-line bg-surface p-4";
  return href ? (
    <Link href={href} className={cx(box, "transition hover:border-muted")}>
      {body}
    </Link>
  ) : (
    <div className={box}>{body}</div>
  );
}

/** Wraps wide tables so they scroll inside the card, never the page. */
export function TableWrap({ children }: { children: ReactNode }) {
  return <div className="-mx-4 overflow-x-auto px-4 md:mx-0 md:px-0">{children}</div>;
}

export const th = "px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-muted";
export const td = "px-3 py-2.5 align-top text-sm";

/** The first error among several reads, as the user should see it (or null). */
export function firstError(...reads: { error?: unknown }[]): string | null {
  const error = reads.find((r) => r.error)?.error;
  if (!error) return null;
  return error instanceof Error ? error.message : String(error);
}

export const textareaClass = `${inputClass} min-h-20 resize-y`;

/** A radio group drawn as pill buttons. */
export function RadioPills<T extends string>({
  legend,
  name,
  options,
  value,
  onChange,
}: {
  legend: string;
  name: string;
  options: { value: T; label: string }[];
  value: T | null;
  onChange: (value: T) => void;
}) {
  return (
    <fieldset>
      <legend className="mb-1.5 block text-sm font-medium">{legend}</legend>
      <div className="flex flex-wrap gap-2">
        {options.map((o) => (
          <label key={o.value} className="cursor-pointer">
            <input
              type="radio"
              name={name}
              value={o.value}
              checked={value === o.value}
              onChange={() => onChange(o.value)}
              className="peer sr-only"
            />
            <span className="inline-flex rounded-full border border-line bg-surface-2 px-3 py-1.5 text-sm font-semibold text-muted transition peer-checked:border-yellow peer-checked:bg-yellow peer-checked:text-bg peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-yellow">
              {o.label}
            </span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}

/** Small key/value line used in cards: "Interview · Sat 14 Nov, 10:30". */
export function Meta({ label, children }: { label: string; children: ReactNode }) {
  return (
    <p className="text-sm">
      <span className="text-muted">{label}: </span>
      {children}
    </p>
  );
}

/** A link the student typed (e.g. a project), opened in a new tab. */
export function ExternalLink({ href }: { href: string }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer" className="break-all text-blue-soft underline">
      {href}
    </a>
  );
}

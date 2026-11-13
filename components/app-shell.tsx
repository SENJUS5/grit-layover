"use client";

import {
  BookOpen,
  CalendarCheck,
  CalendarClock,
  CalendarPlus,
  ClipboardList,
  Coins,
  Compass,
  FolderGit2,
  History,
  LayoutDashboard,
  Mail,
  ShieldAlert,
  Swords,
  TriangleAlert,
  Trophy,
  type LucideIcon,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useActor } from "@/lib/actor";
import { useHasNewMessages } from "@/lib/inbox";
import { isConfigured } from "@/lib/supabase";
import type { Role } from "@/lib/types";
import { Loading } from "./ui";
import { ViewAs } from "./view-as";

type NavItem = { href: string; label: string; icon: LucideIcon };

const NAV: Record<Role, NavItem[]> = {
  student: [
    { href: "/", label: "Dashboard", icon: LayoutDashboard },
    { href: "/miles", label: "Miles", icon: Coins },
    { href: "/leaderboard", label: "Leaderboard", icon: Trophy },
    { href: "/interviews", label: "Interviews", icon: CalendarCheck },
    { href: "/messages", label: "Messages", icon: Mail },
  ],
  interviewer: [
    { href: "/interviewer", label: "Schedule", icon: CalendarClock },
    { href: "/interviewer/availability", label: "Availability", icon: CalendarPlus },
    { href: "/interviewer/projects", label: "Projects", icon: FolderGit2 },
    { href: "/leaderboard", label: "Leaderboard", icon: Trophy },
  ],
  admin: [
    { href: "/admin", label: "Bookings", icon: ClipboardList },
    { href: "/admin/at-risk", label: "At risk", icon: TriangleAlert },
    { href: "/admin/cases", label: "Cases", icon: ShieldAlert },
    { href: "/admin/audit", label: "Audit log", icon: History },
    { href: "/leaderboard", label: "Leaderboard", icon: Trophy },
  ],
};

// Parts of the real GRIT dashboard that this prototype does not cover.
const COMING_SOON: NavItem[] = [
  { href: "#", label: "Contests", icon: Swords },
  { href: "#", label: "Skill Guide", icon: BookOpen },
  { href: "#", label: "Quests", icon: Compass },
];

function Wordmark() {
  return (
    <Link href="/" className="flex items-baseline gap-2" aria-label="GRIT Layover home">
      <span className="text-2xl font-black tracking-tight text-yellow">GRIT</span>
      <span className="text-sm font-medium text-muted">Layover</span>
    </Link>
  );
}

export function AppShell({ children }: { children: ReactNode }) {
  const { actor, ready } = useActor();
  const pathname = usePathname();
  const hasNew = useHasNewMessages(actor);
  const items = actor ? NAV[actor.role] : [];

  const navLink = (item: NavItem, compact = false) => {
    const active = pathname === item.href;
    const dot = item.href === "/messages" && hasNew;
    const Icon = item.icon;
    return (
      <Link
        key={item.href}
        href={item.href}
        aria-current={active ? "page" : undefined}
        className={
          compact
            ? `relative flex flex-1 flex-col items-center gap-0.5 py-2 text-[11px] font-medium ${active ? "text-yellow" : "text-muted"}`
            : `relative flex items-center gap-3 rounded-full px-4 py-2.5 text-sm font-semibold transition ${
                active ? "bg-yellow text-bg" : "text-muted hover:bg-surface-2 hover:text-fg"
              }`
        }
      >
        <Icon size={compact ? 20 : 18} aria-hidden />
        {item.label}
        {dot && (
          <span
            className={`absolute h-2 w-2 rounded-full bg-red ${compact ? "right-[30%] top-1.5" : "right-4 top-1/2 -translate-y-1/2"}`}
            aria-label="new messages"
          />
        )}
      </Link>
    );
  };

  return (
    <div className="min-h-dvh md:grid md:grid-cols-[15rem_1fr]">
      <aside className="sticky top-0 hidden h-dvh flex-col gap-6 border-r border-line bg-surface px-3 py-5 md:flex">
        <div className="px-4">
          <Wordmark />
        </div>
        <nav className="flex flex-col gap-1" aria-label="Main">
          {items.map((item) => navLink(item))}
        </nav>
        {actor?.role === "student" && (
          <div className="flex flex-col gap-1" aria-label="Coming soon">
            {COMING_SOON.map(({ label, icon: Icon }) => (
              <span
                key={label}
                aria-disabled
                className="flex cursor-not-allowed items-center gap-3 rounded-full px-4 py-2.5 text-sm font-semibold text-muted/50"
              >
                <Icon size={18} aria-hidden />
                {label}
                <span className="ml-auto rounded-full bg-surface-2 px-2 text-[10px] uppercase tracking-wide">Soon</span>
              </span>
            ))}
          </div>
        )}
        <p className="mt-auto px-4 text-xs text-muted/70">Prototype · no login</p>
      </aside>

      <div className="flex min-h-dvh min-w-0 flex-col">
        <header className="sticky top-0 z-20 flex items-center justify-between gap-3 border-b border-line bg-bg/90 px-4 py-3 backdrop-blur md:justify-end md:px-8">
          <div className="md:hidden">
            <Wordmark />
          </div>
          <ViewAs />
        </header>

        <main className="mx-auto w-full max-w-5xl flex-1 px-4 pb-28 pt-6 md:px-8 md:pb-12">
          {!isConfigured && (
            <p role="alert" className="mb-6 rounded-xl border border-red/50 bg-red/10 px-4 py-3 text-sm text-red-soft">
              Supabase is not configured. Copy <code>.env.example</code> to <code>.env.local</code>, fill in the two
              values, and restart the app.
            </p>
          )}
          {/* Everything below depends on the "View as" choice, which lives in the browser. */}
          {ready ? children : <Loading />}
        </main>
      </div>

      {items.length > 0 && (
        <nav
          className="fixed inset-x-0 bottom-0 z-20 flex border-t border-line bg-surface/95 px-1 pb-[env(safe-area-inset-bottom)] backdrop-blur md:hidden"
          aria-label="Main"
        >
          {items.map((item) => navLink(item, true))}
        </nav>
      )}
    </div>
  );
}

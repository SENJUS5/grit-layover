"use client";

import { Info, Mail, Plane } from "lucide-react";
import { Fragment, useEffect, useState } from "react";
import { RoleGate } from "@/components/role-gate";
import { ButtonLink, Card, Empty, ErrorNote, Loading, PageHeader, Pill } from "@/components/ui";
import { markMessagesSeen, readSeen, useMessages } from "@/lib/inbox";
import { SUPPORT_EMAIL, type Message } from "@/lib/messages";
import { formatDateTime } from "@/lib/time";
import type { Actor } from "@/lib/types";

export function MessagesScreen() {
  return <RoleGate allow={["student"]}>{(student) => <Inbox key={student.id} student={student} />}</RoleGate>;
}

function Inbox({ student }: { student: Actor }) {
  const { messages, error } = useMessages(student);
  // What was already seen when the screen opened, so new messages stay marked while you read.
  const [seenBefore] = useState(() => readSeen(student.id));
  const newest = messages?.[0]?.at;

  useEffect(() => {
    if (newest) markMessagesSeen(student.id, newest);
  }, [student.id, newest]);

  if (error) return <ErrorNote message={error instanceof Error ? error.message : String(error)} />;
  if (!messages) return <Loading />;

  return (
    <>
      <PageHeader title="Messages" subtitle="Results and changes to your badges." />
      {messages.length === 0 ? (
        <Empty>No messages yet. Your interview results will show up here.</Empty>
      ) : (
        <div className="space-y-4">
          {messages.map((m) => (
            <MessageCard key={m.id} message={m} isNew={!seenBefore || Date.parse(m.at) > Date.parse(seenBefore)} />
          ))}
        </div>
      )}
    </>
  );
}

const ICON = { good: Plane, neutral: Mail, care: Info };

function MessageCard({ message: m, isNew }: { message: Message; isNew: boolean }) {
  const Icon = ICON[m.tone];
  return (
    <Card tone={m.tone === "good" ? "yellow" : undefined}>
      <article>
        <header className="flex flex-wrap items-center gap-x-3 gap-y-1">
          <Icon size={18} className={m.tone === "good" ? "text-yellow" : "text-muted"} aria-hidden />
          <h2 className="text-lg font-bold">{m.title}</h2>
          {isNew && <Pill tone="red">New</Pill>}
          <time dateTime={m.at} className="ml-auto text-sm text-muted">
            {formatDateTime(m.at)}
          </time>
        </header>
        <div className="mt-3 space-y-2 text-[15px] leading-relaxed">
          {m.body.map((line, i) => (
            <p key={i}>{line}</p>
          ))}
        </div>
        {m.action && (
          <ButtonLink href={m.action.href} variant="secondary" className="mt-4">
            {m.action.label}
          </ButtonLink>
        )}
        {m.note && <p className="mt-3 border-t border-line pt-3 text-sm text-muted">{withEmailLink(m.note)}</p>}
      </article>
    </Card>
  );
}

/** Turns the support address inside a note into a mail link. */
function withEmailLink(text: string) {
  const parts = text.split(SUPPORT_EMAIL);
  return parts.map((part, i) => (
    <Fragment key={i}>
      {part}
      {i < parts.length - 1 && (
        <a href={`mailto:${SUPPORT_EMAIL}`} className="text-fg underline">
          {SUPPORT_EMAIL}
        </a>
      )}
    </Fragment>
  ));
}

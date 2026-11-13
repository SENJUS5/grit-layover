-- =============================================================================
-- GRIT Layover - 001_schema.sql
-- Extensions, tables, constraints and indexes.
--
-- Design principles (enforced across 001-004):
--   1. Miles are a passbook: miles_ledger is insert-only. Miles = SUM(amount).
--   2. Nothing is deleted: badges are revoked, bookings are cancelled,
--      contest attempts are never overwritten.
--   3. Every change is recorded in audit_log by triggers (002).
--   4. The database enforces the rules, not just the app.
--   5. Journey state is derived by a view (003), never stored.
--   6. Dates are Asia/Kolkata (IST); timestamps are timestamptz.
-- =============================================================================

-- Supabase installs extensions into the "extensions" schema. Creating it here
-- is a no-op on Supabase and makes a plain Postgres behave the same way.
create schema if not exists extensions;
create extension if not exists pgcrypto   with schema extensions;  -- gen_random_uuid (also core since PG13)
create extension if not exists btree_gist with schema extensions;  -- uuid "=" inside a GiST exclusion constraint

-- btree_gist's operator classes must be visible while the exclusion constraint is created.
set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Shared value types
-- -----------------------------------------------------------------------------
create domain grit_track as text
  check (value in ('AI Product Mastery', 'AI Systems Mastery', 'AI Models Mastery', 'AI Robotics Mastery'));
comment on domain grit_track is 'The four GRIT mastery tracks.';

create domain actor_role as text
  check (value in ('student', 'interviewer', 'admin', 'system'));
comment on domain actor_role is 'Who performed an action. "system" covers seeds, contest sync and direct SQL.';

-- -----------------------------------------------------------------------------
-- 1. program_settings
-- -----------------------------------------------------------------------------
create table program_settings (
  id                        int primary key default 1 check (id = 1),
  badge_deadline            date not null default '2026-12-31',
  retake_gap_days           int  not null default 5  check (retake_gap_days >= 0),
  slot_minutes              int  not null default 30 check (slot_minutes > 0),
  min_booking_notice_hours  int  not null default 2  check (min_booking_notice_hours >= 0),
  review_limit_days         int  not null default 7  check (review_limit_days > 0),
  min_attendance_pct        numeric(5,2) not null default 75 check (min_attendance_pct between 0 and 100),
  updated_at                timestamptz not null default now()
);
comment on table program_settings is 'Single-row table of program-wide rules, so policy changes are data changes (audited), not code changes.';
comment on column program_settings.badge_deadline is 'Last date (IST) to earn a first badge and qualify. Used for at-risk reporting only; it does not block bookings.';
comment on column program_settings.retake_gap_days is 'Default cooldown after fail / retake_later / no_show before the student can book again.';
comment on column program_settings.slot_minutes is 'Length of every interview slot created through create_slot().';
comment on column program_settings.min_booking_notice_hours is 'A slot must start at least this many hours after the moment of booking.';
comment on column program_settings.review_limit_days is 'Days an admin has to decide a malpractice case. Copied into each case at creation.';
comment on column program_settings.min_attendance_pct is 'Minimum attendance to be eligible to book (GRIT rule: 75%).';

insert into program_settings (id) values (1);

-- -----------------------------------------------------------------------------
-- 2. students
-- -----------------------------------------------------------------------------
create table students (
  id                      uuid primary key default gen_random_uuid(),
  name                    text not null check (btrim(name) <> ''),
  phone                   text not null unique,
  batch                   int  not null check (batch in (2023, 2024, 2025)),
  campus                  text not null,
  section                 text not null,
  primary_track           grit_track not null,
  is_registered_approved  boolean not null default false,
  attendance_pct          numeric(5,2) not null default 0 check (attendance_pct between 0 and 100),
  has_admin_hold          boolean not null default false,
  conduct_ok              boolean not null default true,
  has_surprise_ticket     boolean not null default false,
  created_at              timestamptz not null default now()
);
comment on table students is 'NIAT students in the GRIT program, with the eligibility flags that gate interview booking.';
comment on column students.primary_track is 'The track the student is pursuing; drives "next badge" in admin views. Journeys still list every unlocked badge.';
comment on column students.is_registered_approved is 'Registered for GRIT and approved by an admin. Required to book and to appear on the leaderboard.';
comment on column students.conduct_ok is 'Set to false when a malpractice case is confirmed; only restore_eligibility() (admin) sets it back. Blocks booking.';
comment on column students.has_surprise_ticket is 'GRIT surprise ticket flag, carried for the app; no rule depends on it yet.';

-- -----------------------------------------------------------------------------
-- 3. interviewers
-- -----------------------------------------------------------------------------
create table interviewers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (btrim(name) <> ''),
  email       text not null unique check (email like '%@%'),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);
comment on table interviewers is 'People who publish slots, run badge interviews and record results.';
comment on column interviewers.is_active is 'Inactive interviewers keep their history but cannot be booked or create slots.';

-- -----------------------------------------------------------------------------
-- 4. skills
-- -----------------------------------------------------------------------------
create table skills (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  max_level  int  not null check (max_level between 1 and 4)
);
comment on table skills is 'GRIT contest skills. Each has levels 1..max_level; badges require cleared levels.';

-- -----------------------------------------------------------------------------
-- 5. badges
-- -----------------------------------------------------------------------------
create table badges (
  id             uuid primary key default gen_random_uuid(),
  track          grit_track not null,
  level          text not null check (level in ('Novice', 'Specialist', 'Expert', 'Master', 'Grand Master')),
  sequence       int  not null check (sequence between 1 and 5),
  bonus_miles    int  check (bonus_miles > 0),
  needs_project  boolean not null default false,
  is_locked      boolean not null default false,
  unique (track, sequence),
  -- The level name and its position in the track must agree.
  constraint badges_level_matches_sequence check (
    sequence = case level when 'Novice' then 1 when 'Specialist' then 2 when 'Expert' then 3
                          when 'Master' then 4 when 'Grand Master' then 5 end),
  -- Only locked (not yet offered) badges may have an undecided bonus.
  constraint badges_bonus_required_when_open check (is_locked or bonus_miles is not null)
);
comment on table badges is 'The 4 tracks x 5 levels of GRIT badges. A badge is earned by passing an interview.';
comment on column badges.sequence is 'Position in the track (1 = Novice). A badge needs the previous one in the same track: no skipping.';
comment on column badges.bonus_miles is 'Miles credited when the badge is awarded and debited if it is revoked. Null only for locked badges.';
comment on column badges.needs_project is 'Robotics badges need an approved project submission before booking.';
comment on column badges.is_locked is 'Not offered yet (Expert and above). Locked badges cannot be booked and are hidden from journeys.';

-- -----------------------------------------------------------------------------
-- 6. badge_requirements
-- -----------------------------------------------------------------------------
create table badge_requirements (
  id              uuid primary key default gen_random_uuid(),
  badge_id        uuid not null references badges (id),
  skill_id        uuid not null references skills (id),
  required_level  int  not null check (required_level between 1 and 4),
  unique (badge_id, skill_id)
);
comment on table badge_requirements is 'Skill levels a student must clear (gold or silver, at that level or higher) before booking a badge interview.';
create index badge_requirements_skill_idx on badge_requirements (skill_id);

-- -----------------------------------------------------------------------------
-- 7. skill_results (insert-only)
-- -----------------------------------------------------------------------------
create table skill_results (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references students (id),
  skill_id      uuid not null references skills (id),
  level         int  not null check (level between 1 and 4),
  medal         text not null check (medal in ('gold', 'silver', 'try_again')),
  miles         int  not null check (miles >= 0),
  attempted_at  timestamptz not null default now(),
  created_at    timestamptz not null default now()
);
comment on table skill_results is 'One row per contest attempt, exactly as sent by the contest system. Never overwritten, so the history of upgrades is kept.';
comment on column skill_results.miles is 'Miles the contest system attached to this attempt. Only the improvement over the previous best at this level reaches the ledger.';
create index skill_results_student_skill_level_idx on skill_results (student_id, skill_id, level);

-- -----------------------------------------------------------------------------
-- 8. slots
-- -----------------------------------------------------------------------------
create table slots (
  id              uuid primary key default gen_random_uuid(),
  interviewer_id  uuid not null references interviewers (id),
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  status          text not null default 'open' check (status in ('open', 'withdrawn')),
  withdrawn_at    timestamptz,
  withdraw_reason text,
  created_at      timestamptz not null default now(),
  constraint slots_ends_after_start check (ends_at > starts_at),
  constraint slots_withdrawn_has_time check ((status = 'withdrawn') = (withdrawn_at is not null)),
  -- An interviewer cannot have two open slots that overlap. Ranges are
  -- half-open [start, end), so back-to-back slots (10:00-10:30, 10:30-11:00) are fine.
  constraint slots_no_overlap exclude using gist (
    interviewer_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (status = 'open')
);
comment on table slots is 'Interview time windows published by interviewers. "Booked" is not stored here; it is derived from bookings.';
create index slots_starts_at_idx on slots (starts_at);

-- -----------------------------------------------------------------------------
-- 9. bookings
-- -----------------------------------------------------------------------------
create table bookings (
  id                   uuid primary key default gen_random_uuid(),
  student_id           uuid not null references students (id),
  badge_id             uuid not null references badges (id),
  slot_id              uuid not null references slots (id),
  status               text not null default 'active' check (status in ('active', 'cancelled', 'completed')),
  cancelled_by         actor_role check (cancelled_by in ('student', 'interviewer', 'admin')),
  cancel_reason        text,
  cancelled_at         timestamptz,
  rescheduled_from_id  uuid,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  -- Target for composite foreign keys that must agree on student and badge.
  constraint bookings_id_student_badge_key unique (id, student_id, badge_id),
  -- A reschedule must point at a booking of the same student for the same badge.
  constraint bookings_rescheduled_from_fk foreign key (rescheduled_from_id, student_id, badge_id)
    references bookings (id, student_id, badge_id),
  constraint bookings_cancel_fields check (
    (status = 'cancelled') = (cancelled_by is not null and cancelled_at is not null))
);
comment on table bookings is 'A student''s reservation of a slot for a badge interview. Cancelled, never deleted.';
comment on column bookings.rescheduled_from_id is 'The cancelled booking this one replaced, so a reschedule chain can be followed.';

-- Final guard against double booking: a slot carries at most one live booking.
-- Cancelled bookings do not count, so a cancelled slot can be booked again.
create unique index bookings_one_per_slot on bookings (slot_id) where status in ('active', 'completed');
-- A student has at most one upcoming interview per badge.
create unique index bookings_one_active_per_badge on bookings (student_id, badge_id) where status = 'active';
create index bookings_student_idx on bookings (student_id);

-- -----------------------------------------------------------------------------
-- 10. interview_results
-- -----------------------------------------------------------------------------
create table interview_results (
  id                 uuid primary key default gen_random_uuid(),
  booking_id         uuid not null unique,
  -- Denormalised from the booking (and pinned to it by the composite FK) so
  -- "latest result for student + badge" needs no join, and awards can FK to it.
  student_id         uuid not null,
  badge_id           uuid not null,
  outcome            text not null check (outcome in ('pass', 'fail', 'retake_later', 'no_show', 'technical_issue')),
  feedback           text,
  retake_after       date,
  interview_held_at  timestamptz not null,
  recorded_at        timestamptz not null default now(),
  recorded_by        uuid not null references interviewers (id),
  corrected_at       timestamptz,
  correction_reason  text,
  updated_at         timestamptz not null default now(),
  constraint interview_results_booking_fk foreign key (booking_id, student_id, badge_id)
    references bookings (id, student_id, badge_id),
  constraint interview_results_id_student_badge_key unique (id, student_id, badge_id),
  -- Only outcomes that impose a cooldown carry a retake date.
  constraint interview_results_retake_only_when_penalised check (
    retake_after is null or outcome in ('fail', 'retake_later', 'no_show'))
);
comment on table interview_results is 'The outcome of one completed booking. Corrections update it in place; audit_log keeps every earlier version.';
comment on column interview_results.interview_held_at is 'When the interview happened. Badges are dated by this, not by when the result was typed in.';
comment on column interview_results.recorded_at is 'When the result was entered. Interviewers may self-correct only on this IST calendar day.';
comment on column interview_results.retake_after is 'IST date from which the student may book again. Null = no cooldown.';
create index interview_results_student_badge_idx on interview_results (student_id, badge_id, interview_held_at desc);

-- -----------------------------------------------------------------------------
-- 11. project_submissions
-- -----------------------------------------------------------------------------
create table project_submissions (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references students (id),
  badge_id      uuid not null references badges (id),
  link          text not null check (link ~* '^https?://'),
  status        text not null default 'submitted' check (status in ('submitted', 'approved', 'rejected')),
  submitted_at  timestamptz not null default now(),
  reviewed_at   timestamptz,
  reviewed_by   uuid references interviewers (id),
  review_note   text,
  constraint project_submissions_review_fields check ((status = 'submitted') = (reviewed_at is null))
);
comment on table project_submissions is 'Project evidence for badges with needs_project (Robotics). An approved project unlocks booking.';
-- One submission in play per student and badge; a rejected one can be followed by a new one.
create unique index project_submissions_one_live on project_submissions (student_id, badge_id)
  where status in ('submitted', 'approved');

-- -----------------------------------------------------------------------------
-- 12. badge_awards
-- -----------------------------------------------------------------------------
create table badge_awards (
  id                  uuid primary key default gen_random_uuid(),
  student_id          uuid not null,
  badge_id            uuid not null,
  result_id           uuid not null,
  status              text not null default 'active' check (status in ('active', 'revoked')),
  awarded_at          timestamptz not null,
  created_at          timestamptz not null default now(),
  revoked_at          timestamptz,
  revoke_reason       text,
  revoke_cause        text check (revoke_cause in ('malpractice', 'result_corrected', 'prerequisite_revoked')),
  caused_by_award_id  uuid references badge_awards (id),
  revoked_by          text,
  -- The award must belong to the same student and badge as its interview result.
  constraint badge_awards_result_fk foreign key (result_id, student_id, badge_id)
    references interview_results (id, student_id, badge_id),
  constraint badge_awards_id_student_key unique (id, student_id),
  constraint badge_awards_revoke_fields check (
    (status = 'revoked') = (revoked_at is not null and revoke_cause is not null)),
  -- Only a cascade names the award that caused it.
  constraint badge_awards_cascade_has_cause check (
    (revoke_cause = 'prerequisite_revoked') = (caused_by_award_id is not null))
);
comment on table badge_awards is 'A badge earned by a student. Revoked (with cause), never deleted, so the history stays visible.';
comment on column badge_awards.awarded_at is 'Equals the interview''s interview_held_at, not when the result was recorded.';
comment on column badge_awards.caused_by_award_id is 'For cascade revocations: the lower badge whose revocation removed this one.';
comment on column badge_awards.revoked_by is 'Actor id that triggered the revocation (admin, interviewer, or system).';

create unique index badge_awards_one_active on badge_awards (student_id, badge_id) where status = 'active';
-- Partial on purpose: a result corrected pass -> fail -> pass gets a fresh award
-- while the revoked one stays on record.
create unique index badge_awards_one_active_per_result on badge_awards (result_id) where status = 'active';

-- -----------------------------------------------------------------------------
-- 13. miles_ledger (insert-only)
-- -----------------------------------------------------------------------------
create table miles_ledger (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references students (id),
  amount        int  not null check (amount <> 0),
  reason        text not null check (reason in (
                  'skill_medal', 'medal_upgrade', 'badge_bonus', 'badge_revoked',
                  -- Reserved, not written by anything yet: GRIT Bonus Miles
                  -- granted for proof submissions in a later phase.
                  'bonus_milestone')),
  source_id     uuid,
  note          text,
  effective_at  timestamptz not null,
  created_at    timestamptz not null default now()
);
comment on table miles_ledger is 'The Miles passbook. Rows are only ever inserted; a student''s Miles = SUM(amount).';
comment on column miles_ledger.source_id is 'Row that caused the entry: skill_results.id for medals, badge_awards.id for bonuses and revocations.';
comment on column miles_ledger.effective_at is 'When the Miles were earned or lost (e.g. interview time), as opposed to created_at (when the row was written).';
create index miles_ledger_student_idx on miles_ledger (student_id, effective_at);

-- -----------------------------------------------------------------------------
-- 14. malpractice_cases
-- -----------------------------------------------------------------------------
create table malpractice_cases (
  id              uuid primary key default gen_random_uuid(),
  student_id      uuid not null,
  badge_award_id  uuid not null,
  flagged_by      text not null,
  flagged_at      timestamptz not null default now(),
  evidence        text not null check (btrim(evidence) <> ''),
  status          text not null default 'open' check (status in ('open', 'confirmed', 'dismissed')),
  review_due_at   timestamptz not null,  -- set by trigger from program_settings.review_limit_days
  decided_by      text,
  decided_at      timestamptz,
  decision_note   text,
  eligibility_restored_at  timestamptz,
  eligibility_restored_by  text,
  restore_note             text,
  constraint malpractice_cases_award_fk foreign key (badge_award_id, student_id)
    references badge_awards (id, student_id),
  constraint malpractice_cases_decision_fields check ((status = 'open') = (decided_at is null)),
  -- Restoring eligibility is a follow-up to a confirmed case, with who and why.
  constraint malpractice_cases_restore_fields check (
    eligibility_restored_at is null
    or (status = 'confirmed' and eligibility_restored_by is not null and restore_note is not null))
);
comment on table malpractice_cases is 'Flags raised against an awarded badge. While open, the student''s badges count but final steps are on hold.';
comment on column malpractice_cases.review_due_at is 'flagged_at + review_limit_days, fixed at creation so later setting changes do not move existing deadlines.';
comment on column malpractice_cases.eligibility_restored_at is 'When an admin let the student book again after this confirmed case (restore_eligibility). Revoked badges stay revoked.';
create unique index malpractice_cases_one_open_per_award on malpractice_cases (badge_award_id) where status = 'open';
create index malpractice_cases_student_idx on malpractice_cases (student_id) where status = 'open';

-- -----------------------------------------------------------------------------
-- 15. audit_log (insert-only)
-- -----------------------------------------------------------------------------
create table audit_log (
  id          bigserial primary key,
  actor_role  actor_role not null default 'system',
  actor_id    text,
  action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  table_name  text not null,
  record_id   text,
  before      jsonb,
  after       jsonb,
  created_at  timestamptz not null default now()
);
comment on table audit_log is 'Row-level history of every change to business tables, written by triggers. Who did what, and the before/after values.';
comment on column audit_log.actor_role is 'From app.actor_role, set by the function that made the change. "system" when changed by direct SQL.';
create index audit_log_record_idx on audit_log (table_name, record_id);
create index audit_log_created_idx on audit_log (created_at);

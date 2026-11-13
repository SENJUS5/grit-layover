-- =============================================================================
-- GRIT Layover - 002_functions.sql
-- Helpers, guard triggers, audit triggers and the business functions that are
-- the ONLY write path for the app (direct table writes are revoked in 004).
--
-- Conventions
--   * Business functions are SECURITY DEFINER with a pinned search_path.
--   * Every business function takes p_actor_role / p_actor_id. They are copied
--     into settings (app.actor_role / app.actor_id) that the audit trigger
--     reads, scoped to the function call by a function-level SET clause. Parameter order: required business args, then the
--     actor, then optional args (Postgres needs defaults last).
--   * Errors are plain sentences: the app shows them to users as-is.
--   * Functions whose name starts with "_" are internal and not granted to
--     anon/authenticated (see 004).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Time helpers (principle 6: all date logic in IST)
-- -----------------------------------------------------------------------------
create function ist_date(p_ts timestamptz) returns date
language sql immutable parallel safe
set search_path = public, pg_temp
as $$ select (p_ts at time zone 'Asia/Kolkata')::date $$;
comment on function ist_date(timestamptz) is 'Calendar date of a timestamp in Asia/Kolkata.';

create function ist_today() returns date
language sql stable parallel safe
set search_path = public, pg_temp
as $$ select ist_date(now()) $$;
comment on function ist_today() is 'Today in Asia/Kolkata. now() is fixed for a transaction, so this is too.';

create function format_ist(p_ts timestamptz) returns text
language sql stable
set search_path = public, pg_temp
as $$ select to_char(p_ts at time zone 'Asia/Kolkata', 'DD Mon YYYY, HH24:MI "IST"') $$;
comment on function format_ist(timestamptz) is 'Human-readable IST timestamp for error messages.';

-- -----------------------------------------------------------------------------
-- Eligibility (shared by book_slot and the views, so the rule lives in one place)
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER because it reads badge_awards, which the API roles cannot
-- read directly, and the views call it with the caller's rights. It only
-- returns a reason string that student_journey already exposes.
create function student_ineligibility_reason(p_student students) returns text
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select nullif(concat_ws('; ',
    case when not p_student.is_registered_approved then 'Not registered/approved for GRIT' end,
    case when p_student.attendance_pct < ps.min_attendance_pct
         then format('Attendance %s%% (needs %s%%)', trim_scale(p_student.attendance_pct), trim_scale(ps.min_attendance_pct)) end,
    case when p_student.has_admin_hold then 'Admin hold on account' end,
    case when not p_student.conduct_ok then 'Confirmed conduct case (eligibility not restored)' end,
    -- Qualification deadline: once it has passed, only students holding a badge
    -- from an interview held (IST) on or before it may keep booking. awarded_at
    -- is the interview time, so a 30 Dec interview entered on 2 Jan qualifies.
    case when ist_today() > ps.badge_deadline
          and not exists (select 1 from badge_awards a
                          where a.student_id = p_student.id and a.status = 'active'
                            and ist_date(a.awarded_at) <= ps.badge_deadline)
         then format('Missed the %s badge deadline', to_char(ps.badge_deadline, 'FMDD Mon')) end
  ), '')
  from program_settings ps
$$;
comment on function student_ineligibility_reason(students) is 'Why a student may not book, or null if eligible: approval, attendance, hold, conduct, missed badge deadline. Used by book_slot and every view.';

-- -----------------------------------------------------------------------------
-- Actor context
-- -----------------------------------------------------------------------------
create function _set_actor(p_actor_role text, p_actor_id text) returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if p_actor_role is null or p_actor_role not in ('student', 'interviewer', 'admin', 'system') then
    raise exception using message = format('Unknown role "%s". Use student, interviewer, admin or system.', p_actor_role);
  end if;
  if p_actor_role <> 'system' and coalesce(btrim(p_actor_id), '') = '' then
    raise exception 'Please choose who you are acting as before making changes.';
  end if;
  -- is_local = true keeps the values from leaking between requests on a pooled
  -- connection. Every public business function also declares
  -- "SET app.actor_role = 'system'", so the actor is scoped to that one call:
  -- direct SQL later in the same transaction is logged as 'system', not as
  -- whoever called the last function.
  perform set_config('app.actor_role', p_actor_role, true);
  perform set_config('app.actor_id', coalesce(p_actor_id, ''), true);
end;
$$;
comment on function _set_actor(text, text) is 'Validates the acting role and stores it for the audit trigger (transaction-local).';

create function _require_role(p_actor_role text, variadic p_allowed text[]) returns void
language plpgsql immutable
set search_path = public, pg_temp
as $$
begin
  if not (p_actor_role = any (p_allowed)) then
    raise exception using message = format('This action is only available to: %s.', array_to_string(p_allowed, ', '));
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Guard triggers (principles 1 and 2)
-- -----------------------------------------------------------------------------
create function _forbid_update_delete() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception using message = format(
    '%s is append-only: rows can never be changed or removed. Add a correcting row instead.', tg_table_name);
end;
$$;

create function _forbid_delete() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception using message = format(
    'Rows in %s are never deleted. Change their status instead (cancel, revoke, withdraw).', tg_table_name);
end;
$$;

-- Insert-only tables: no UPDATE, DELETE or TRUNCATE.
create trigger miles_ledger_append_only  before update or delete on miles_ledger  for each row execute function _forbid_update_delete();
create trigger skill_results_append_only before update or delete on skill_results for each row execute function _forbid_update_delete();
create trigger audit_log_append_only     before update or delete on audit_log     for each row execute function _forbid_update_delete();
create trigger miles_ledger_no_truncate  before truncate on miles_ledger  for each statement execute function _forbid_update_delete();
create trigger skill_results_no_truncate before truncate on skill_results for each statement execute function _forbid_update_delete();
create trigger audit_log_no_truncate     before truncate on audit_log     for each statement execute function _forbid_update_delete();

-- Everything else: updates are allowed (status changes), deletes are not.
do $$
declare t text;
begin
  foreach t in array array['program_settings', 'students', 'interviewers', 'skills', 'badges',
                           'badge_requirements', 'slots', 'bookings', 'interview_results',
                           'project_submissions', 'badge_awards', 'malpractice_cases']
  loop
    execute format('create trigger %1$s_no_delete before delete on %1$I for each row execute function _forbid_delete()', t);
    execute format('create trigger %1$s_no_truncate before truncate on %1$I for each statement execute function _forbid_delete()', t);
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- updated_at maintenance
-- -----------------------------------------------------------------------------
create function _touch_updated_at() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger program_settings_touch  before update on program_settings  for each row execute function _touch_updated_at();
create trigger bookings_touch          before update on bookings          for each row execute function _touch_updated_at();
create trigger interview_results_touch before update on interview_results for each row execute function _touch_updated_at();

-- -----------------------------------------------------------------------------
-- Level validation: a CHECK cannot look at another table, so a trigger does.
-- -----------------------------------------------------------------------------
create function _check_level_within_skill() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  -- Read via jsonb: the two tables name the column differently, and PL/pgSQL
  -- rejects a reference to a field the row type does not have.
  v_level int := coalesce((to_jsonb(new) ->> 'required_level')::int, (to_jsonb(new) ->> 'level')::int);
  v_skill skills;
begin
  select * into v_skill from skills where id = new.skill_id;
  if v_level > v_skill.max_level then
    raise exception using message = format('%s only has levels 1 to %s (got level %s).', v_skill.name, v_skill.max_level, v_level);
  end if;
  return new;
end;
$$;

create trigger skill_results_level_check      before insert on skill_results
  for each row execute function _check_level_within_skill();
create trigger badge_requirements_level_check before insert or update on badge_requirements
  for each row execute function _check_level_within_skill();

-- -----------------------------------------------------------------------------
-- Skill medals -> Miles. GRIT counts only the HIGHEST grade per skill level:
-- an attempt adds the difference between its Miles and the previous best.
-- Example: try_again (+5), then silver (18): ledger gets +5 then +13.
-- -----------------------------------------------------------------------------
create function _credit_skill_miles() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_previous_best int;
begin
  -- Serialise attempts per student so two simultaneous rows cannot both be
  -- credited against the same "previous best".
  perform 1 from students where id = new.student_id for update;

  select coalesce(max(miles), 0) into v_previous_best
  from skill_results
  where student_id = new.student_id and skill_id = new.skill_id and level = new.level
    and id <> new.id;

  if new.miles > v_previous_best then
    insert into miles_ledger (student_id, amount, reason, source_id, note, effective_at)
    values (new.student_id,
            new.miles - v_previous_best,
            -- First Miles at this skill level vs. an improvement on earlier Miles.
            case when v_previous_best = 0 then 'skill_medal' else 'medal_upgrade' end,
            new.id,
            format('%s L%s %s', (select name from skills where id = new.skill_id), new.level, new.medal),
            new.attempted_at);
  end if;
  return null;
end;
$$;

create trigger skill_results_credit_miles after insert on skill_results
  for each row execute function _credit_skill_miles();

-- -----------------------------------------------------------------------------
-- Malpractice review deadline: fixed at creation, immutable afterwards.
-- -----------------------------------------------------------------------------
create function _set_case_review_due() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.review_due_at := new.flagged_at
      + make_interval(days => (select review_limit_days from program_settings where id = 1));
  elsif new.review_due_at is distinct from old.review_due_at or new.flagged_at is distinct from old.flagged_at then
    raise exception 'A case''s flag time and review deadline are fixed when it is opened.';
  end if;
  return new;
end;
$$;

create trigger malpractice_cases_review_due before insert or update on malpractice_cases
  for each row execute function _set_case_review_due();

-- -----------------------------------------------------------------------------
-- Audit trigger (principle 3)
-- -----------------------------------------------------------------------------
create function _audit_row() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_before jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_after  jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
begin
  -- Skip no-op updates so the log only holds real changes.
  if tg_op = 'UPDATE' and v_before = v_after then
    return null;
  end if;
  insert into audit_log (actor_role, actor_id, action, table_name, record_id, before, after)
  values (coalesce(nullif(current_setting('app.actor_role', true), ''), 'system'),
          nullif(current_setting('app.actor_id', true), ''),
          tg_op, tg_table_name,
          coalesce(v_after, v_before) ->> 'id',
          v_before, v_after);
  return null;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['program_settings', 'students', 'interviewers', 'skill_results', 'slots',
                           'bookings', 'interview_results', 'project_submissions', 'badge_awards',
                           'miles_ledger', 'malpractice_cases']
  loop
    execute format('create trigger %1$s_audit after insert or update or delete on %1$I for each row execute function _audit_row()', t);
  end loop;
end;
$$;

-- =============================================================================
-- Business functions
-- =============================================================================

-- -----------------------------------------------------------------------------
-- record_skill_result: entry point for the contest system.
-- -----------------------------------------------------------------------------
create function record_skill_result(
  p_student uuid, p_skill uuid, p_level int, p_medal text, p_miles int,
  p_actor_role text, p_actor_id text,
  p_attempted_at timestamptz default now()
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare v_id uuid;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'system', 'admin');

  insert into skill_results (student_id, skill_id, level, medal, miles, attempted_at)
  values (p_student, p_skill, p_level, p_medal, p_miles, p_attempted_at)
  returning id into v_id;
  return v_id;
end;
$$;
comment on function record_skill_result(uuid, uuid, int, text, int, text, text, timestamptz) is
  'Stores one contest attempt; a trigger credits only the improvement over the previous best.';

-- -----------------------------------------------------------------------------
-- create_slot
-- -----------------------------------------------------------------------------
create function create_slot(
  p_interviewer uuid, p_starts_at timestamptz,
  p_actor_role text, p_actor_id text
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare
  v_interviewer interviewers;
  v_id uuid;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'interviewer', 'admin');
  if p_actor_role = 'interviewer' and p_actor_id <> p_interviewer::text then
    raise exception 'Interviewers can only create their own slots.';
  end if;

  select * into v_interviewer from interviewers where id = p_interviewer;
  if not found then raise exception 'Interviewer not found.'; end if;
  if not v_interviewer.is_active then raise exception 'Inactive interviewers cannot publish slots.'; end if;
  if p_starts_at <= now() then raise exception 'A new slot must start in the future.'; end if;

  begin
    insert into slots (interviewer_id, starts_at, ends_at)
    values (p_interviewer, p_starts_at,
            p_starts_at + make_interval(mins => (select slot_minutes from program_settings where id = 1)))
    returning id into v_id;
  exception when exclusion_violation then
    raise exception using message = format('You already have an open slot overlapping %s.', format_ist(p_starts_at));
  end;
  return v_id;
end;
$$;
comment on function create_slot(uuid, timestamptz, text, text) is
  'Publishes a slot of program_settings.slot_minutes. Overlaps are rejected by the exclusion constraint.';

-- -----------------------------------------------------------------------------
-- _create_booking: every booking rule, shared by book_slot and reschedule_booking.
-- -----------------------------------------------------------------------------
create function _create_booking(
  p_student uuid, p_badge uuid, p_slot uuid, p_rescheduled_from uuid
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_settings     program_settings;
  v_student      students;
  v_badge        badges;
  v_prev_badge   badges;
  v_slot         slots;
  v_interviewer  interviewers;
  v_reason       text;
  v_missing      text;
  v_retake_after date;
  v_booking_id   uuid;
  v_constraint   text;
begin
  select * into v_settings from program_settings where id = 1;

  -- Lock order is always student, then slot, so concurrent calls cannot deadlock.
  -- The student lock serialises one student's bookings (no two overlapping interviews).
  select * into v_student from students where id = p_student for update;
  if not found then raise exception 'Student not found.'; end if;

  -- Student eligibility.
  if not v_student.is_registered_approved then
    raise exception 'You are not registered and approved for GRIT yet, so you cannot book an interview.';
  end if;
  if v_student.attendance_pct < v_settings.min_attendance_pct then
    raise exception using message = format(
      'Your attendance is %s%%. You need at least %s%% to book an interview.',
      trim_scale(v_student.attendance_pct), trim_scale(v_settings.min_attendance_pct));
  end if;
  if v_student.has_admin_hold then
    raise exception 'Your account has an admin hold. Please contact the GRIT team.';
  end if;
  if not v_student.conduct_ok then
    raise exception 'Booking is blocked after a confirmed conduct case. An admin must restore your eligibility before you can book again.';
  end if;
  -- Anything else in the shared eligibility rule (e.g. the badge deadline).
  -- It is the same function the views use, so "Not eligible" and book_slot
  -- can never disagree. The checks above only give friendlier messages.
  v_reason := student_ineligibility_reason(v_student);
  if v_reason is not null then
    raise exception using message = format('You cannot book an interview: %s.', v_reason);
  end if;

  -- Badge rules.
  select * into v_badge from badges where id = p_badge;
  if not found then raise exception 'Badge not found.'; end if;
  if v_badge.is_locked then
    raise exception using message = format('%s %s is not open for interviews yet.', v_badge.track, v_badge.level);
  end if;
  if exists (select 1 from badge_awards where student_id = p_student and badge_id = p_badge and status = 'active') then
    raise exception using message = format('You already hold %s %s.', v_badge.track, v_badge.level);
  end if;

  -- No skipping: the previous badge in the track must be held.
  if v_badge.sequence > 1 then
    select * into v_prev_badge from badges where track = v_badge.track and sequence = v_badge.sequence - 1;
    if not exists (select 1 from badge_awards
                   where student_id = p_student and badge_id = v_prev_badge.id and status = 'active') then
      raise exception using message = format('Earn %s %s first. Badges in a track cannot be skipped.',
                                             v_prev_badge.track, v_prev_badge.level);
    end if;
  end if;

  -- Every required skill cleared (gold/silver at the required level or higher).
  select string_agg(format('%s L%s', sk.name, r.required_level), ', ' order by sk.name)
    into v_missing
  from badge_requirements r
  join skills sk on sk.id = r.skill_id
  where r.badge_id = p_badge
    and not exists (select 1 from skill_results sr
                    where sr.student_id = p_student and sr.skill_id = r.skill_id
                      and sr.level >= r.required_level and sr.medal in ('gold', 'silver'));
  if v_missing is not null then
    raise exception using message = format('Clear these skills with gold or silver first: %s.', v_missing);
  end if;

  if v_badge.needs_project and not exists (
       select 1 from project_submissions
       where student_id = p_student and badge_id = p_badge and status = 'approved') then
    raise exception 'Your project for this badge must be approved before you can book.';
  end if;

  if exists (select 1 from bookings where student_id = p_student and badge_id = p_badge and status = 'active') then
    raise exception 'You already have an interview booked for this badge. Cancel or reschedule it instead.';
  end if;

  -- Retake cooldown from the latest result for this badge.
  select retake_after into v_retake_after
  from interview_results
  where student_id = p_student and badge_id = p_badge
  order by interview_held_at desc, recorded_at desc
  limit 1;
  if v_retake_after is not null and v_retake_after > ist_today() then
    raise exception using message = format('You can book a retake for this badge from %s.',
                                           to_char(v_retake_after, 'DD Mon YYYY'));
  end if;

  -- Slot rules. FOR UPDATE makes concurrent bookers of this slot queue here.
  select * into v_slot from slots where id = p_slot for update;
  if not found then raise exception 'Slot not found.'; end if;
  if v_slot.status <> 'open' then
    raise exception 'This slot has been withdrawn by the interviewer. Please pick another.';
  end if;
  select * into v_interviewer from interviewers where id = v_slot.interviewer_id;
  if not v_interviewer.is_active then
    raise exception 'This interviewer is no longer taking interviews. Please pick another slot.';
  end if;
  if v_slot.starts_at <= now() then
    raise exception 'This slot has already started. Please pick a future slot.';
  end if;
  if v_slot.starts_at < now() + make_interval(hours => v_settings.min_booking_notice_hours) then
    raise exception using message = format('Slots must be booked at least %s hours in advance.',
                                           v_settings.min_booking_notice_hours);
  end if;
  if exists (select 1 from bookings where slot_id = p_slot and status in ('active', 'completed')) then
    raise exception 'Sorry, this slot was just booked by someone else. Please pick another.';
  end if;

  -- A student cannot be in two interviews at once (e.g. two tracks, two interviewers).
  if exists (select 1 from bookings b join slots s on s.id = b.slot_id
             where b.student_id = p_student and b.status = 'active'
               and tstzrange(s.starts_at, s.ends_at) && tstzrange(v_slot.starts_at, v_slot.ends_at)) then
    raise exception 'You already have another interview booked at that time.';
  end if;

  -- The partial unique indexes are the final guard if two requests slip past
  -- the checks above at the same moment.
  begin
    insert into bookings (student_id, badge_id, slot_id, rescheduled_from_id)
    values (p_student, p_badge, p_slot, p_rescheduled_from)
    returning id into v_booking_id;
  exception when unique_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint = 'bookings_one_per_slot' then
      raise exception 'Sorry, this slot was just booked by someone else. Please pick another.';
    elsif v_constraint = 'bookings_one_active_per_badge' then
      raise exception 'You already have an interview booked for this badge.';
    end if;
    raise;
  end;

  return v_booking_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- book_slot
-- -----------------------------------------------------------------------------
create function book_slot(
  p_student uuid, p_badge uuid, p_slot uuid,
  p_actor_role text, p_actor_id text
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'student', 'admin');
  if p_actor_role = 'student' and p_actor_id <> p_student::text then
    raise exception 'Students can only book interviews for themselves.';
  end if;
  -- An open malpractice case deliberately does NOT block booking: badges
  -- "count but hold" - only final decisions wait for the case.
  return _create_booking(p_student, p_badge, p_slot, null);
end;
$$;
comment on function book_slot(uuid, uuid, uuid, text, text) is
  'Books a badge interview after checking eligibility, badge order, skills, project, cooldown and slot rules in one transaction.';

-- -----------------------------------------------------------------------------
-- cancel_booking
-- -----------------------------------------------------------------------------
create function _cancel_booking(p_booking bookings, p_by text, p_reason text) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update bookings
     set status = 'cancelled', cancelled_by = p_by, cancel_reason = p_reason, cancelled_at = now()
   where id = p_booking.id;
end;
$$;

create function cancel_booking(
  p_booking uuid, p_reason text,
  p_actor_role text, p_actor_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare
  v_booking bookings;
  v_slot    slots;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'student', 'interviewer', 'admin');
  if coalesce(btrim(p_reason), '') = '' then raise exception 'Please give a reason for cancelling.'; end if;

  select * into v_booking from bookings where id = p_booking for update;
  if not found then raise exception 'Booking not found.'; end if;
  select * into v_slot from slots where id = v_booking.slot_id;

  if p_actor_role = 'student' and p_actor_id <> v_booking.student_id::text then
    raise exception 'Students can only cancel their own bookings.';
  end if;
  if p_actor_role = 'interviewer' and p_actor_id <> v_slot.interviewer_id::text then
    raise exception 'Interviewers can only cancel bookings on their own slots.';
  end if;
  if v_booking.status <> 'active' then
    raise exception using message = format('This booking is already %s.', v_booking.status);
  end if;
  if v_slot.starts_at <= now() and p_actor_role <> 'admin' then
    raise exception 'This interview has already started. Only an admin can cancel it now.';
  end if;

  perform _cancel_booking(v_booking, p_actor_role, p_reason);
end;
$$;
comment on function cancel_booking(uuid, text, text, text) is
  'Cancels an active booking (never deletes it). After the slot starts, admin only.';

-- -----------------------------------------------------------------------------
-- reschedule_booking: cancel + book in one transaction. Any failure raises,
-- which rolls back the cancellation too, so the old booking stays intact.
-- -----------------------------------------------------------------------------
create function reschedule_booking(
  p_booking uuid, p_new_slot uuid,
  p_actor_role text, p_actor_id text
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare
  v_booking bookings;
  v_slot    slots;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'student', 'admin');

  select * into v_booking from bookings where id = p_booking for update;
  if not found then raise exception 'Booking not found.'; end if;
  if p_actor_role = 'student' and p_actor_id <> v_booking.student_id::text then
    raise exception 'Students can only reschedule their own bookings.';
  end if;
  if v_booking.status <> 'active' then
    raise exception using message = format('Only active bookings can be rescheduled; this one is %s.', v_booking.status);
  end if;
  if v_booking.slot_id = p_new_slot then
    raise exception 'That is the slot you already have.';
  end if;
  select * into v_slot from slots where id = v_booking.slot_id;
  if v_slot.starts_at <= now() and p_actor_role <> 'admin' then
    raise exception 'This interview has already started, so it cannot be rescheduled.';
  end if;

  -- Cancel first so the "one active booking per badge" rule lets the new one in.
  perform _cancel_booking(v_booking, p_actor_role, 'Rescheduled');
  return _create_booking(v_booking.student_id, v_booking.badge_id, p_new_slot, v_booking.id);
end;
$$;
comment on function reschedule_booking(uuid, uuid, text, text) is
  'Moves a booking to a new slot atomically; the new booking links back via rescheduled_from_id.';

-- -----------------------------------------------------------------------------
-- withdraw_slot
-- -----------------------------------------------------------------------------
create function withdraw_slot(
  p_slot uuid, p_interviewer uuid, p_reason text,
  p_actor_role text, p_actor_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare
  v_slot    slots;
  v_booking bookings;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'interviewer', 'admin');
  if p_actor_role = 'interviewer' and p_actor_id <> p_interviewer::text then
    raise exception 'Interviewers can only withdraw their own slots.';
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'Please give a reason for withdrawing the slot.'; end if;

  select * into v_slot from slots where id = p_slot for update;
  if not found then raise exception 'Slot not found.'; end if;
  if v_slot.interviewer_id <> p_interviewer then
    raise exception 'This slot belongs to a different interviewer.';
  end if;
  if v_slot.status = 'withdrawn' then raise exception 'This slot is already withdrawn.'; end if;
  if v_slot.starts_at <= now() then raise exception 'A slot that has already started cannot be withdrawn.'; end if;

  update slots set status = 'withdrawn', withdrawn_at = now(), withdraw_reason = p_reason where id = p_slot;

  -- The student's booking is cancelled, not lost: it stays on record with the reason.
  for v_booking in select * from bookings where slot_id = p_slot and status = 'active' for update loop
    perform _cancel_booking(v_booking,
                            case p_actor_role when 'interviewer' then 'interviewer' else 'admin' end,
                            'Slot withdrawn: ' || p_reason);
  end loop;
end;
$$;
comment on function withdraw_slot(uuid, uuid, text, text, text) is
  'Withdraws a future slot and cancels any active booking on it (cancelled_by = interviewer).';

-- -----------------------------------------------------------------------------
-- Awards: grant and revoke (internal)
-- -----------------------------------------------------------------------------
create function _grant_award(p_result uuid) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_result     interview_results;
  v_badge      badges;
  v_prev_badge badges;
  v_award_id   uuid;
begin
  select * into v_result from interview_results where id = p_result;
  select * into v_badge from badges where id = v_result.badge_id;

  if exists (select 1 from badge_awards where student_id = v_result.student_id
             and badge_id = v_result.badge_id and status = 'active') then
    raise exception using message = format('The student already holds %s %s.', v_badge.track, v_badge.level);
  end if;
  -- Re-checked here because a correction can grant an award long after booking,
  -- by which time the previous badge may have been revoked.
  if v_badge.sequence > 1 then
    select * into v_prev_badge from badges where track = v_badge.track and sequence = v_badge.sequence - 1;
    if not exists (select 1 from badge_awards where student_id = v_result.student_id
                   and badge_id = v_prev_badge.id and status = 'active') then
      raise exception using message = format('Cannot award %s %s: the student no longer holds %s %s.',
                                             v_badge.track, v_badge.level, v_prev_badge.track, v_prev_badge.level);
    end if;
  end if;

  insert into badge_awards (student_id, badge_id, result_id, awarded_at)
  values (v_result.student_id, v_result.badge_id, v_result.id, v_result.interview_held_at)
  returning id into v_award_id;

  insert into miles_ledger (student_id, amount, reason, source_id, note, effective_at)
  values (v_result.student_id, v_badge.bonus_miles, 'badge_bonus', v_award_id,
          format('%s %s awarded', v_badge.track, v_badge.level),
          v_result.interview_held_at);

  return v_award_id;
end;
$$;

create function _revoke_award(
  p_award uuid, p_cause text, p_reason text,
  p_actor_role text, p_actor_id text,
  p_caused_by uuid default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_award   badge_awards;
  v_badge   badges;
  v_booking bookings;
  v_child   record;
begin
  select * into v_award from badge_awards where id = p_award for update;
  if not found then raise exception 'Badge award not found.'; end if;
  if v_award.status <> 'active' then raise exception 'This badge has already been revoked.'; end if;
  select * into v_badge from badges where id = v_award.badge_id;

  update badge_awards
     set status = 'revoked', revoked_at = now(), revoke_reason = p_reason, revoke_cause = p_cause,
         caused_by_award_id = p_caused_by, revoked_by = coalesce(p_actor_id, p_actor_role)
   where id = p_award;

  -- The passbook gets a correcting row; the original bonus row stays.
  insert into miles_ledger (student_id, amount, reason, source_id, note, effective_at)
  values (v_award.student_id, -v_badge.bonus_miles, 'badge_revoked', p_award,
          format('%s %s revoked (%s)', v_badge.track, v_badge.level, p_cause), now());

  -- Interviews booked for higher badges in this track depended on this badge
  -- (no skipping), so cancel them. cancelled_by is the acting role: only an
  -- admin (case decision, correction) or an interviewer (same-day correction)
  -- can trigger a revocation, and both fit the bookings CHECK.
  for v_booking in
    select bo.*
    from bookings bo
    join badges b on b.id = bo.badge_id
    where bo.student_id = v_award.student_id and bo.status = 'active'
      and b.track = v_badge.track and b.sequence > v_badge.sequence
    for update of bo
  loop
    perform _cancel_booking(v_booking, p_actor_role, format('Earlier badge (%s) was revoked', v_badge.level));
  end loop;

  -- Cascade: higher badges in the same track depended on this one. Walk them in
  -- order; the recursive call revokes everything above the child, so later
  -- iterations find those rows already revoked and skip them.
  for v_child in
    select a.id
    from badge_awards a join badges b on b.id = a.badge_id
    where a.student_id = v_award.student_id and a.status = 'active'
      and b.track = v_badge.track and b.sequence > v_badge.sequence
    order by b.sequence
  loop
    if (select status from badge_awards where id = v_child.id) = 'active' then
      perform _revoke_award(v_child.id, 'prerequisite_revoked',
                            format('%s %s was revoked', v_badge.track, v_badge.level),
                            p_actor_role, p_actor_id, p_award);
    end if;
  end loop;
end;
$$;
comment on function _revoke_award(uuid, text, text, text, text, uuid) is
  'Internal. Revokes an award, debits its bonus, cancels active bookings for higher badges in the track, and cascades to higher awards.';

-- -----------------------------------------------------------------------------
-- record_result
-- -----------------------------------------------------------------------------
create function _retake_date(p_outcome text, p_held_at timestamptz, p_given date) returns date
language plpgsql stable
set search_path = public, pg_temp
as $$
begin
  if p_outcome in ('pass', 'technical_issue') then
    if p_given is not null then
      raise exception 'A retake date only applies to fail, retake later or no-show results.';
    end if;
    return null;  -- technical_issue: rebook immediately, no penalty
  end if;
  if p_given is not null and p_given <= ist_date(p_held_at) then
    raise exception 'The retake date must be after the interview date.';
  end if;
  return coalesce(p_given, ist_date(p_held_at) + (select retake_gap_days from program_settings where id = 1));
end;
$$;

create function record_result(
  p_booking uuid, p_interviewer uuid, p_outcome text, p_feedback text,
  p_actor_role text, p_actor_id text,
  p_retake_after date default null,
  p_interview_held_at timestamptz default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare
  v_booking   bookings;
  v_slot      slots;
  v_held_at   timestamptz;
  v_result_id uuid;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'interviewer');
  if p_actor_id <> p_interviewer::text then
    raise exception 'You can only record results as yourself.';
  end if;
  if p_outcome is null or p_outcome not in ('pass', 'fail', 'retake_later', 'no_show', 'technical_issue') then
    raise exception 'Outcome must be pass, fail, retake_later, no_show or technical_issue.';
  end if;

  select * into v_booking from bookings where id = p_booking for update;
  if not found then raise exception 'Booking not found.'; end if;
  select * into v_slot from slots where id = v_booking.slot_id;

  if v_slot.interviewer_id <> p_interviewer then
    raise exception 'Only the interviewer who owns this slot can record its result.';
  end if;
  if v_booking.status = 'completed' then
    raise exception 'A result has already been recorded for this booking. Use a correction instead.';
  end if;
  if v_booking.status = 'cancelled' then
    raise exception 'This booking was cancelled, so it cannot have a result.';
  end if;
  if v_slot.starts_at > now() then
    raise exception using message = format('This interview starts at %s. Record the result after it has started.',
                                           format_ist(v_slot.starts_at));
  end if;

  v_held_at := coalesce(p_interview_held_at, v_slot.starts_at);
  if v_held_at > now() then raise exception 'The interview time cannot be in the future.'; end if;
  if v_held_at < v_slot.starts_at then raise exception 'The interview cannot have happened before its slot started.'; end if;

  insert into interview_results (booking_id, student_id, badge_id, outcome, feedback, retake_after,
                                 interview_held_at, recorded_by)
  values (v_booking.id, v_booking.student_id, v_booking.badge_id, p_outcome, p_feedback,
          _retake_date(p_outcome, v_held_at, p_retake_after), v_held_at, p_interviewer)
  returning id into v_result_id;

  update bookings set status = 'completed' where id = v_booking.id;

  if p_outcome = 'pass' then
    perform _grant_award(v_result_id);  -- award dated interview_held_at, + bonus Miles
  end if;
  return v_result_id;
end;
$$;
comment on function record_result(uuid, uuid, text, text, text, text, date, timestamptz) is
  'Records an interview outcome, completes the booking, and on pass awards the badge and its bonus Miles.';

-- -----------------------------------------------------------------------------
-- correct_result
-- -----------------------------------------------------------------------------
create function correct_result(
  p_result uuid, p_new_outcome text, p_reason text,
  p_actor_role text, p_actor_id text,
  p_retake_after date default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare
  v_result       interview_results;
  v_award        uuid;
  v_booking      bookings;
  v_retake_after date;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'interviewer', 'admin');
  if coalesce(btrim(p_reason), '') = '' then raise exception 'Please give a reason for the correction.'; end if;
  if p_new_outcome is null or p_new_outcome not in ('pass', 'fail', 'retake_later', 'no_show', 'technical_issue') then
    raise exception 'Outcome must be pass, fail, retake_later, no_show or technical_issue.';
  end if;

  select * into v_result from interview_results where id = p_result for update;
  if not found then raise exception 'Result not found.'; end if;

  if p_actor_role = 'interviewer' then
    if p_actor_id <> v_result.recorded_by::text then
      raise exception 'Only the interviewer who recorded this result can correct it. Please ask an admin.';
    end if;
    if ist_date(v_result.recorded_at) <> ist_today() then
      raise exception 'Interviewers can correct a result only on the day it was recorded. Please ask an admin.';
    end if;
  end if;
  if p_new_outcome = v_result.outcome then
    raise exception using message = format('The result is already "%s".', v_result.outcome);
  end if;

  -- GRIT rule: a student whose pass is corrected can rebook any time, so a
  -- corrected pass never carries a retake cooldown. Other corrections keep the
  -- normal cooldown, counted from the interview date.
  if v_result.outcome = 'pass' then
    if p_retake_after is not null then
      raise exception 'A corrected pass has no retake date: the student can rebook any time.';
    end if;
    v_retake_after := null;
  else
    v_retake_after := _retake_date(p_new_outcome, v_result.interview_held_at, p_retake_after);
  end if;

  -- pass -> not pass: the badge was never really earned. Revoking cascades.
  if v_result.outcome = 'pass' then
    select id into v_award from badge_awards where result_id = p_result and status = 'active';
    if v_award is not null then
      perform _revoke_award(v_award, 'result_corrected', p_reason, p_actor_role, p_actor_id);
    end if;
  end if;

  update interview_results
     set outcome = p_new_outcome,
         retake_after = v_retake_after,
         corrected_at = now(),
         correction_reason = p_reason
   where id = p_result;

  -- not pass -> pass: award now, still dated by the interview.
  if p_new_outcome = 'pass' then
    -- A retake the student booked meanwhile is no longer needed.
    for v_booking in select * from bookings
                     where student_id = v_result.student_id and badge_id = v_result.badge_id
                       and status = 'active' for update loop
      perform _cancel_booking(v_booking, p_actor_role, 'Earlier result corrected to pass');
    end loop;
    perform _grant_award(p_result);
  end if;
end;
$$;
comment on function correct_result(uuid, text, text, text, text, date) is
  'Changes an outcome. Interviewers: same IST day as recorded_at, own results only. Admins: any time. A corrected pass revokes the badge with no retake cooldown.';

-- -----------------------------------------------------------------------------
-- Malpractice
-- -----------------------------------------------------------------------------
create function flag_malpractice(
  p_award uuid, p_evidence text,
  p_actor_role text, p_actor_id text
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare
  v_award badge_awards;
  v_id    uuid;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'interviewer', 'admin');
  if coalesce(btrim(p_evidence), '') = '' then raise exception 'Please describe the evidence.'; end if;

  select * into v_award from badge_awards where id = p_award for update;
  if not found then raise exception 'Badge award not found.'; end if;
  if v_award.status <> 'active' then raise exception 'This badge is already revoked.'; end if;

  begin
    -- flagged_by is the acting user, so a flag cannot be raised in someone else's name.
    insert into malpractice_cases (student_id, badge_award_id, flagged_by, evidence)
    values (v_award.student_id, p_award, p_actor_id, p_evidence)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'There is already an open case for this badge.';
  end;
  return v_id;
end;
$$;
comment on function flag_malpractice(uuid, text, text, text) is
  'Opens a malpractice case. The badge still counts; final steps wait. Review deadline is set by trigger.';

create function decide_case(
  p_case uuid, p_decision text, p_note text,
  p_actor_role text, p_actor_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare
  v_case malpractice_cases;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'admin');
  if p_decision is null or p_decision not in ('confirmed', 'dismissed') then
    raise exception 'Decision must be confirmed or dismissed.';
  end if;
  if coalesce(btrim(p_note), '') = '' then raise exception 'Please add a note explaining the decision.'; end if;

  select * into v_case from malpractice_cases where id = p_case for update;
  if not found then raise exception 'Case not found.'; end if;
  if v_case.status <> 'open' then
    raise exception using message = format('This case was already %s.', v_case.status);
  end if;

  update malpractice_cases
     set status = p_decision, decided_by = p_actor_id, decided_at = now(), decision_note = p_note
   where id = p_case;

  if p_decision = 'confirmed' then
    -- The award may already be gone (e.g. revoked by a cascade); conduct is still recorded.
    if (select status from badge_awards where id = v_case.badge_award_id) = 'active' then
      perform _revoke_award(v_case.badge_award_id, 'malpractice', p_note, p_actor_role, p_actor_id);
    end if;
    update students set conduct_ok = false where id = v_case.student_id;
  end if;
  -- dismissed: nothing else changes; the case stays on record.
end;
$$;
comment on function decide_case(uuid, text, text, text, text) is
  'Admin decision. Confirmed: revoke the badge (cascading) and set conduct_ok = false until an admin calls restore_eligibility(). Dismissed: no change.';

-- -----------------------------------------------------------------------------
-- restore_eligibility: after a confirmed malpractice case the student can book
-- again ONLY when an admin restores eligibility. Revoked badges stay revoked;
-- the student re-earns them through new interviews.
-- -----------------------------------------------------------------------------
create function restore_eligibility(
  p_student uuid, p_note text,
  p_actor_role text, p_actor_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare
  v_student students;
  v_cases   int;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'admin');
  if coalesce(btrim(p_note), '') = '' then
    raise exception 'Please add a note explaining why eligibility is being restored.';
  end if;

  select * into v_student from students where id = p_student for update;
  if not found then raise exception 'Student not found.'; end if;
  if v_student.conduct_ok then
    raise exception 'This student is not blocked by a conduct case, so there is nothing to restore.';
  end if;

  -- Record who restored eligibility and why on every confirmed case that was
  -- still holding the student back (usually one).
  update malpractice_cases
     set eligibility_restored_at = now(), eligibility_restored_by = p_actor_id, restore_note = p_note
   where student_id = p_student and status = 'confirmed' and eligibility_restored_at is null;
  get diagnostics v_cases = row_count;
  if v_cases = 0 then
    raise exception 'No confirmed malpractice case is blocking this student, so there is nothing to restore.';
  end if;

  update students set conduct_ok = true where id = p_student;
end;
$$;
comment on function restore_eligibility(uuid, text, text, text) is
  'Admin only. Lets a student book again after a confirmed malpractice case: conduct_ok = true, with who/why stamped on the case. Revoked badges stay revoked.';

-- -----------------------------------------------------------------------------
-- Projects (Robotics)
-- -----------------------------------------------------------------------------
create function submit_project(
  p_student uuid, p_badge uuid, p_link text,
  p_actor_role text, p_actor_id text
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare v_id uuid;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'student', 'admin');
  if p_actor_role = 'student' and p_actor_id <> p_student::text then
    raise exception 'Students can only submit their own projects.';
  end if;
  if not exists (select 1 from badges where id = p_badge and needs_project) then
    raise exception 'This badge does not need a project.';
  end if;
  if coalesce(p_link, '') !~* '^https?://' then
    raise exception 'Please submit a full link starting with http:// or https://.';
  end if;

  begin
    insert into project_submissions (student_id, badge_id, link)
    values (p_student, p_badge, p_link)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'You already have a project submitted or approved for this badge.';
  end;
  return v_id;
end;
$$;
comment on function submit_project(uuid, uuid, text, text, text) is
  'Submits a project link for a needs_project badge. One live submission per badge; resubmit after rejection.';

create function review_project(
  p_submission uuid, p_decision text, p_note text,
  p_actor_role text, p_actor_id text
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
-- Actor scope: restored to its previous value when this function returns.
set app.actor_role = 'system'
set app.actor_id = ''
as $$
declare v_sub project_submissions;
begin
  perform _set_actor(p_actor_role, p_actor_id);
  perform _require_role(p_actor_role, 'interviewer', 'admin');
  if p_decision is null or p_decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected.';
  end if;

  select * into v_sub from project_submissions where id = p_submission for update;
  if not found then raise exception 'Project submission not found.'; end if;
  if v_sub.status <> 'submitted' then
    raise exception using message = format('This project was already %s.', v_sub.status);
  end if;

  update project_submissions
     set status = p_decision, reviewed_at = now(), review_note = p_note,
         reviewed_by = case when p_actor_role = 'interviewer' then p_actor_id::uuid end
   where id = p_submission;
end;
$$;
comment on function review_project(uuid, text, text, text, text) is 'Approves or rejects a submitted project.';

-- -----------------------------------------------------------------------------
-- Admin read functions: the only way the app reads cases and the audit log.
-- -----------------------------------------------------------------------------
create function admin_list_cases(p_actor_role text, p_actor_id text)
returns table (
  case_id uuid, student_id uuid, student_name text, track text, level text,
  status text, flagged_by text, flagged_at timestamptz, review_due_at timestamptz,
  is_overdue boolean, evidence text, decided_by text, decided_at timestamptz, decision_note text,
  eligibility_restored_at timestamptz, eligibility_restored_by text, restore_note text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_role(p_actor_role, 'admin');
  return query
    select c.id, s.id, s.name, b.track::text, b.level, c.status, c.flagged_by, c.flagged_at,
           c.review_due_at, (c.status = 'open' and c.review_due_at < now()),
           c.evidence, c.decided_by, c.decided_at, c.decision_note,
           c.eligibility_restored_at, c.eligibility_restored_by, c.restore_note
    from malpractice_cases c
    join students s     on s.id = c.student_id
    join badge_awards a on a.id = c.badge_award_id
    join badges b       on b.id = a.badge_id
    order by (c.status = 'open') desc, c.review_due_at;
end;
$$;
comment on function admin_list_cases(text, text) is 'Admin only. All malpractice cases, open first, soonest deadline first.';

create function admin_audit_log(
  p_actor_role text, p_actor_id text,
  p_table text default null, p_record_id text default null, p_limit int default 200
) returns setof audit_log
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_role(p_actor_role, 'admin');
  return query
    select * from audit_log
    where (p_table is null or table_name = p_table)
      and (p_record_id is null or record_id = p_record_id)
    order by id desc
    limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end;
$$;
comment on function admin_audit_log(text, text, text, text, int) is 'Admin only. Recent audit rows, optionally for one table / record.';

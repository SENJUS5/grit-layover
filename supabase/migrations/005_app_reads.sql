-- =============================================================================
-- GRIT Layover - 005_app_reads.sql
-- Read-only views and functions for the app's screens. Nothing here writes.
--
-- Access rules:
--   * Student reads take p_student plus the actor: a student may read only
--     their own data, an admin anyone's. Interviewer reads work the same way.
--   * Leaderboard- and interviewer-facing reads never reference
--     malpractice_cases (checks 8 and 32): an open case must not change the
--     standings or what an interviewer sees.
--   * Grants are explicit (section 5). Supabase gives new functions and views
--     to anon by default, and Postgres gives EXECUTE on new functions to PUBLIC.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Views
-- -----------------------------------------------------------------------------
create view student_directory as
select id as student_id, name, primary_track, batch, campus, section
from students
order by name;
comment on view student_directory is 'Every student''s name and track, for the app''s "View as" picker. No eligibility or case data.';

-- GRIT ranks each list on its own ("Top the Qualiflyer Leaderboard"). The
-- official order is leaderboard.rank, so numbering within a list only needs
-- that order; ties keep sharing a number.
create view leaderboard_lists as
select
  case when l.is_qualiflyer then 'Qualiflyers' else 'Pre-Qualiflyers' end as list,
  rank() over (partition by l.is_qualiflyer order by l.rank)::int        as list_rank,
  l.student_id,
  l.name,
  l.batch,
  l.campus,
  l.section,
  l.highest_badge,
  l.total_miles,
  l.skill_depth,
  l.is_qualiflyer,
  l.rank::int as overall_rank
from leaderboard l
order by l.is_qualiflyer desc, list_rank, l.name;
comment on view leaderboard_lists is 'GRIT''s two lists: Qualiflyers (hold an active badge) and Pre-Qualiflyers (registered, no active badge yet), each ranked from 1 in the official leaderboard order. Built only on leaderboard, so it never sees malpractice cases.';

-- -----------------------------------------------------------------------------
-- 2. Internal helpers (not granted)
-- -----------------------------------------------------------------------------
create function _require_self_or_admin(p_actor_role text, p_actor_id text, p_role text, p_id uuid)
returns void
language plpgsql stable
set search_path = public, pg_temp
as $$
begin
  perform _require_role(p_actor_role, p_role, 'admin');
  if p_actor_role = p_role and p_actor_id is distinct from p_id::text then
    raise exception using message = format('%ss can only see their own data.', initcap(p_role));
  end if;
end;
$$;
comment on function _require_self_or_admin(text, text, text, uuid) is
  'Internal. Lets a student (or interviewer) read only their own data, and an admin anyone''s.';

-- Where a student stands on the leaderboard lists, optionally with the latest
-- change of some of their awards undone ("where would they be without it").
-- It repeats the leaderboard's ranking rules so it can swap in the undone
-- values; check 29 proves it agrees with leaderboard_lists for every student.
-- Undoing an award:
--   * an active award (just earned): its badge_bonus row is left out and the
--     badge does not count;
--   * a revoked award (just removed): its badge_revoked row is left out and
--     the badge counts again.
-- p_listed says whether p_student is on the leaderboard at all; every other
-- student uses the leaderboard's own rule (registered and conduct_ok).
create function _standing(p_student uuid, p_undo_awards uuid[], p_listed boolean)
returns table (list text, list_rank int, total_miles int, has_deadline_badge boolean)
language sql stable
set search_path = public, pg_temp
as $$
  with undo as (
    select a.id, a.status
    from badge_awards a
    where a.student_id = p_student and a.id = any (p_undo_awards)
  ),
  ledger as (
    select l.student_id, l.amount, l.effective_at
    from miles_ledger l
    where not exists (
      select 1 from undo u
      where u.id = l.source_id
        and l.reason = case when u.status = 'active' then 'badge_bonus' else 'badge_revoked' end)
  ),
  held as (
    -- Awards that count: the active ones, flipped for the undone ones.
    select a.student_id, a.awarded_at, b.sequence
    from badge_awards a
    join badges b on b.id = a.badge_id
    left join undo u on u.id = a.id
    where (a.status = 'active') <> (u.id is not null)
  ),
  miles as (
    select student_id, sum(amount)::int as total_miles, max(effective_at) as last_milestone_at
    from ledger
    group by student_id
  ),
  best_badge as (
    select student_id, max(sequence) as best_sequence
    from held
    group by student_id
  ),
  depth as (
    select student_id, sum(best_cleared_level)::int as skill_depth
    from skill_progress
    group by student_id
  ),
  board as (
    select s.id as student_id,
           case when s.id = p_student then coalesce(p_listed, false)
                else s.is_registered_approved and s.conduct_ok end as listed,
           coalesce(m.total_miles, 0)    as total_miles,
           coalesce(bb.best_sequence, 0) as best_sequence,
           coalesce(d.skill_depth, 0)    as skill_depth,
           m.last_milestone_at
    from students s
    left join miles m       on m.student_id = s.id
    left join best_badge bb on bb.student_id = s.id
    left join depth d       on d.student_id = s.id
  ),
  ranked as (
    select b.*,
           rank() over (partition by b.listed, b.best_sequence > 0
                        order by b.total_miles desc, b.best_sequence desc, b.skill_depth desc,
                                 b.last_milestone_at asc nulls last)::int as list_rank
    from board b
  )
  select case when r.listed then case when r.best_sequence > 0 then 'Qualiflyers' else 'Pre-Qualiflyers' end end,
         case when r.listed then r.list_rank end,
         r.total_miles,
         exists (select 1 from held h cross join program_settings ps
                 where h.student_id = p_student and ist_date(h.awarded_at) <= ps.badge_deadline)
  from ranked r
  where r.student_id = p_student
$$;
comment on function _standing(uuid, uuid[], boolean) is
  'Internal. A student''s list, rank within it, Miles and deadline badge, with the latest change of the given awards undone.';

-- -----------------------------------------------------------------------------
-- 3. Student reads (the student themselves, or an admin)
-- -----------------------------------------------------------------------------
create function student_overview(p_student uuid, p_actor_role text, p_actor_id text)
returns table (
  student_id uuid, name text, primary_track text,
  total_miles int, list text, list_rank int,
  attendance_pct numeric, min_attendance_pct numeric, attendance_ok boolean,
  registered_ok boolean, conduct_ok boolean,
  badge_deadline date, badge_by_deadline boolean
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_self_or_admin(p_actor_role, p_actor_id, 'student', p_student);
  return query
    select s.id, s.name, s.primary_track::text,
           (select coalesce(sum(l.amount), 0)::int from miles_ledger l where l.student_id = s.id),
           lb.list, lb.list_rank,
           s.attendance_pct, ps.min_attendance_pct, s.attendance_pct >= ps.min_attendance_pct,
           s.is_registered_approved, s.conduct_ok,
           ps.badge_deadline,
           exists (select 1 from badge_awards a
                   where a.student_id = s.id and a.status = 'active'
                     and ist_date(a.awarded_at) <= ps.badge_deadline)
    from students s
    cross join program_settings ps
    left join leaderboard_lists lb on lb.student_id = s.id
    where s.id = p_student;
end;
$$;
comment on function student_overview(uuid, text, text) is
  'Student or admin. Miles, leaderboard list and rank, and the trip checklist facts (attendance, registration, conduct, a badge by the deadline). The final interview round is not tracked yet; the app always shows it as pending.';

create function student_passbook(p_student uuid, p_actor_role text, p_actor_id text)
returns table (
  entry_id uuid, seq int, effective_at timestamptz, amount int, balance int, reason text,
  skill_name text, skill_level int, medal text, badge_track text, badge_level text, note text
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_self_or_admin(p_actor_role, p_actor_id, 'student', p_student);
  return query
    with entries as (
      select l.id, l.effective_at, l.amount, l.reason, l.source_id, l.note,
             row_number() over w::int as n,
             (sum(l.amount) over (w rows unbounded preceding))::int as running
      from miles_ledger l
      where l.student_id = p_student
      window w as (order by l.effective_at, l.created_at, l.id)
    )
    select e.id, e.n, e.effective_at, e.amount, e.running, e.reason,
           sk.name, sr.level, sr.medal, b.track::text, b.level,
           -- Revocation notes name the cause; the app labels rows itself instead.
           case when e.reason = 'bonus_milestone' then e.note end
    from entries e
    left join skill_results sr on e.reason in ('skill_medal', 'medal_upgrade') and sr.id = e.source_id
    left join skills sk        on sk.id = sr.skill_id
    left join badge_awards a   on e.reason in ('badge_bonus', 'badge_revoked') and a.id = e.source_id
    left join badges b         on b.id = a.badge_id
    order by e.n desc;
end;
$$;
comment on function student_passbook(uuid, text, text) is
  'Student or admin. Every Miles row, newest first, with a running balance (seq 1 = oldest) and what it was for.';

create function student_requirements(p_student uuid, p_actor_role text, p_actor_id text)
returns table (
  badge_id uuid, track text, level text, sequence int, skill_name text, required_level int,
  best_cleared_level int, best_attempted_level int, is_cleared boolean
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_self_or_admin(p_actor_role, p_actor_id, 'student', p_student);
  return query
    select b.id, b.track::text, b.level, b.sequence, sk.name, r.required_level,
           sp.best_cleared_level, sp.best_attempted_level,
           coalesce(sp.best_cleared_level >= r.required_level, false)
    from badges b
    join badge_requirements r on r.badge_id = b.id
    join skills sk            on sk.id = r.skill_id
    left join skill_progress sp on sp.student_id = p_student and sp.skill_id = r.skill_id
    where not b.is_locked
      and exists (select 1 from students s where s.id = p_student)
    order by b.track, b.sequence, sk.name;
end;
$$;
comment on function student_requirements(uuid, text, text) is
  'Student or admin. For every open badge: each required skill level and whether the student has cleared it.';

create function student_projects(p_student uuid, p_actor_role text, p_actor_id text)
returns table (
  badge_id uuid, track text, level text, submission_id uuid, link text, status text,
  submitted_at timestamptz, reviewed_at timestamptz, review_note text
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_self_or_admin(p_actor_role, p_actor_id, 'student', p_student);
  return query
    select distinct on (b.track, b.sequence)
           b.id, b.track::text, b.level, p.id, p.link, p.status, p.submitted_at, p.reviewed_at, p.review_note
    from badges b
    left join project_submissions p on p.badge_id = b.id and p.student_id = p_student
    where b.needs_project and not b.is_locked
    order by b.track, b.sequence, p.submitted_at desc nulls last;
end;
$$;
comment on function student_projects(uuid, text, text) is
  'Student or admin. The latest project submission (if any) for every open badge that needs a project.';

create function student_bookings(p_student uuid, p_actor_role text, p_actor_id text)
returns table (
  booking_id uuid, badge_id uuid, track text, level text, slot_id uuid,
  starts_at timestamptz, ends_at timestamptz, interviewer_name text
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_self_or_admin(p_actor_role, p_actor_id, 'student', p_student);
  return query
    select bo.id, b.id, b.track::text, b.level, sl.id, sl.starts_at, sl.ends_at, i.name
    from bookings bo
    join badges b       on b.id = bo.badge_id
    join slots sl       on sl.id = bo.slot_id
    join interviewers i on i.id = sl.interviewer_id
    where bo.student_id = p_student and bo.status = 'active'
    order by sl.starts_at;
end;
$$;
comment on function student_bookings(uuid, text, text) is
  'Student or admin. Active bookings with their ids, so the app can cancel or reschedule them.';

-- Facts behind the student's messages: every interview result, and every
-- badge removal (a cascade, removed in the same moment, is one event).
create function student_timeline(p_student uuid, p_actor_role text, p_actor_id text)
returns table (
  kind text, happened_at timestamptz, track text, levels text[],
  outcome text, feedback text, retake_after date, interview_held_at timestamptz,
  corrected boolean, correction_reason text, bonus_miles int,
  cause text, miles_change int
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_self_or_admin(p_actor_role, p_actor_id, 'student', p_student);
  return query
    with removed as (
      select a.revoked_at, b.track, b.sequence, b.level, a.revoke_cause,
             (select l.amount from miles_ledger l
              where l.reason = 'badge_revoked' and l.source_id = a.id) as amount
      from badge_awards a
      join badges b on b.id = a.badge_id
      where a.student_id = p_student and a.status = 'revoked'
    ),
    events as (
      select 'result'::text as kind, coalesce(r.corrected_at, r.recorded_at) as happened_at,
             b.track::text as track, array[b.level] as levels,
             r.outcome, r.feedback, r.retake_after, r.interview_held_at,
             r.corrected_at is not null as corrected, r.correction_reason, b.bonus_miles,
             null::text as cause, null::int as miles_change
      from interview_results r
      join badges b on b.id = r.badge_id
      where r.student_id = p_student
      union all
      select 'badge_removed', rm.revoked_at, rm.track::text,
             array_agg(rm.level order by rm.sequence),
             null, null, null, null, null, null, null,
             -- The lowest badge carries the root cause; the rest say "prerequisite_revoked".
             (array_agg(rm.revoke_cause order by rm.sequence))[1],
             sum(rm.amount)::int
      from removed rm
      group by rm.revoked_at, rm.track
    )
    select * from events ev
    order by ev.happened_at desc, ev.kind;
end;
$$;
comment on function student_timeline(uuid, text, text) is
  'Student or admin. Interview results (with feedback and retake date) and badge removals (cascades grouped), newest first. The app turns these into messages.';

-- "What changed": the student's latest badge change (earned or removed) and
-- their standing with and without it, on today's leaderboard. Comparing
-- against today (not against a stored snapshot) needs no extra tables and
-- isolates exactly what this change did.
create function student_last_change(p_student uuid, p_actor_role text, p_actor_id text)
returns table (
  change text, happened_at timestamptz, track text, levels text[], cause text,
  miles_before int, miles_after int,
  list_before text, rank_before int, list_after text, rank_after int,
  deadline_badge_before boolean, deadline_badge_after boolean
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_student       students;
  v_at            timestamptz;
  v_change        text;
  v_awards        uuid[];
  v_track         text;
  v_levels        text[];
  v_cause         text;
  v_listed_before boolean;
  v_before        record;
  v_after         record;
begin
  perform _require_self_or_admin(p_actor_role, p_actor_id, 'student', p_student);
  select * into v_student from students where id = p_student;
  if not found then return; end if;

  -- The latest badge event. A removal wins a tie with an earning at the same
  -- moment: both can happen in one transaction, and a removal always comes after.
  select e.happened_at, e.change into v_at, v_change
  from (select a.created_at as happened_at, 'badge_earned' as change
        from badge_awards a where a.student_id = p_student
        union all
        select a.revoked_at, 'badge_removed'
        from badge_awards a where a.student_id = p_student and a.status = 'revoked') e
  order by e.happened_at desc, (e.change = 'badge_removed') desc
  limit 1;
  if v_at is null then return; end if;

  -- Every award that changed in that moment (a cascade removes several).
  select array_agg(a.id order by b.sequence), array_agg(b.level order by b.sequence),
         min(b.track), (array_agg(a.revoke_cause order by b.sequence))[1]
    into v_awards, v_levels, v_track, v_cause
  from badge_awards a
  join badges b on b.id = a.badge_id
  where a.student_id = p_student
    and case when v_change = 'badge_earned' then a.status = 'active' and a.created_at = v_at
             else a.status = 'revoked' and a.revoked_at = v_at end;

  -- Was the student on the leaderboard just before? A confirmed conduct case
  -- clears conduct_ok in the same transaction as the removal, so audit_log
  -- holds the earlier value; otherwise nothing else changed it.
  v_listed_before := v_student.is_registered_approved and coalesce(
    (select (al.before ->> 'conduct_ok')::boolean
     from audit_log al
     where al.table_name = 'students' and al.record_id = p_student::text and al.action = 'UPDATE'
       and al.created_at = v_at
       and (al.before ->> 'conduct_ok') is distinct from (al.after ->> 'conduct_ok')
     order by al.id
     limit 1),
    v_student.conduct_ok);

  select * into v_before from _standing(p_student, v_awards, v_listed_before);
  select * into v_after  from _standing(p_student, '{}', v_student.is_registered_approved and v_student.conduct_ok);

  return query
    select v_change, v_at, v_track, v_levels,
           case when v_change = 'badge_removed' then v_cause end,
           v_before.total_miles, v_after.total_miles,
           v_before.list, v_before.list_rank, v_after.list, v_after.list_rank,
           v_before.has_deadline_badge, v_after.has_deadline_badge;
end;
$$;
comment on function student_last_change(uuid, text, text) is
  'Student or admin. The latest badge earned or removed, with Miles, list + rank and the deadline-badge condition before and after it.';

-- -----------------------------------------------------------------------------
-- 4. Interviewer reads (the interviewer themselves, or an admin)
-- -----------------------------------------------------------------------------
create function interviewer_slots(p_interviewer uuid, p_actor_role text, p_actor_id text)
returns table (
  slot_id uuid, starts_at timestamptz, ends_at timestamptz, ist_day date, status text, withdraw_reason text,
  booking_id uuid, booking_status text, student_name text, track text, level text
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_self_or_admin(p_actor_role, p_actor_id, 'interviewer', p_interviewer);
  return query
    select sl.id, sl.starts_at, sl.ends_at, ist_date(sl.starts_at), sl.status, sl.withdraw_reason,
           bo.id, bo.status, st.name, b.track::text, b.level
    from slots sl
    left join bookings bo on bo.slot_id = sl.id and bo.status in ('active', 'completed')
    left join students st on st.id = bo.student_id
    left join badges b    on b.id = bo.badge_id
    where sl.interviewer_id = p_interviewer
      and sl.starts_at >= ist_today()::timestamp at time zone 'Asia/Kolkata'
    order by sl.starts_at;
end;
$$;
comment on function interviewer_slots(uuid, text, text) is
  'Interviewer or admin. The interviewer''s slots from today (IST) on: open, booked or withdrawn.';

create function interviewer_results(p_interviewer uuid, p_actor_role text, p_actor_id text)
returns table (
  result_id uuid, booking_id uuid, student_name text, track text, level text, outcome text,
  feedback text, retake_after date, interview_held_at timestamptz, recorded_at timestamptz,
  corrected_at timestamptz, correction_reason text, can_correct_today boolean
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_self_or_admin(p_actor_role, p_actor_id, 'interviewer', p_interviewer);
  return query
    select r.id, r.booking_id, st.name, b.track::text, b.level, r.outcome,
           r.feedback, r.retake_after, r.interview_held_at, r.recorded_at,
           r.corrected_at, r.correction_reason,
           ist_date(r.recorded_at) = ist_today()
    from interview_results r
    join students st on st.id = r.student_id
    join badges b    on b.id = r.badge_id
    where r.recorded_by = p_interviewer
    order by r.recorded_at desc
    limit 100;
end;
$$;
comment on function interviewer_results(uuid, text, text) is
  'Interviewer or admin. Results the interviewer recorded, newest first; can_correct_today mirrors correct_result''s same-day rule.';

create function project_review_queue(p_actor_role text, p_actor_id text)
returns table (
  submission_id uuid, student_id uuid, student_name text, track text, level text,
  link text, submitted_at timestamptz
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_role(p_actor_role, 'interviewer', 'admin');
  return query
    select p.id, st.id, st.name, b.track::text, b.level, p.link, p.submitted_at
    from project_submissions p
    join students st on st.id = p.student_id
    join badges b    on b.id = p.badge_id
    where p.status = 'submitted'
    order by p.submitted_at;
end;
$$;
comment on function project_review_queue(text, text) is
  'Interviewer or admin. Robotics project submissions waiting for review, oldest first.';

-- -----------------------------------------------------------------------------
-- 5. Admin reads
-- -----------------------------------------------------------------------------
create function admin_active_awards(p_actor_role text, p_actor_id text)
returns table (
  award_id uuid, student_id uuid, student_name text, track text, level text,
  awarded_at timestamptz, has_open_case boolean
)
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform _require_role(p_actor_role, 'admin');
  return query
    select a.id, st.id, st.name, b.track::text, b.level, a.awarded_at,
           exists (select 1 from malpractice_cases c where c.badge_award_id = a.id and c.status = 'open')
    from badge_awards a
    join students st on st.id = a.student_id
    join badges b    on b.id = a.badge_id
    where a.status = 'active'
    order by st.name, b.track, b.sequence;
end;
$$;
comment on function admin_active_awards(text, text) is
  'Admin only. Every active badge, for flagging a malpractice case.';

-- -----------------------------------------------------------------------------
-- 6. Grants: start from zero for everything above, then open what the app uses.
-- -----------------------------------------------------------------------------
revoke all on student_directory, leaderboard_lists from anon, authenticated;
grant select on student_directory, leaderboard_lists to anon, authenticated;

revoke all on function
  _require_self_or_admin(text, text, text, uuid),
  _standing(uuid, uuid[], boolean),
  student_overview(uuid, text, text),
  student_passbook(uuid, text, text),
  student_requirements(uuid, text, text),
  student_projects(uuid, text, text),
  student_bookings(uuid, text, text),
  student_timeline(uuid, text, text),
  student_last_change(uuid, text, text),
  interviewer_slots(uuid, text, text),
  interviewer_results(uuid, text, text),
  project_review_queue(text, text),
  admin_active_awards(text, text)
from public, anon, authenticated;

grant execute on function
  student_overview(uuid, text, text),
  student_passbook(uuid, text, text),
  student_requirements(uuid, text, text),
  student_projects(uuid, text, text),
  student_bookings(uuid, text, text),
  student_timeline(uuid, text, text),
  student_last_change(uuid, text, text),
  interviewer_slots(uuid, text, text),
  interviewer_results(uuid, text, text),
  project_review_queue(text, text),
  admin_active_awards(text, text)
to anon, authenticated;

-- Tell the Supabase API (PostgREST) to pick up the new objects right away.
notify pgrst, 'reload schema';

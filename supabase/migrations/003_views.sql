-- =============================================================================
-- GRIT Layover - 003_views.sql
-- Derived state (principle 5: journey state is computed here, never stored).
--
-- These views run with their owner's rights (the Postgres default, i.e. NOT
-- security_invoker). That is deliberate: anon/authenticated can read the
-- views but not the underlying tables (see 004). Supabase's linter flags this
-- pattern ("security definer view"); here it is the intended access path.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- skill_progress (internal, not granted): best cleared level per student+skill.
-- Shared by student_journey (requirements) and leaderboard (skill depth).
-- Must never reference malpractice_cases, because leaderboard depends on it.
-- -----------------------------------------------------------------------------
create view skill_progress as
select student_id,
       skill_id,
       max(level) filter (where medal in ('gold', 'silver')) as best_cleared_level,
       max(level)                                            as best_attempted_level
from skill_results
group by student_id, skill_id;
comment on view skill_progress is 'Internal. Highest cleared (gold/silver) and attempted level per student and skill.';

-- -----------------------------------------------------------------------------
-- available_slots: what the booking screen lists.
-- -----------------------------------------------------------------------------
create view available_slots as
select s.id as slot_id,
       s.interviewer_id,
       i.name as interviewer_name,
       s.starts_at,
       s.ends_at,
       ist_date(s.starts_at) as ist_day
from slots s
join interviewers i on i.id = s.interviewer_id
cross join program_settings ps
where s.status = 'open'
  and i.is_active
  and s.starts_at >= now() + make_interval(hours => ps.min_booking_notice_hours)
  and not exists (select 1 from bookings b where b.slot_id = s.id and b.status in ('active', 'completed'))
order by s.starts_at, i.name;
comment on view available_slots is 'Open, unbooked slots of active interviewers that are still outside the booking notice window.';

-- -----------------------------------------------------------------------------
-- student_journey: one row per student x unlocked badge. First matching state wins.
-- -----------------------------------------------------------------------------
create view student_journey as
with facts as (
  select
    st.id   as student_id,
    st.name as student_name,
    st.primary_track,
    b.id    as badge_id,
    b.track,
    b.level,
    b.sequence,
    b.needs_project,
    student_ineligibility_reason(st) as ineligible_reason,
    st.conduct_ok,
    aw.status       as award_status,
    aw.revoke_cause as award_revoke_cause,
    aw.revoked_at   as award_revoked_at,
    exists (select 1 from malpractice_cases c
            where c.student_id = st.id and c.status = 'open') as has_open_case,
    (b.sequence = 1 or exists (
       select 1 from badge_awards pa join badges pb on pb.id = pa.badge_id
       where pa.student_id = st.id and pa.status = 'active'
         and pb.track = b.track and pb.sequence = b.sequence - 1)) as previous_badge_held,
    req.skills_cleared,
    req.skills_total,
    exists (select 1 from project_submissions p
            where p.student_id = st.id and p.badge_id = b.id and p.status = 'approved') as project_approved,
    bk.booking_id,
    bk.slot_starts_at,
    bk.interviewer_name,
    lr.outcome            as last_outcome,
    lr.retake_after       as last_retake_after,
    lr.interview_held_at  as last_held_at
  from students st
  cross join badges b
  -- Latest award for this badge (the active one if any).
  left join lateral (
    select a.status, a.revoke_cause, a.revoked_at
    from badge_awards a
    where a.student_id = st.id and a.badge_id = b.id
    order by (a.status = 'active') desc, a.created_at desc
    limit 1
  ) aw on true
  -- Requirement progress.
  left join lateral (
    select count(*) filter (where sp.best_cleared_level >= r.required_level)::int as skills_cleared,
           count(*)::int                                                         as skills_total
    from badge_requirements r
    left join skill_progress sp on sp.student_id = st.id and sp.skill_id = r.skill_id
    where r.badge_id = b.id
  ) req on true
  -- Active booking, if any.
  left join lateral (
    select bo.id as booking_id, sl.starts_at as slot_starts_at, i.name as interviewer_name
    from bookings bo
    join slots sl        on sl.id = bo.slot_id
    join interviewers i  on i.id = sl.interviewer_id
    where bo.student_id = st.id and bo.badge_id = b.id and bo.status = 'active'
  ) bk on true
  -- Latest interview result.
  left join lateral (
    select r.outcome, r.retake_after, r.interview_held_at
    from interview_results r
    where r.student_id = st.id and r.badge_id = b.id
    order by r.interview_held_at desc, r.recorded_at desc
    limit 1
  ) lr on true
  where not b.is_locked
),
states as (
  select f.*,
    case
      when f.award_status = 'active' and f.has_open_case                     then 'Under review'
      when f.award_status = 'active'                                          then 'Passed'
      -- 'Revoked' is the headline only while the revocation still blocks
      -- rebooking: a malpractice revoke (or its cascade) until an admin
      -- restores eligibility. A result_corrected revoke never blocks (the
      -- student can rebook any time), so the normal states apply. Once the
      -- student books or interviews again, that newer state takes over.
      when f.award_status = 'revoked'
       and f.award_revoke_cause <> 'result_corrected'
       and not f.conduct_ok
       and f.booking_id is null
       and (f.last_held_at is null or f.last_held_at <= f.award_revoked_at)  then 'Revoked'
      when f.ineligible_reason is not null                                    then 'Not eligible'
      when not f.previous_badge_held or f.skills_cleared < f.skills_total     then 'Not ready'
      when f.needs_project and not f.project_approved                         then 'Project pending'
      when f.booking_id is not null and f.slot_starts_at > now()              then 'Booked'
      when f.booking_id is not null                                           then 'Waiting for result'
      when f.last_outcome in ('fail', 'retake_later', 'no_show')
       and f.last_retake_after > ist_today()                                  then 'Retake later'
      else 'Ready to book'
    end as state
  from facts f
)
select
  student_id,
  student_name,
  primary_track,
  badge_id,
  track,
  level,
  sequence,
  state,
  case when state = 'Not eligible' then ineligible_reason end as not_eligible_reason,
  previous_badge_held,
  skills_cleared,
  skills_total,
  slot_starts_at,
  interviewer_name,
  case when state = 'Retake later' then last_retake_after end as retake_after,
  has_open_case as final_steps_on_hold
from states
order by student_name, track, sequence;
comment on view student_journey is 'Derived journey state per student and unlocked badge. Never stored, so it cannot drift from the facts.';

-- -----------------------------------------------------------------------------
-- leaderboard: GRIT official order. MUST NOT reference malpractice_cases
-- (directly or through another view): an open case must not change standings.
-- Terms: disqualification forfeits leaderboard standing, so students with
-- conduct_ok = false are left out until an admin restores eligibility.
-- -----------------------------------------------------------------------------
create view leaderboard as
with miles as (
  select student_id, sum(amount)::int as total_miles, max(effective_at) as last_milestone_at
  from miles_ledger
  group by student_id
),
best_badge as (
  select a.student_id, max(b.sequence) as best_sequence
  from badge_awards a join badges b on b.id = a.badge_id
  where a.status = 'active'
  group by a.student_id
),
depth as (
  select student_id, sum(best_cleared_level)::int as skill_depth
  from skill_progress
  group by student_id
)
select
  rank() over (order by coalesce(m.total_miles, 0) desc,
                        coalesce(bb.best_sequence, 0) desc,
                        coalesce(d.skill_depth, 0) desc,
                        m.last_milestone_at asc nulls last) as rank,
  s.name,
  s.batch,
  s.campus,
  s.section,
  (array['Novice', 'Specialist', 'Expert', 'Master', 'Grand Master'])[bb.best_sequence] as highest_badge,
  coalesce(m.total_miles, 0)  as total_miles,
  coalesce(d.skill_depth, 0)  as skill_depth,
  (bb.best_sequence is not null) as is_qualiflyer,
  s.id as student_id
from students s
left join miles m       on m.student_id = s.id
left join best_badge bb on bb.student_id = s.id
left join depth d       on d.student_id = s.id
where s.is_registered_approved
  and s.conduct_ok
order by rank, s.name;
comment on view leaderboard is 'Registered, approved, not disqualified students ranked by Miles, highest badge, skill depth, then who reached their total first.';

-- -----------------------------------------------------------------------------
-- admin_booking_status: every eligible student, their next badge in their track.
-- -----------------------------------------------------------------------------
create view admin_booking_status as
select
  s.id as student_id,
  s.name,
  s.batch,
  s.campus,
  s.section,
  s.primary_track,
  nb.level as next_badge,
  coalesce(nb.state, 'All open badges earned') as journey_state,
  coalesce(nb.state in ('Booked', 'Waiting for result'), false) as is_booked,
  nb.slot_starts_at,
  nb.interviewer_name
from students s
left join lateral (
  -- Lowest badge in the student's track that is not yet held.
  select j.level, j.state, j.slot_starts_at, j.interviewer_name
  from student_journey j
  where j.student_id = s.id and j.track = s.primary_track
    and j.state not in ('Passed', 'Under review')
  order by j.sequence
  limit 1
) nb on true
where student_ineligibility_reason(s) is null
order by is_booked, s.name;
comment on view admin_booking_status is 'Admin: each eligible student''s next badge in their primary track, its journey state, and whether it is booked.';

-- -----------------------------------------------------------------------------
-- admin_overdue_cases
-- -----------------------------------------------------------------------------
create view admin_overdue_cases as
select
  c.id as case_id,
  s.id as student_id,
  s.name as student_name,
  b.track,
  b.level,
  c.flagged_by,
  c.flagged_at,
  c.review_due_at,
  ist_today() - ist_date(c.review_due_at) as days_overdue,
  c.evidence
from malpractice_cases c
join students s     on s.id = c.student_id
join badge_awards a on a.id = c.badge_award_id
join badges b       on b.id = a.badge_id
where c.status = 'open' and c.review_due_at < now()
order by c.review_due_at;
comment on view admin_overdue_cases is 'Admin: open malpractice cases past their review deadline.';

-- -----------------------------------------------------------------------------
-- admin_at_risk: not yet qualified and nothing booked.
-- -----------------------------------------------------------------------------
create view admin_at_risk as
select
  s.id as student_id,
  s.name,
  s.batch,
  s.campus,
  s.section,
  s.primary_track,
  student_ineligibility_reason(s) as not_eligible_reason,
  ps.badge_deadline,
  ps.badge_deadline - ist_today() as days_left
from students s
cross join program_settings ps
where s.is_registered_approved
  and not exists (select 1 from badge_awards a where a.student_id = s.id and a.status = 'active')
  and not exists (select 1 from bookings b where b.student_id = s.id and b.status = 'active')
order by days_left, s.name;
comment on view admin_at_risk is 'Admin: registered students with no active badge and no active booking, with days left to the badge deadline.';

-- -----------------------------------------------------------------------------
-- interviewer_schedule. MUST NOT reference malpractice_cases: interviewers
-- should judge every interview without knowing about open cases.
-- -----------------------------------------------------------------------------
create view interviewer_schedule as
select
  i.id   as interviewer_id,
  i.name as interviewer_name,
  ist_date(sl.starts_at) as ist_day,
  count(*) over (partition by i.id, ist_date(sl.starts_at)) as bookings_that_day,
  sl.id  as slot_id,
  sl.starts_at,
  sl.ends_at,
  bo.id  as booking_id,
  bo.status as booking_status,
  st.id  as student_id,
  st.name as student_name,
  b.track,
  b.level,
  r.id as result_id,
  r.outcome
from bookings bo
join slots sl         on sl.id = bo.slot_id
join interviewers i   on i.id = sl.interviewer_id
join students st      on st.id = bo.student_id
join badges b         on b.id = bo.badge_id
left join interview_results r on r.booking_id = bo.id
where bo.status in ('active', 'completed')
order by i.name, sl.starts_at;
comment on view interviewer_schedule is 'Interviewer: their active and completed bookings by IST day, with any recorded outcome.';

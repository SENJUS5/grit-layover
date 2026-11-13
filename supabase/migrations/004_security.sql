-- =============================================================================
-- GRIT Layover - 004_security.sql
-- Grants and Row Level Security.
--
-- PROTOTYPE MODEL: there is no login yet. The app has a role switcher and
-- passes p_actor_role / p_actor_id to the functions. The functions enforce
-- what each role may do, but they cannot verify WHO the caller is: anyone
-- holding the anon key can claim to be an admin.
--
-- PRODUCTION: use Supabase Auth. Derive the actor from auth.uid() and a
-- role claim inside the functions (drop the p_actor_* parameters), and add
-- per-role RLS policies (a student reads only their own rows, an interviewer
-- only their own slots, admins everything).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Start from zero. Supabase grants ALL on new public tables to anon and
--    authenticated by default, and Postgres grants EXECUTE on every new
--    function to PUBLIC. Remove both so only the grants below apply.
-- -----------------------------------------------------------------------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. RLS on every table. With no policy, a role sees zero rows even if granted.
-- -----------------------------------------------------------------------------
alter table program_settings    enable row level security;
alter table students            enable row level security;
alter table interviewers        enable row level security;
alter table skills              enable row level security;
alter table badges              enable row level security;
alter table badge_requirements  enable row level security;
alter table skill_results       enable row level security;
alter table slots               enable row level security;
alter table bookings            enable row level security;
alter table interview_results   enable row level security;
alter table project_submissions enable row level security;
alter table badge_awards        enable row level security;
alter table miles_ledger        enable row level security;
alter table malpractice_cases   enable row level security;
alter table audit_log           enable row level security;

-- -----------------------------------------------------------------------------
-- 3. Reference tables: read-only for everyone.
--    malpractice_cases and audit_log get no grant and no policy at all; admins
--    read them through admin_list_cases() / admin_audit_log().
--    Student-level data (results, bookings, ledger) is read through the views.
-- -----------------------------------------------------------------------------
grant select on program_settings, interviewers, skills, badges, badge_requirements, slots
  to anon, authenticated;

create policy program_settings_read   on program_settings   for select to anon, authenticated using (true);
create policy interviewers_read       on interviewers       for select to anon, authenticated using (true);
create policy skills_read             on skills             for select to anon, authenticated using (true);
create policy badges_read             on badges             for select to anon, authenticated using (true);
create policy badge_requirements_read on badge_requirements for select to anon, authenticated using (true);
create policy slots_read              on slots              for select to anon, authenticated using (true);

-- -----------------------------------------------------------------------------
-- 4. Views. They run with the owner's rights, so they can read the locked
--    tables (see the note in 003). skill_progress is internal: not granted.
-- -----------------------------------------------------------------------------
grant select on student_journey, leaderboard, available_slots, interviewer_schedule,
                admin_booking_status, admin_overdue_cases, admin_at_risk
  to anon, authenticated;

-- Functions called inside views are checked against the caller, so the
-- read-only helpers the views use must be executable.
grant execute on function ist_date(timestamptz), ist_today(), format_ist(timestamptz),
                          student_ineligibility_reason(students)
  to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5. Writes: no INSERT/UPDATE/DELETE on any table. All changes go through these.
--    Internal functions (_create_booking, _grant_award, _revoke_award, ...)
--    are intentionally NOT granted.
-- -----------------------------------------------------------------------------
grant execute on function
  record_skill_result(uuid, uuid, int, text, int, text, text, timestamptz),
  create_slot(uuid, timestamptz, text, text),
  book_slot(uuid, uuid, uuid, text, text),
  cancel_booking(uuid, text, text, text),
  reschedule_booking(uuid, uuid, text, text),
  withdraw_slot(uuid, uuid, text, text, text),
  record_result(uuid, uuid, text, text, text, text, date, timestamptz),
  correct_result(uuid, text, text, text, text, date),
  flag_malpractice(uuid, text, text, text),
  decide_case(uuid, text, text, text, text),
  restore_eligibility(uuid, text, text, text),
  submit_project(uuid, uuid, text, text, text),
  review_project(uuid, text, text, text, text),
  admin_list_cases(text, text),
  admin_audit_log(text, text, text, text, int)
to anon, authenticated;

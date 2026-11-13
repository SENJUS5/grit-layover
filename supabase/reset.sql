-- =============================================================================
-- GRIT Layover - reset.sql
-- DESTROYS ALL GRIT DATA. Drops every object created by 001-005 so the
-- migrations and seed can be run again from scratch.
--
-- Dropping tables is the only way to clear the insert-only tables: their
-- guard triggers block UPDATE, DELETE and TRUNCATE by design.
-- Extensions (pgcrypto, btree_gist) are left in place.
-- =============================================================================

begin;

-- Tables (CASCADE also drops every view, including 005's, and the functions that
-- take a table row type).
drop table if exists
  audit_log, malpractice_cases, miles_ledger, badge_awards, project_submissions,
  interview_results, bookings, slots, skill_results, badge_requirements, badges,
  skills, interviewers, students, program_settings
  cascade;

-- Functions, by name only, so unrelated functions in the project are untouched.
do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (array[
        'ist_date', 'ist_today', 'format_ist', 'student_ineligibility_reason',
        '_set_actor', '_restore_actor', '_require_role', '_forbid_update_delete', '_forbid_delete',
        '_touch_updated_at', '_check_level_within_skill', '_credit_skill_miles',
        '_set_case_review_due', '_audit_row', '_create_booking', '_cancel_booking',
        '_grant_award', '_revoke_award', '_retake_date',
        'record_skill_result', 'create_slot', 'book_slot', 'cancel_booking',
        'reschedule_booking', 'withdraw_slot', 'record_result', 'correct_result',
        'flag_malpractice', 'decide_case', 'restore_eligibility', 'submit_project', 'review_project',
        'admin_list_cases', 'admin_audit_log',
        -- 005_app_reads.sql
        '_require_self_or_admin', '_standing', 'student_overview', 'student_passbook',
        'student_requirements', 'student_projects', 'student_bookings', 'student_timeline',
        'student_last_change', 'interviewer_slots', 'interviewer_results',
        'project_review_queue', 'admin_active_awards'])
  loop
    execute format('drop function %s cascade', f);
  end loop;
end;
$$;

drop domain if exists grit_track cascade;
drop domain if exists actor_role cascade;

commit;

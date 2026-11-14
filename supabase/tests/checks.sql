-- =============================================================================
-- GRIT Layover - tests/checks.sql
-- Proves the rules hold. Run AFTER 001-005 and seed.sql.
--
-- How the rollback works:
--   All checks run inside one plpgsql block (a transaction / subtransaction).
--   The block ends by raising a sentinel error, which ROLLS BACK every change
--   the checks made. Results are copied into a variable first, so they survive
--   and are returned as a PASS/FAIL table.
--   This is done instead of BEGIN ... ROLLBACK because the Supabase SQL Editor
--   only displays the last statement's result and does not show RAISE NOTICE
--   output. Here the last statement IS the result grid. (In psql the NOTICE
--   lines are printed too.)
--
-- Limits, stated honestly:
--   * Check 1 runs two book_slot calls one after the other in one session. It
--     proves the guards exist; true concurrency is covered by the slot row lock
--     and the partial unique index, which a single script cannot race.
--   * Check 12 backdates recorded_at by one day, because now() cannot be moved
--     inside a transaction.
--   * Check 34 sends the same correction twice, one after the other. Two calls
--     arriving at the same moment are serialised by correct_result's row lock
--     (select ... for update), so the second still sees the first's outcome.
-- =============================================================================

create temp table if not exists grit_check_results (
  check_no int, check_name text, result text, detail text
);
truncate grit_check_results;

-- ---------------------------------------------------------------- helpers ----
create or replace function pg_temp.report(p_no int, p_name text, p_passed boolean, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into grit_check_results
  values (p_no, p_name, case when p_passed then 'PASS' else 'FAIL' end, p_detail);
  raise notice '% check %: % %', case when p_passed then 'PASS' else 'FAIL' end, p_no, p_name,
               coalesce('(' || p_detail || ')', '');
end;
$$;

-- Runs p_sql and expects it to fail with an error matching p_pattern.
-- Returns 'OK: <error>' on the expected failure, anything else otherwise.
-- If the statement unexpectedly SUCCEEDS, its effects are undone too, so one
-- broken rule cannot contaminate the checks that run after it.
create or replace function pg_temp.expect_error(p_sql text, p_pattern text)
returns text language plpgsql as $$
begin
  execute p_sql;
  raise exception 'expect_error: no error';
exception when others then
  if sqlerrm = 'expect_error: no error' then return 'NO ERROR: statement succeeded (effects undone)'; end if;
  if sqlerrm ~* p_pattern then return 'OK: ' || sqlerrm; end if;
  return 'WRONG ERROR: ' || sqlerrm;
end;
$$;

create or replace function pg_temp.sid(p_name text) returns uuid language sql stable as
  $$ select id from students where name = p_name $$;
create or replace function pg_temp.iid(p_name text) returns uuid language sql stable as
  $$ select id from interviewers where name = p_name $$;
create or replace function pg_temp.bid(p_track text, p_level text) returns uuid language sql stable as
  $$ select id from badges where track = p_track and level = p_level $$;
create or replace function pg_temp.miles(p_student uuid) returns int language sql stable as
  $$ select coalesce(sum(amount), 0)::int from miles_ledger where student_id = p_student $$;

-- Clears the AI Product Specialist skills for a student (contest-system path).
create or replace function pg_temp.give_specialist_skills(p_student uuid) returns void language plpgsql as $$
begin
  perform record_skill_result(p_student, (select id from skills where name = 'Computational Thinking'), 2, 'gold', 80, 'system', 'checks');
  perform record_skill_result(p_student, (select id from skills where name = 'Applied Gen AI Development'), 2, 'gold', 80, 'system', 'checks');
  perform record_skill_result(p_student, (select id from skills where name = 'Server-Side Engineering'), 1, 'gold', 10, 'system', 'checks');
  perform record_skill_result(p_student, (select id from skills where name = 'SQL'), 1, 'gold', 10, 'system', 'checks');
end;
$$;

-- A past slot + booking inserted directly (as the seed does), owned by p_interviewer.
create or replace function pg_temp.past_booking(p_student uuid, p_badge uuid, p_interviewer uuid, p_starts_at timestamptz)
returns uuid language plpgsql as $$
declare v_slot uuid; v_booking uuid;
begin
  insert into slots (interviewer_id, starts_at, ends_at)
  values (p_interviewer, p_starts_at, p_starts_at + interval '30 minutes') returning id into v_slot;
  insert into bookings (student_id, badge_id, slot_id) values (p_student, p_badge, v_slot) returning id into v_booking;
  return v_booking;
end;
$$;

-- ----------------------------------------------------------------- checks ----
create or replace function pg_temp.grit_checks()
returns table (check_no int, check_name text, result text, detail text)
language plpgsql as $$
declare
  v_out        jsonb;
  v_r          text;
  v_r2         text;
  v_ok         boolean;
  v_n          int;
  v_id         uuid;
  v_free       uuid[];
  v_tester     uuid;   -- a private interviewer, so test slots never collide with seeded ones
  v_priya      uuid := pg_temp.sid('Priya Sharma');
  v_arjun      uuid := pg_temp.sid('Arjun Reddy');
  v_kavya      uuid := pg_temp.sid('Kavya Nair');
  v_vikram     uuid := pg_temp.sid('Vikram Singh');
  v_aditya     uuid := pg_temp.sid('Aditya Kulkarni');
  v_sneha      uuid := pg_temp.sid('Sneha Iyer');
  v_novice     uuid := pg_temp.bid('AI Product Mastery', 'Novice');
  v_specialist uuid := pg_temp.bid('AI Product Mastery', 'Specialist');
  v_ananya     uuid := pg_temp.iid('Ananya Rao');
  v_rahul      uuid := pg_temp.sid('Rahul Verma');
  v_karthik    uuid := pg_temp.iid('Karthik Menon');
  v_snap       jsonb;  -- seed-state facts for checks 31 and 33
  v_before     jsonb;
  v_after      jsonb;
  v_booking    uuid;
  v_result     uuid;
  v_award      uuid;
  v_award2     uuid;
  v_case       uuid;
  v_deadline   date;
  v_probe      uuid;
begin
  if v_priya is null then
    raise exception 'Seed data not found. Run supabase/seed.sql before the checks.';
  end if;

  begin  -- everything in here is rolled back at the end
    -- Keep the suite independent of the calendar: if the real badge deadline
    -- has passed, pretend it has not (check 23 simulates it explicitly).
    update program_settings set badge_deadline = ist_today() + 30 where id = 1 and badge_deadline < ist_today();
    select array_agg(slot_id order by starts_at, slot_id) into v_free from available_slots;
    insert into interviewers (name, email) values ('Check Interviewer', 'checks@grit.example')
      returning id into v_tester;

    -- ===== Seed-state checks first (later checks change these students) =====

    -- 13. Every demo student shows the journey state the seed promises.
    select string_agg(format('%s: expected %s, got %s', e.name, e.state, coalesce(j.state, 'none')), '; ')
      into v_r
    from (values ('Priya Sharma', 'AI Product Mastery', 'Ready to book'),
                 ('Arjun Reddy', 'AI Product Mastery', 'Not ready'),
                 ('Sneha Iyer', 'AI Product Mastery', 'Booked'),
                 ('Rahul Verma', 'AI Product Mastery', 'Waiting for result'),
                 ('Kavya Nair', 'AI Product Mastery', 'Retake later'),
                 ('Vikram Singh', 'AI Product Mastery', 'Passed'),
                 ('Meera Joshi', 'AI Product Mastery', 'Not eligible'),
                 ('Aditya Kulkarni', 'AI Product Mastery', 'Under review'),
                 ('Rohan Das', 'AI Robotics Mastery', 'Project pending'),
                 ('Ishita Gupta', 'AI Product Mastery', 'Revoked')) as e(name, track, state)
    left join student_journey j on j.student_name = e.name and j.track = e.track and j.level = 'Novice'
    where j.state is distinct from e.state;
    perform pg_temp.report(13, 'Seeded students show their intended journey states', v_r is null, v_r);

    -- 14. Medal upgrade: Kavya CT L1 try_again then silver -> +5 then +13 (= 18).
    select string_agg(format('%s %s', amount, reason), ', ' order by effective_at) into v_r
    from miles_ledger
    where student_id = v_kavya and reason in ('skill_medal', 'medal_upgrade') and note like 'Computational Thinking L1%';
    perform pg_temp.report(14, 'Medal upgrade credits only the difference (+5, +13)',
                           v_r = '5 skill_medal, 13 medal_upgrade', v_r);

    -- 15. Open case: Aditya still ranks normally; journey flags final steps on hold.
    select count(*) into v_n from leaderboard l
    where l.student_id = v_aditya and l.is_qualiflyer and l.total_miles = 250;
    select bool_and(final_steps_on_hold) into v_ok from student_journey where student_id = v_aditya;
    perform pg_temp.report(15, 'Student with open case stays on leaderboard, final steps on hold',
                           v_n = 1 and v_ok, format('leaderboard rows=%s, on_hold=%s', v_n, v_ok));

    -- 16. Ishita's cascade from the seed: Novice and Specialist revoked, Miles = skill Miles only.
    select count(*) into v_n from badge_awards where student_id = pg_temp.sid('Ishita Gupta') and status = 'revoked';
    select string_agg(amount::text, ',' order by amount) into v_r
    from miles_ledger where student_id = pg_temp.sid('Ishita Gupta') and reason = 'badge_revoked';
    perform pg_temp.report(16, 'Seeded malpractice cascade revoked both badges (-250, -150)',
                           v_n = 2 and v_r = '-250,-150', format('revoked=%s, debits=%s', v_n, v_r));

    -- 29. GRIT ranks each list on its own: Qualiflyers and Pre-Qualiflyers are
    --     each numbered from 1. The _standing helper behind "what changed"
    --     must place every student exactly where leaderboard_lists does.
    select string_agg(format('%s: view %s #%s, helper %s #%s',
                             s.name, lb.list, lb.list_rank, st.list, st.list_rank), '; ')
      into v_r
    from students s
    left join leaderboard_lists lb on lb.student_id = s.id
    cross join lateral _standing(s.id, '{}', s.is_registered_approved and s.conduct_ok) st
    where (lb.list, lb.list_rank) is distinct from (st.list, st.list_rank);
    select string_agg(format('%s %s', list, ranks), ' | ' order by list desc) into v_r2
    from (select list, string_agg(list_rank::text, ',' order by list_rank) as ranks
          from leaderboard_lists group by list) x;
    v_ok := v_r is null
      and v_r2 = 'Qualiflyers 1,2 | Pre-Qualiflyers 1,2,3,4,5,6,7'
      and not exists (select 1 from leaderboard_lists where name = 'Ishita Gupta');
    perform pg_temp.report(29, 'Each list ranked from 1; the what-changed helper matches leaderboard_lists',
                           v_ok, coalesce(v_r, v_r2));

    -- Seed-state facts for checks 31 and 33 (later checks change these students).
    select jsonb_build_object(
      'ishita_change', (select to_jsonb(c) from student_last_change(pg_temp.sid('Ishita Gupta'), 'admin', 'checks-admin') c),
      'meera',  (select to_jsonb(o) from student_overview(pg_temp.sid('Meera Joshi'), 'admin', 'checks-admin') o),
      'ishita', (select to_jsonb(o) from student_overview(pg_temp.sid('Ishita Gupta'), 'admin', 'checks-admin') o),
      'vikram', (select to_jsonb(o) from student_overview(v_vikram, 'admin', 'checks-admin') o),
      'priya',  (select to_jsonb(o) from student_overview(v_priya, 'admin', 'checks-admin') o))
      into v_snap;

    -- ===== The 12 required checks =====

    -- 1. Double booking: the second booker of a slot is refused.
    perform record_skill_result(v_arjun, (select id from skills where name = 'UI Engineering'), 2, 'gold', 40, 'system', 'checks');
    v_booking := book_slot(v_arjun, v_novice, v_free[1], 'student', v_arjun::text);
    v_r := pg_temp.expect_error(
      format('select book_slot(%L, %L, %L, %L, %L)', v_priya, v_novice, v_free[1], 'student', v_priya),
      'just booked by someone else');
    perform pg_temp.report(1, 'Second book_slot on the same slot fails', v_booking is not null and v_r like 'OK:%', v_r);

    -- 2. Overlapping open slots for one interviewer are rejected (raw insert and via create_slot).
    v_r := pg_temp.expect_error(
      format($q$insert into slots (interviewer_id, starts_at, ends_at)
                select interviewer_id, starts_at + interval '15 minutes', ends_at + interval '15 minutes'
                from slots where id = %L$q$, v_free[2]),
      'slots_no_overlap');
    v_r2 := pg_temp.expect_error(
      format('select create_slot(s.interviewer_id, s.starts_at + interval ''10 minutes'', ''admin'', ''checks'') from slots s where s.id = %L', v_free[2]),
      'overlapping');
    perform pg_temp.report(2, 'Overlapping slot for the same interviewer fails',
                           v_r like 'OK:%' and v_r2 like 'OK:%', v_r || ' | ' || v_r2);

    -- 3. The ledger is append-only.
    v_r  := pg_temp.expect_error('update miles_ledger set amount = amount + 1', 'append-only');
    v_r2 := pg_temp.expect_error('delete from miles_ledger', 'append-only');
    perform pg_temp.report(3, 'UPDATE and DELETE on miles_ledger fail',
                           v_r like 'OK:%' and v_r2 like 'OK:%', v_r || ' | ' || v_r2);

    -- 4. Past slot and a slot inside the 2-hour notice window are refused.
    insert into slots (interviewer_id, starts_at, ends_at)
    values (v_tester, now() - interval '1 day', now() - interval '1 day' + interval '30 minutes') returning id into v_id;
    v_r := pg_temp.expect_error(
      format('select book_slot(%L, %L, %L, %L, %L)', v_priya, v_novice, v_id, 'student', v_priya), 'already started');
    v_id := create_slot(v_tester, now() + interval '1 hour', 'admin', 'checks');
    v_r2 := pg_temp.expect_error(
      format('select book_slot(%L, %L, %L, %L, %L)', v_priya, v_novice, v_id, 'student', v_priya), 'at least 2 hours');
    perform pg_temp.report(4, 'Booking a past slot or one inside the notice window fails',
                           v_r like 'OK:%' and v_r2 like 'OK:%', v_r || ' | ' || v_r2);

    -- 5. No skipping: Specialist without an active Novice.
    v_r := pg_temp.expect_error(
      format('select book_slot(%L, %L, %L, %L, %L)', v_priya, v_specialist, v_free[3], 'student', v_priya),
      'Earn AI Product Mastery Novice first');
    perform pg_temp.report(5, 'Booking Specialist without an active Novice fails', v_r like 'OK:%', v_r);

    -- 6. Retake cooldown: Kavya failed 2 days ago, retake_after is in 3 days.
    v_r := pg_temp.expect_error(
      format('select book_slot(%L, %L, %L, %L, %L)', v_kavya, v_novice, v_free[3], 'student', v_kavya),
      'retake');
    perform pg_temp.report(6, 'Booking during the retake_after cooldown fails', v_r like 'OK:%', v_r);

    -- 7. Confirmed case on Novice while Specialist is active -> cascade.
    perform pg_temp.give_specialist_skills(v_vikram);
    v_booking := pg_temp.past_booking(v_vikram, v_specialist, v_tester, now() - interval '1 day 2 hours');
    v_result := record_result(v_booking, v_tester, 'pass', 'Strong', 'interviewer', v_tester::text);
    select id into v_award from badge_awards where student_id = v_vikram and badge_id = v_novice and status = 'active';
    select id into v_award2 from badge_awards where result_id = v_result;
    v_case := flag_malpractice(v_award, 'Test evidence', 'admin', 'checks-admin');
    perform decide_case(v_case, 'confirmed', 'Test confirmation', 'admin', 'checks-admin');
    select count(*) into v_n from badge_awards
    where (id = v_award and status = 'revoked' and revoke_cause = 'malpractice')
       or (id = v_award2 and status = 'revoked' and revoke_cause = 'prerequisite_revoked' and caused_by_award_id = v_award);
    select string_agg(amount::text, ',' order by amount) into v_r
    from miles_ledger where student_id = v_vikram and reason = 'badge_revoked';
    perform pg_temp.report(7, 'Confirmed Novice case revokes Novice + Specialist, -150 and -250, audited',
      v_n = 2 and v_r = '-250,-150'
        and (select count(*) from audit_log where table_name = 'badge_awards' and record_id in (v_award::text, v_award2::text)
               and action = 'UPDATE' and actor_role = 'admin' and after ->> 'status' = 'revoked') = 2
        and (select count(*) from audit_log where table_name = 'miles_ledger' and actor_role = 'admin'
               and after ->> 'reason' = 'badge_revoked' and after ->> 'student_id' = v_vikram::text) = 2
        and not (select conduct_ok from students where id = v_vikram),
      format('revoked=%s, debits=%s', v_n, v_r));

    -- 8. Leaderboard and interviewer_schedule never touch malpractice_cases,
    --    directly or through any view they depend on (walks pg_depend recursively).
    with recursive deps(oid) as (
      select unnest(array['public.leaderboard'::regclass::oid, 'public.interviewer_schedule'::regclass::oid])
      union
      select d.refobjid
      from deps
      join pg_rewrite rw on rw.ev_class = deps.oid
      join pg_depend d   on d.classid = 'pg_rewrite'::regclass and d.objid = rw.oid
                        and d.refclassid = 'pg_class'::regclass and d.refobjid <> deps.oid
    )
    select exists (select 1 from deps where oid = 'public.malpractice_cases'::regclass) into v_ok;
    v_ok := not v_ok
            and pg_get_viewdef('public.leaderboard'::regclass) !~* 'malpractice'
            and pg_get_viewdef('public.interviewer_schedule'::regclass) !~* 'malpractice';
    perform pg_temp.report(8, 'leaderboard and interviewer_schedule do not reference malpractice_cases', v_ok);

    -- 9 + 10. Priya: 100 Miles -> pass recorded 2 days after the interview -> 250,
    --         and the badge is dated by the interview, not by the recording.
    v_n := pg_temp.miles(v_priya);
    v_booking := pg_temp.past_booking(v_priya, v_novice, v_tester, now() - interval '2 days 1 hour');
    v_result := record_result(v_booking, v_tester, 'pass', 'Great demo', 'interviewer', v_tester::text);
    perform pg_temp.report(9, 'Priya Miles 100 before pass, 250 after',
                           v_n = 100 and pg_temp.miles(v_priya) = 250,
                           format('before=%s, after=%s', v_n, pg_temp.miles(v_priya)));
    select a.awarded_at = r.interview_held_at and r.recorded_at - r.interview_held_at >= interval '2 days'
      into v_ok
    from badge_awards a join interview_results r on r.id = a.result_id
    where r.id = v_result;
    perform pg_temp.report(10, 'awarded_at = interview_held_at even when recorded 2 days later', v_ok);

    -- 11. An open malpractice case does not block booking the next badge.
    perform pg_temp.give_specialist_skills(v_aditya);
    v_r := 'booked';
    begin
      v_id := book_slot(v_aditya, v_specialist, v_free[3], 'student', v_aditya::text);
    exception when others then v_r := sqlerrm;
    end;
    perform pg_temp.report(11, 'Student with an open case can still book their next badge', v_r = 'booked', v_r);

    -- 12. Interviewer correction is same-day only; admin can correct any time.
    select id into v_result from interview_results where student_id = v_kavya and badge_id = v_novice;
    update interview_results set recorded_at = recorded_at - interval '1 day' where id = v_result;
    v_r := pg_temp.expect_error(
      format('select correct_result(%L, %L, %L, %L, %L)', v_result, 'pass', 'Misread rubric', 'interviewer', v_ananya),
      'only on the day it was recorded');
    v_r2 := 'ok';
    begin
      perform correct_result(v_result, 'pass', 'Rubric re-checked by admin', 'admin', 'checks-admin');
    exception when others then v_r2 := sqlerrm;
    end;
    perform pg_temp.report(12, 'correct_result next day: interviewer fails, admin works',
      v_r like 'OK:%' and v_r2 = 'ok'
        and exists (select 1 from badge_awards where result_id = v_result and status = 'active'),
      v_r || ' | admin: ' || v_r2);

    -- ===== Extra guarantees =====

    -- 17. Reschedule is atomic: a failed move leaves the old booking active;
    --     a good move cancels the old one and links the new one to it.
    select id into v_booking from bookings where student_id = v_sneha and status = 'active';
    v_r := pg_temp.expect_error(
      format('select reschedule_booking(%L, %L, %L, %L)', v_booking, v_free[1], 'student', v_sneha), 'just booked');
    v_ok := (select status from bookings where id = v_booking) = 'active';
    v_id := reschedule_booking(v_booking, v_free[4], 'student', v_sneha::text);
    v_ok := v_ok and v_r like 'OK:%'
            and (select status from bookings where id = v_booking) = 'cancelled'
            and (select rescheduled_from_id from bookings where id = v_id) = v_booking;
    perform pg_temp.report(17, 'Reschedule is all-or-nothing and linked by rescheduled_from_id', v_ok, v_r);

    -- 18. Withdrawing a booked slot cancels the booking as 'interviewer'.
    perform withdraw_slot(v_free[4], (select interviewer_id from slots where id = v_free[4]), 'Unwell',
                          'interviewer', (select interviewer_id from slots where id = v_free[4])::text);
    perform pg_temp.report(18, 'withdraw_slot cancels the active booking with cancelled_by = interviewer',
      (select status = 'cancelled' and cancelled_by = 'interviewer' from bookings where id = v_id));

    -- 19. Grants: anon can read reference data and views, call public functions,
    --     but cannot touch cases, the audit log, internal functions or any table write.
    v_ok := not has_table_privilege('anon', 'public.malpractice_cases', 'select')
        and not has_table_privilege('anon', 'public.audit_log', 'select')
        and not has_table_privilege('anon', 'public.miles_ledger', 'insert')
        and not has_table_privilege('anon', 'public.bookings', 'select')
        and has_table_privilege('anon', 'public.leaderboard', 'select')
        and has_function_privilege('anon', 'public.book_slot(uuid,uuid,uuid,text,text)', 'execute')
        and not has_function_privilege('anon', 'public._revoke_award(uuid,text,text,text,text,uuid)', 'execute')
        and not has_function_privilege('anon', 'public._create_booking(uuid,uuid,uuid,uuid)', 'execute');
    -- Then act as anon for real. (No pg_temp helpers in here: anon may not
    -- be allowed to use this session's temp schema.)
    v_r := 'anon:';
    begin
      execute 'set local role anon';
      select count(*) into v_n from badges;             -- RLS policy lets reference rows through
      v_ok := v_ok and v_n = 20;
      v_r := v_r || format(' badges=%s', v_n);
      select count(*) into v_n from student_journey;    -- views work for anon
      v_ok := v_ok and v_n > 0;
      begin
        perform count(*) from malpractice_cases;
        v_ok := false; v_r := v_r || ' | cases READABLE';
      exception when insufficient_privilege then v_r := v_r || ' | cases denied';
      end;
      begin
        insert into miles_ledger (student_id, amount, reason, effective_at) values (v_priya, 1000, 'bonus_milestone', now());
        v_ok := false; v_r := v_r || ' | ledger WRITABLE';
      exception when insufficient_privilege then v_r := v_r || ' | ledger insert denied';
      end;
      begin                                             -- callable, and its rules run
        perform book_slot(gen_random_uuid(), v_novice, gen_random_uuid(), 'admin', 'checks-admin');
        v_ok := false;
      exception when others then
        v_ok := v_ok and sqlerrm = 'Student not found.';
        v_r := v_r || ' | book_slot: ' || sqlerrm;
      end;
      execute 'reset role';
    exception when others then
      execute 'reset role';
      v_ok := false; v_r := v_r || ' | unexpected: ' || sqlerrm;
    end;
    perform pg_temp.report(19, 'anon: reads views + reference data, no cases/audit/table writes', v_ok, v_r);

    -- 20. A case's review deadline is fixed at creation: changing the setting
    --     does not move it, and it cannot be edited. Overdue cases reach admins.
    select id into v_case from malpractice_cases where student_id = v_aditya and status = 'open';
    update program_settings set review_limit_days = 1 where id = 1;
    v_ok := (select review_due_at = flagged_at + interval '7 days' from malpractice_cases where id = v_case);
    v_r := pg_temp.expect_error(
      format('update malpractice_cases set review_due_at = now() + interval ''30 days'' where id = %L', v_case),
      'fixed when it is opened');
    -- Simulate time passing: a case flagged 10 days ago under the new 1-day limit is 9 days overdue.
    insert into malpractice_cases (student_id, badge_award_id, flagged_by, flagged_at, evidence)
    select student_id, id, 'checks', now() - interval '10 days', 'Old flag'
    from badge_awards where student_id = v_priya and status = 'active';
    v_ok := v_ok and v_r like 'OK:%'
            and exists (select 1 from admin_overdue_cases where student_id = v_priya and days_overdue = 9)
            and not exists (select 1 from admin_overdue_cases where case_id = v_case);
    perform pg_temp.report(20, 'Case review deadline fixed at creation; overdue cases reach admins', v_ok, v_r);

    -- 21. Result corrected -> can rebook any time. Priya's pass (check 9) is
    --     corrected to fail: badge revoked, -150, no cooldown, books at once.
    select id into v_result from interview_results
    where student_id = v_priya and badge_id = v_novice and outcome = 'pass';
    v_r := pg_temp.expect_error(
      format('select correct_result(%L, %L, %L, %L, %L, %L::date)',
             v_result, 'fail', 'Rubric misread', 'admin', 'checks-admin', ist_today() + 3),
      'can rebook any time');
    perform correct_result(v_result, 'fail', 'Rubric misread', 'admin', 'checks-admin');
    v_ok := v_r like 'OK:%'
      and (select retake_after is null from interview_results where id = v_result)
      and (select revoke_cause = 'result_corrected' from badge_awards where result_id = v_result)
      and pg_temp.miles(v_priya) = 100
      and (select state from student_journey where student_id = v_priya and badge_id = v_novice) = 'Ready to book';
    v_r2 := 'booked';
    begin
      perform book_slot(v_priya, v_novice, v_free[5], 'student', v_priya::text);
    exception when others then v_r2 := sqlerrm;
    end;
    perform pg_temp.report(21, 'Corrected pass: badge revoked, no cooldown, can rebook at once',
                           v_ok and v_r2 = 'booked', v_r || ' | rebook: ' || v_r2);

    -- 22. Malpractice -> rebooking only after an admin restores eligibility.
    --     Vikram's Novice + Specialist were revoked for malpractice in check 7.
    v_ok := (select state from student_journey where student_id = v_vikram and badge_id = v_novice) = 'Revoked';
    v_r := pg_temp.expect_error(
      format('select book_slot(%L, %L, %L, %L, %L)', v_vikram, v_novice, v_free[6], 'student', v_vikram),
      'admin must restore your eligibility');
    v_r2 := pg_temp.expect_error(
      format('select restore_eligibility(%L, %L, %L, %L)', v_vikram, 'Apology accepted', 'interviewer', v_ananya),
      'only available to: admin');
    perform restore_eligibility(v_vikram, 'Suspension served; apology accepted', 'admin', 'checks-admin');
    v_ok := v_ok and v_r like 'OK:%' and v_r2 like 'OK:%'
      and (select conduct_ok from students where id = v_vikram)
      and exists (select 1 from malpractice_cases where student_id = v_vikram and status = 'confirmed'
                  and eligibility_restored_by = 'checks-admin' and restore_note is not null)
      and (select status from badge_awards where id = v_award) = 'revoked'   -- badges stay revoked
      and (select state from student_journey where student_id = v_vikram and badge_id = v_novice) = 'Ready to book'
      and (select state from student_journey where student_id = v_vikram and badge_id = v_specialist) = 'Not ready'
      and pg_temp.expect_error(
            format('select restore_eligibility(%L, %L, %L, %L)', v_vikram, 'Again', 'admin', 'checks-admin'),
            'nothing to restore') like 'OK:%';
    v_r := v_r || ' | ' || v_r2;
    v_r2 := 'booked';
    begin
      perform book_slot(v_vikram, v_novice, v_free[6], 'student', v_vikram::text);
    exception when others then v_r2 := sqlerrm;
    end;
    perform pg_temp.report(22, 'Malpractice: rebooking blocked until an admin restores eligibility',
                           v_ok and v_r2 = 'booked', v_r || ' | after restore: ' || v_r2);

    -- 23. Badge deadline, simulated as having passed 3 days ago:
    --     (a) Arjun holds no badge: "Not eligible" with the deadline reason, and book_slot refuses.
    --     (b) Sneha's interview was held 4 days ago (before the deadline) but its result is
    --         entered now (after it): the badge still qualifies, so her Specialist booking works.
    select badge_deadline into v_deadline from program_settings where id = 1;
    update program_settings set badge_deadline = ist_today() - 3 where id = 1;
    v_booking := pg_temp.past_booking(v_sneha, v_novice, v_tester,
                                      ((ist_today() - 4) + time '11:00') at time zone 'Asia/Kolkata');
    v_result := record_result(v_booking, v_tester, 'pass', 'Held before the deadline', 'interviewer', v_tester::text);
    perform pg_temp.give_specialist_skills(v_sneha);
    v_r2 := 'booked';
    begin
      perform book_slot(v_sneha, v_specialist, v_free[7], 'student', v_sneha::text);
    exception when others then v_r2 := sqlerrm;
    end;
    v_r := pg_temp.expect_error(
      format('select book_slot(%L, %L, %L, %L, %L)', v_arjun, v_novice, v_free[8], 'student', v_arjun),
      'You cannot book an interview: Missed the .* badge deadline');
    v_ok := v_r like 'OK:%'
      and (select state = 'Not eligible'
                  and not_eligible_reason = format('Missed the %s badge deadline', to_char(ist_today() - 3, 'FMDD Mon'))
           from student_journey where student_id = v_arjun and badge_id = v_novice)
      and student_ineligibility_reason((select s from students s where s.id = v_sneha)) is null
      and v_r2 = 'booked';
    update program_settings set badge_deadline = v_deadline where id = 1;
    perform pg_temp.report(23, 'Badge deadline: no badge -> blocked; badge from a pre-deadline interview still qualifies',
                           v_ok, v_r || ' | qualified student''s Specialist booking: ' || v_r2);

    -- 24. Disqualified students (conduct_ok = false) forfeit leaderboard standing
    --     and reappear when an admin restores eligibility.
    v_id := pg_temp.sid('Ishita Gupta');
    v_ok := not exists (select 1 from leaderboard where student_id = v_id);
    perform restore_eligibility(v_id, 'Appeal upheld', 'admin', 'checks-admin');
    v_ok := v_ok and exists (select 1 from leaderboard where student_id = v_id);
    perform pg_temp.report(24, 'Leaderboard leaves out disqualified students; restore brings them back', v_ok);

    -- 25. Revoking a badge cancels active bookings for higher badges in the same track.
    --     (a) An admin confirms Aditya's case: his Specialist booking (check 11) is cancelled by 'admin'.
    --     (b) The interviewer corrects Sneha's Novice pass (check 23) on the same day: her
    --         Specialist booking is cancelled by 'interviewer'.
    select id into v_case from malpractice_cases where student_id = v_aditya and status = 'open';
    perform decide_case(v_case, 'confirmed', 'Evidence reviewed', 'admin', 'checks-admin');
    v_ok := (select status = 'cancelled' and cancelled_by = 'admin'
                    and cancel_reason = 'Earlier badge (Novice) was revoked'
             from bookings where student_id = v_aditya and badge_id = v_specialist);
    perform correct_result(v_result, 'fail', 'Scored against the wrong rubric', 'interviewer', v_tester::text);
    v_ok := v_ok and (select status = 'cancelled' and cancelled_by = 'interviewer'
                             and cancel_reason = 'Earlier badge (Novice) was revoked'
                      from bookings where student_id = v_sneha and badge_id = v_specialist);
    perform pg_temp.report(25, 'Revoking a badge cancels higher-badge bookings in the track', coalesce(v_ok, false));

    -- 26. The audit actor is scoped to one function call: SQL that runs
    --     afterwards in the same transaction is credited to 'system', not to
    --     whoever called the last function.
    v_id := create_slot(v_tester, now() + interval '20 days', 'interviewer', v_tester::text);
    insert into interviewers (name, email) values ('Audit Probe', 'probe@grit.example') returning id into v_probe;
    v_ok := (select actor_role = 'interviewer' and actor_id = v_tester::text
             from audit_log where table_name = 'slots' and action = 'INSERT' and record_id = v_id::text)
        and (select actor_role = 'system' and actor_id is null
             from audit_log where table_name = 'interviewers' and action = 'INSERT' and record_id = v_probe::text);
    perform pg_temp.report(26, 'Audit actor is scoped to each function call', coalesce(v_ok, false));

    -- ===== App reads (005) =====

    -- 27. A student reads only their own data, an interviewer only theirs, an
    --     admin anyone's. Internal helpers stay private even though Supabase
    --     grants new functions to anon by default.
    v_r := pg_temp.expect_error(
      format('select * from student_passbook(%L, %L, %L)', v_priya, 'student', v_arjun),
      'Students can only see their own data');
    v_r2 := pg_temp.expect_error(
      format('select * from student_passbook(%L, %L, %L)', v_priya, 'interviewer', v_ananya),
      'only available to: student, admin');
    v_ok := v_r like 'OK:%' and v_r2 like 'OK:%'
      and pg_temp.expect_error(
            format('select * from interviewer_results(%L, %L, %L)', v_ananya, 'interviewer', v_karthik),
            'Interviewers can only see their own data') like 'OK:%'
      and pg_temp.expect_error(
            format('select * from admin_active_awards(%L, %L)', 'student', v_priya),
            'only available to: admin') like 'OK:%'
      and exists (select 1 from student_passbook(v_priya, 'student', v_priya::text))
      and exists (select 1 from student_passbook(v_priya, 'admin', 'checks-admin'))
      and exists (select 1 from interviewer_results(v_ananya, 'interviewer', v_ananya::text))
      and has_table_privilege('anon', 'public.student_directory', 'select')
      and has_table_privilege('anon', 'public.leaderboard_lists', 'select')
      and not has_table_privilege('anon', 'public.student_directory', 'insert')
      and has_function_privilege('anon', 'public.student_last_change(uuid,text,text)', 'execute')
      and has_function_privilege('anon', 'public.project_review_queue(text,text)', 'execute')
      and not has_function_privilege('anon', 'public._standing(uuid,uuid[],boolean)', 'execute')
      and not has_function_privilege('anon', 'public._require_self_or_admin(text,text,text,uuid)', 'execute');
    perform pg_temp.report(27, 'App reads: own data only (admins see all); helpers not granted', v_ok, v_r || ' | ' || v_r2);

    -- 28. The passbook adds up: for every student it has one row per ledger
    --     row, in date order (seq 1 = oldest), each balance is the sum so far,
    --     and the last balance is their Miles, which the leaderboard shows too.
    select string_agg(s.name, ', ') into v_r
    from students s
    left join leaderboard_lists lb on lb.student_id = s.id
    left join lateral (
      select count(*) as n,
             (array_agg(x.balance order by x.seq desc))[1] as last_balance,
             bool_and(x.balance = x.sum_so_far and x.effective_at >= coalesce(x.prev_at, x.effective_at)) as in_order
      from (select p.seq, p.balance, p.effective_at,
                   sum(p.amount) over (order by p.seq)    as sum_so_far,
                   lag(p.effective_at) over (order by p.seq) as prev_at
            from student_passbook(s.id, 'admin', 'checks-admin') p) x
    ) pb on true
    where pb.n <> (select count(*) from miles_ledger l where l.student_id = s.id)
       or coalesce(pb.last_balance, 0) <> pg_temp.miles(s.id)
       or not coalesce(pb.in_order, true)
       or (lb.student_id is not null and lb.total_miles <> pg_temp.miles(s.id));
    perform pg_temp.report(28, 'Passbook rows and running balance add up to the leaderboard Miles', v_r is null, v_r);

    -- 30. What changed after a pass: Karthik records Rahul's result (the live
    --     demo). "Before" must equal Rahul's real standing a moment earlier.
    select to_jsonb(o) into v_before from student_overview(v_rahul, 'student', v_rahul::text) o;
    v_ok := not exists (select 1 from student_last_change(v_rahul, 'student', v_rahul::text));
    select id into v_booking from bookings where student_id = v_rahul and status = 'active';
    v_result := record_result(v_booking, v_karthik, 'pass', 'Clear product thinking', 'interviewer', v_karthik::text);
    select to_jsonb(c) into v_after from student_last_change(v_rahul, 'student', v_rahul::text) c;
    v_ok := v_ok
      and v_after ->> 'change' = 'badge_earned'
      and v_after -> 'levels' = '["Novice"]'
      and (v_after ->> 'miles_before')::int = (v_before ->> 'total_miles')::int
      and (v_after ->> 'miles_after')::int
          = (v_before ->> 'total_miles')::int + (select bonus_miles from badges where id = v_novice)
      and v_after ->> 'list_before' = 'Pre-Qualiflyers'
      and (v_after ->> 'rank_before')::int = (v_before ->> 'list_rank')::int
      and v_after ->> 'list_after' = 'Qualiflyers'
      and (v_after ->> 'rank_after')::int = (select list_rank from leaderboard_lists where student_id = v_rahul)
      and not (v_after ->> 'deadline_badge_before')::boolean
      and (v_after ->> 'deadline_badge_after')::boolean
      and (select badge_by_deadline from student_overview(v_rahul, 'student', v_rahul::text));
    perform pg_temp.report(30, 'What changed after a pass: +150 Miles, Pre-Qualiflyer -> Qualiflyer, badge ticked',
      coalesce(v_ok, false),
      format('Miles %s -> %s; %s #%s -> %s #%s', v_after ->> 'miles_before', v_after ->> 'miles_after',
             v_after ->> 'list_before', v_after ->> 'rank_before', v_after ->> 'list_after', v_after ->> 'rank_after'));

    -- 31. ...and after a removal: Karthik corrects that result to fail the same
    --     day, so everything goes back. Ishita's seeded case (before check 24
    --     restored her) is the cascade version: Novice and Specialist, -400
    --     Miles, and off the leaderboard.
    v_before := v_after;
    perform correct_result(v_result, 'fail', 'Scored against the wrong rubric', 'interviewer', v_karthik::text);
    select to_jsonb(c) into v_after from student_last_change(v_rahul, 'student', v_rahul::text) c;
    v_ok := v_after ->> 'change' = 'badge_removed'
      and v_after ->> 'cause' = 'result_corrected'
      and (v_after ->> 'miles_before')::int = (v_before ->> 'miles_after')::int
      and (v_after ->> 'miles_after')::int = (v_before ->> 'miles_before')::int
      and v_after ->> 'list_before' = 'Qualiflyers'
      and (v_after ->> 'rank_before')::int = (v_before ->> 'rank_after')::int
      and v_after ->> 'list_after' = 'Pre-Qualiflyers'
      and (v_after ->> 'rank_after')::int = (select list_rank from leaderboard_lists where student_id = v_rahul)
      and (v_after ->> 'deadline_badge_before')::boolean
      and not (v_after ->> 'deadline_badge_after')::boolean
      and v_snap -> 'ishita_change' ->> 'change' = 'badge_removed'
      and v_snap -> 'ishita_change' -> 'levels' = '["Novice", "Specialist"]'
      and v_snap -> 'ishita_change' ->> 'cause' = 'malpractice'
      and (v_snap -> 'ishita_change' ->> 'miles_before')::int - (v_snap -> 'ishita_change' ->> 'miles_after')::int = 400
      and v_snap -> 'ishita_change' ->> 'list_before' = 'Qualiflyers'
      and v_snap -> 'ishita_change' ->> 'list_after' is null
      and (v_snap -> 'ishita_change' ->> 'deadline_badge_before')::boolean
      and not (v_snap -> 'ishita_change' ->> 'deadline_badge_after')::boolean;
    perform pg_temp.report(31, 'What changed after a removal, including the cascade version',
      coalesce(v_ok, false),
      format('Rahul: Miles %s -> %s; %s #%s -> %s #%s | Ishita: %s, Miles %s -> %s, %s -> %s',
             v_after ->> 'miles_before', v_after ->> 'miles_after',
             v_after ->> 'list_before', v_after ->> 'rank_before', v_after ->> 'list_after', v_after ->> 'rank_after',
             v_snap -> 'ishita_change' ->> 'levels', v_snap -> 'ishita_change' ->> 'miles_before',
             v_snap -> 'ishita_change' ->> 'miles_after', v_snap -> 'ishita_change' ->> 'list_before',
             coalesce(v_snap -> 'ishita_change' ->> 'list_after', 'not listed')));

    -- 32. Leaderboard and interviewer screens never read malpractice_cases:
    --     not through leaderboard_lists (walking its view dependencies), and
    --     not in the source of any 005 function those screens call (nor via
    --     student_journey or admin_* objects, which do read cases).
    with recursive deps(oid) as (
      select 'public.leaderboard_lists'::regclass::oid
      union
      select d.refobjid
      from deps
      join pg_rewrite rw on rw.ev_class = deps.oid
      join pg_depend d   on d.classid = 'pg_rewrite'::regclass and d.objid = rw.oid
                        and d.refclassid = 'pg_class'::regclass and d.refobjid <> deps.oid
    )
    select not exists (select 1 from deps where oid = 'public.malpractice_cases'::regclass) into v_ok;
    select count(*), string_agg(p.proname, ', ') filter (where p.prosrc ~* 'malpractice|student_journey|admin_')
      into v_n, v_r
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('_standing', 'student_last_change', 'interviewer_slots',
                        'interviewer_results', 'project_review_queue');
    perform pg_temp.report(32, 'Leaderboard and interviewer reads never touch malpractice_cases',
                           v_ok and v_n = 5 and v_r is null, v_r);

    -- 33. The trip checklist facts match the seed: Meera's attendance (72%) is
    --     short, Ishita's confirmed case clears conduct, Vikram holds a badge
    --     from before the deadline, Priya has none yet.
    v_ok := not (v_snap -> 'meera' ->> 'attendance_ok')::boolean
      and (v_snap -> 'meera' ->> 'registered_ok')::boolean
      and (v_snap -> 'meera' ->> 'conduct_ok')::boolean
      and not (v_snap -> 'ishita' ->> 'conduct_ok')::boolean
      and not (v_snap -> 'ishita' ->> 'badge_by_deadline')::boolean
      and v_snap -> 'ishita' ->> 'list' is null
      and (v_snap -> 'vikram' ->> 'badge_by_deadline')::boolean
      and (v_snap -> 'vikram' ->> 'attendance_ok')::boolean
      and v_snap -> 'vikram' ->> 'list' = 'Qualiflyers'
      and not (v_snap -> 'priya' ->> 'badge_by_deadline')::boolean;
    perform pg_temp.report(33, 'Trip checklist facts match the seed (attendance, conduct, badge by deadline)',
                           coalesce(v_ok, false));

    -- 34. A double-click cannot correct a result twice. Karthik corrects
    --     Rahul's result (recorded in check 30) to retake_later; the same call
    --     arrives again and is refused, leaving the result and Miles as they were.
    select id into v_result from interview_results where student_id = v_rahul and badge_id = v_novice;
    perform correct_result(v_result, 'retake_later', 'Asked for a retake after a second look', 'interviewer', v_karthik::text);
    select to_jsonb(r) into v_before from interview_results r where r.id = v_result;
    v_n := pg_temp.miles(v_rahul);
    v_r := pg_temp.expect_error(
      format('select correct_result(%L, %L, %L, %L, %L)',
             v_result, 'retake_later', 'Asked for a retake after a second look', 'interviewer', v_karthik),
      'The result is already "retake_later"');
    perform pg_temp.report(34, 'The same correction sent twice is refused the second time and changes nothing',
      v_r like 'OK:%'
        and (select to_jsonb(r) from interview_results r where r.id = v_result) = v_before
        and pg_temp.miles(v_rahul) = v_n,
      v_r);

    -- Keep the results, then undo everything the checks did.
    select jsonb_agg(to_jsonb(r) order by r.check_no) into v_out from grit_check_results r;
    raise exception 'grit_checks_rollback';
  exception when others then
    if sqlerrm <> 'grit_checks_rollback' then
      raise exception 'Checks aborted by an unexpected error: % (results so far were rolled back)', sqlerrm;
    end if;
  end;

  return query
    select x.check_no, x.check_name, x.result, x.detail
    from jsonb_to_recordset(v_out) as x(check_no int, check_name text, result text, detail text)
    order by x.check_no;
end;
$$;

select * from pg_temp.grit_checks();

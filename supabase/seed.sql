-- =============================================================================
-- GRIT Layover - seed.sql
-- Demo data: real GRIT reference values + one student per journey state.
--
-- * Refuses to run unless the database is empty (see README for reset).
-- * All times are relative to now(), so the demo works whenever it is seeded.
--   Re-seed (after a reset) if the demo has aged: e.g. Sneha's "tomorrow"
--   booking becomes "Waiting for result" a day later.
-- * Reference data and past slots/bookings are inserted directly (book_slot
--   correctly rejects past slots). Skill results, future slots, live bookings,
--   results, awards, Miles, revocations and cases all go through the real
--   functions, so miles_ledger and audit_log are exactly what the app would produce.
-- =============================================================================

begin;

do $$
begin
  if exists (select 1 from students) or exists (select 1 from skills) or exists (select 1 from badges)
     or exists (select 1 from interviewers) or exists (select 1 from miles_ledger) then
    raise exception 'seed.sql only runs on an empty database. See README.md "Reset" to start over.';
  end if;
end;
$$;

-- Demo only: the demo must work on any date. If the real badge deadline has
-- already passed, move it 30 days ahead; otherwise every unqualified demo
-- student would be "Not eligible" and the bookings below would be refused.
do $$
begin
  if (select badge_deadline from program_settings where id = 1) < ist_today() then
    update program_settings set badge_deadline = ist_today() + 30 where id = 1;
    raise notice 'Demo seed: badge_deadline had passed; moved to %.', ist_today() + 30;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Reference data
-- -----------------------------------------------------------------------------
insert into skills (name, max_level) values
  ('Computational Thinking', 4),
  ('UI Engineering', 2),
  ('Server-Side Engineering', 2),
  ('SQL', 2),
  ('Applied Gen AI Development', 4),
  ('CS Fundamentals', 2),
  ('System Design', 2),
  ('Quantitative Reasoning', 2),
  ('Critical Thinking & Communication', 3),
  ('DS & ML', 4),
  ('Human Skills for the AI Era', 2),
  ('Data Intelligence', 2),
  ('Physical AI', 4),
  ('Quantitative Finance Foundations', 3);

-- 4 tracks x 5 levels. Novice 150, Specialist 250; Expert and above locked.
insert into badges (track, level, sequence, bonus_miles, needs_project, is_locked)
select t.track, l.level, l.sequence, l.bonus, t.track = 'AI Robotics Mastery', l.locked
from (values ('AI Product Mastery'), ('AI Systems Mastery'), ('AI Models Mastery'), ('AI Robotics Mastery'))
       as t(track)
cross join (values ('Novice', 1, 150, false),
                   ('Specialist', 2, 250, false),
                   ('Expert', 3, null::int, true),
                   ('Master', 4, null::int, true),
                   ('Grand Master', 5, null::int, true)) as l(level, sequence, bonus, locked);

insert into badge_requirements (badge_id, skill_id, required_level)
select b.id, s.id, r.required_level
from (values
  ('AI Product Mastery', 'Novice', 'Computational Thinking', 1),
  ('AI Product Mastery', 'Novice', 'CS Fundamentals', 1),
  ('AI Product Mastery', 'Novice', 'Applied Gen AI Development', 1),
  ('AI Product Mastery', 'Novice', 'UI Engineering', 2),

  ('AI Product Mastery', 'Specialist', 'Computational Thinking', 2),
  ('AI Product Mastery', 'Specialist', 'CS Fundamentals', 1),
  ('AI Product Mastery', 'Specialist', 'Applied Gen AI Development', 2),
  ('AI Product Mastery', 'Specialist', 'UI Engineering', 2),
  ('AI Product Mastery', 'Specialist', 'Server-Side Engineering', 1),
  ('AI Product Mastery', 'Specialist', 'SQL', 1),

  ('AI Systems Mastery', 'Novice', 'Computational Thinking', 1),
  ('AI Systems Mastery', 'Novice', 'CS Fundamentals', 1),
  ('AI Systems Mastery', 'Novice', 'Applied Gen AI Development', 1),
  ('AI Systems Mastery', 'Novice', 'Quantitative Reasoning', 1),
  ('AI Systems Mastery', 'Novice', 'Critical Thinking & Communication', 2),

  ('AI Systems Mastery', 'Specialist', 'Computational Thinking', 2),
  ('AI Systems Mastery', 'Specialist', 'CS Fundamentals', 1),
  ('AI Systems Mastery', 'Specialist', 'Applied Gen AI Development', 2),
  ('AI Systems Mastery', 'Specialist', 'Quantitative Reasoning', 1),
  ('AI Systems Mastery', 'Specialist', 'Critical Thinking & Communication', 2),

  ('AI Models Mastery', 'Novice', 'Computational Thinking', 1),
  ('AI Models Mastery', 'Novice', 'CS Fundamentals', 1),
  ('AI Models Mastery', 'Novice', 'Applied Gen AI Development', 1),
  ('AI Models Mastery', 'Novice', 'SQL', 1),
  ('AI Models Mastery', 'Novice', 'DS & ML', 1),
  ('AI Models Mastery', 'Novice', 'Data Intelligence', 1),

  ('AI Models Mastery', 'Specialist', 'Computational Thinking', 1),
  ('AI Models Mastery', 'Specialist', 'CS Fundamentals', 2),
  ('AI Models Mastery', 'Specialist', 'Applied Gen AI Development', 1),
  ('AI Models Mastery', 'Specialist', 'SQL', 2),
  ('AI Models Mastery', 'Specialist', 'DS & ML', 2),
  ('AI Models Mastery', 'Specialist', 'Data Intelligence', 2),

  ('AI Robotics Mastery', 'Novice', 'Physical AI', 1),
  ('AI Robotics Mastery', 'Novice', 'CS Fundamentals', 1),
  ('AI Robotics Mastery', 'Novice', 'Computational Thinking', 1),
  ('AI Robotics Mastery', 'Novice', 'Applied Gen AI Development', 1),
  ('AI Robotics Mastery', 'Novice', 'UI Engineering', 1),

  ('AI Robotics Mastery', 'Specialist', 'Physical AI', 2),
  ('AI Robotics Mastery', 'Specialist', 'CS Fundamentals', 1),
  ('AI Robotics Mastery', 'Specialist', 'Computational Thinking', 2),
  ('AI Robotics Mastery', 'Specialist', 'Applied Gen AI Development', 2),
  ('AI Robotics Mastery', 'Specialist', 'UI Engineering', 1),
  ('AI Robotics Mastery', 'Specialist', 'Server-Side Engineering', 1)
) as r(track, level, skill, required_level)
join badges b on b.track = r.track and b.level = r.level
join skills s on s.name = r.skill;

insert into interviewers (name, email, is_active) values
  ('Ananya Rao',    'ananya.rao@grit.example',    true),
  ('Karthik Menon', 'karthik.menon@grit.example', true),
  ('Farhan Ali',    'farhan.ali@grit.example',    false);

-- Medal Miles as the contest system sends them (gold / silver / try_again).
-- Used only to build realistic skill_results below; the database stores the
-- Miles on each attempt and does not keep this table.
create temp table seed_medal_miles (skill text, level int, gold int, silver int, try_again int) on commit drop;
insert into seed_medal_miles values
  ('Computational Thinking', 1, 20, 18, 5),            ('Computational Thinking', 2, 80, 72, 5),
  ('UI Engineering', 1, 10, 9, 5),                     ('UI Engineering', 2, 40, 36, 5),
  ('CS Fundamentals', 1, 10, 9, 5),                    ('CS Fundamentals', 2, 40, 36, 5),
  ('Applied Gen AI Development', 1, 20, 18, 5),        ('Applied Gen AI Development', 2, 80, 72, 5),
  ('SQL', 1, 10, 9, 5),                                ('SQL', 2, 40, 36, 5),
  ('Server-Side Engineering', 1, 10, 9, 5),            ('Server-Side Engineering', 2, 40, 36, 5),
  ('Quantitative Reasoning', 1, 10, 9, 5),             ('Quantitative Reasoning', 2, 40, 36, 5),
  ('Critical Thinking & Communication', 1, 10, 9, 5),  ('Critical Thinking & Communication', 2, 20, 18, 5),
  ('DS & ML', 1, 20, 18, 5),                           ('DS & ML', 2, 80, 72, 5),
  ('Data Intelligence', 1, 10, 9, 5),                  ('Data Intelligence', 2, 40, 36, 5),
  ('Physical AI', 1, 20, 18, 5),                       ('Physical AI', 2, 80, 72, 5);

-- -----------------------------------------------------------------------------
-- Seed helpers (session-only, in pg_temp)
-- -----------------------------------------------------------------------------
create function pg_temp.student(p_name text) returns uuid language sql stable as
  $$ select id from students where name = p_name $$;
create function pg_temp.interviewer(p_name text) returns uuid language sql stable as
  $$ select id from interviewers where name = p_name $$;
create function pg_temp.badge(p_track text, p_level text) returns uuid language sql stable as
  $$ select id from badges where track = p_track and level = p_level $$;

-- One contest attempt, through the real entry point (so the ledger trigger runs).
create function pg_temp.attempt(p_student text, p_skill text, p_level int, p_medal text, p_days_ago int)
returns void language plpgsql as $$
declare v_miles int;
begin
  select case p_medal when 'gold' then gold when 'silver' then silver else try_again end
    into strict v_miles
  from seed_medal_miles where skill = p_skill and level = p_level;
  perform record_skill_result(pg_temp.student(p_student), (select id from skills where name = p_skill),
                              p_level, p_medal, v_miles, 'system', 'contest-sync',
                              now() - make_interval(days => p_days_ago));
end;
$$;

-- All AI Product Novice skills cleared with gold: CT L1 20 + UI L1 10 + UI L2 40 + CSF L1 10 + Gen AI L1 20 = 100.
create function pg_temp.product_novice_skills(p_student text, p_days_ago int) returns void language plpgsql as $$
begin
  perform pg_temp.attempt(p_student, 'Computational Thinking', 1, 'gold', p_days_ago);
  perform pg_temp.attempt(p_student, 'UI Engineering', 1, 'gold', p_days_ago);
  perform pg_temp.attempt(p_student, 'UI Engineering', 2, 'gold', p_days_ago);
  perform pg_temp.attempt(p_student, 'CS Fundamentals', 1, 'gold', p_days_ago);
  perform pg_temp.attempt(p_student, 'Applied Gen AI Development', 1, 'gold', p_days_ago);
end;
$$;

-- The extra AI Product Specialist skills: CT L2, Gen AI L2, Server-Side L1, SQL L1.
create function pg_temp.product_specialist_skills(p_student text, p_days_ago int) returns void language plpgsql as $$
begin
  perform pg_temp.attempt(p_student, 'Computational Thinking', 2, 'gold', p_days_ago);
  perform pg_temp.attempt(p_student, 'Applied Gen AI Development', 2, 'silver', p_days_ago);
  perform pg_temp.attempt(p_student, 'Server-Side Engineering', 1, 'gold', p_days_ago);
  perform pg_temp.attempt(p_student, 'SQL', 1, 'gold', p_days_ago);
end;
$$;

-- A past interview: slot + booking inserted directly (book_slot rejects the
-- past by design), then the result goes through record_result.
create function pg_temp.past_interview(
  p_student text, p_track text, p_level text, p_interviewer text,
  p_starts_at timestamptz, p_outcome text default null
) returns uuid language plpgsql as $$
declare
  v_slot uuid;
  v_booking uuid;
  v_interviewer uuid := pg_temp.interviewer(p_interviewer);
begin
  insert into slots (interviewer_id, starts_at, ends_at)
  values (v_interviewer, p_starts_at, p_starts_at + interval '30 minutes')
  returning id into v_slot;
  insert into bookings (student_id, badge_id, slot_id, created_at)
  values (pg_temp.student(p_student), pg_temp.badge(p_track, p_level), v_slot, p_starts_at - interval '3 days')
  returning id into v_booking;
  if p_outcome is not null then
    perform record_result(v_booking, v_interviewer, p_outcome,
                          format('Seeded %s interview', p_outcome),
                          'interviewer', v_interviewer::text);
  end if;
  return v_booking;
end;
$$;

-- IST wall-clock time on a day relative to today.
create function pg_temp.ist_at(p_days_from_today int, p_time time) returns timestamptz language sql stable as
  $$ select ((ist_today() + p_days_from_today) + p_time) at time zone 'Asia/Kolkata' $$;

-- -----------------------------------------------------------------------------
-- Future slots: each active interviewer, 30-minute slots 10:00-13:00 IST,
-- for the next 5 days, created through create_slot.
-- -----------------------------------------------------------------------------
select create_slot(i.id, pg_temp.ist_at(d, time '10:00' + n * interval '30 minutes'), 'interviewer', i.id::text)
from interviewers i
cross join generate_series(1, 5) as d
cross join generate_series(0, 5) as n
where i.is_active
order by i.name, d, n;

-- -----------------------------------------------------------------------------
-- Students (one per journey state)
-- -----------------------------------------------------------------------------
insert into students (name, phone, batch, campus, section, primary_track,
                      is_registered_approved, attendance_pct) values
  ('Priya Sharma',    '+919000000001', 2024, 'Hyderabad', 'A', 'AI Product Mastery',  true, 88),
  ('Arjun Reddy',     '+919000000002', 2023, 'Bengaluru', 'B', 'AI Product Mastery',  true, 81),
  ('Sneha Iyer',      '+919000000003', 2025, 'Chennai',   'A', 'AI Product Mastery',  true, 92),
  ('Rahul Verma',     '+919000000004', 2024, 'Pune',      'C', 'AI Product Mastery',  true, 79),
  ('Kavya Nair',      '+919000000005', 2023, 'Hyderabad', 'B', 'AI Product Mastery',  true, 85),
  ('Vikram Singh',    '+919000000006', 2025, 'Bengaluru', 'A', 'AI Product Mastery',  true, 90),
  ('Meera Joshi',     '+919000000007', 2024, 'Chennai',   'C', 'AI Product Mastery',  true, 72),
  ('Aditya Kulkarni', '+919000000008', 2023, 'Pune',      'A', 'AI Product Mastery',  true, 87),
  ('Rohan Das',       '+919000000009', 2025, 'Hyderabad', 'C', 'AI Robotics Mastery', true, 83),
  ('Ishita Gupta',    '+919000000010', 2024, 'Bengaluru', 'B', 'AI Product Mastery',  true, 95);

-- Priya -> Ready to book. 100 Miles now; 250 after passing Novice (the live demo).
select pg_temp.product_novice_skills('Priya Sharma', 14);

-- Arjun -> Not ready: 3 of 4 cleared, UI Engineering L2 only try_again.
select pg_temp.attempt('Arjun Reddy', 'Computational Thinking', 1, 'gold', 12);
select pg_temp.attempt('Arjun Reddy', 'UI Engineering', 1, 'gold', 12);
select pg_temp.attempt('Arjun Reddy', 'UI Engineering', 2, 'try_again', 10);
select pg_temp.attempt('Arjun Reddy', 'CS Fundamentals', 1, 'silver', 12);
select pg_temp.attempt('Arjun Reddy', 'Applied Gen AI Development', 1, 'gold', 12);

-- Sneha -> Booked: tomorrow 10:00 IST with Ananya, through book_slot.
select pg_temp.product_novice_skills('Sneha Iyer', 9);
select book_slot(pg_temp.student('Sneha Iyer'), pg_temp.badge('AI Product Mastery', 'Novice'),
                 (select id from slots
                  where interviewer_id = pg_temp.interviewer('Ananya Rao')
                    and starts_at = pg_temp.ist_at(1, time '10:00')),
                 'student', pg_temp.student('Sneha Iyer')::text);

-- Rahul -> Waiting for result: booked on the most recent 10:00-12:30 IST slot
-- that has already started (today's if the morning has begun, else yesterday's).
select pg_temp.product_novice_skills('Rahul Verma', 11);
select pg_temp.past_interview('Rahul Verma', 'AI Product Mastery', 'Novice', 'Karthik Menon',
                              (select max(pg_temp.ist_at(d, time '10:00' + n * interval '30 minutes'))
                               from generate_series(-1, 0) as d, generate_series(0, 5) as n
                               where pg_temp.ist_at(d, time '10:00' + n * interval '30 minutes') <= now()));

-- Kavya -> Retake later. CT L1 try_again (+5) then silver (+13 upgrade, total 18).
-- Failed 2 days ago, so retake_after = interview date + 5 = 3 days from today.
select pg_temp.attempt('Kavya Nair', 'Computational Thinking', 1, 'try_again', 20);
select pg_temp.attempt('Kavya Nair', 'Computational Thinking', 1, 'silver', 15);
select pg_temp.attempt('Kavya Nair', 'UI Engineering', 1, 'gold', 15);
select pg_temp.attempt('Kavya Nair', 'UI Engineering', 2, 'gold', 15);
select pg_temp.attempt('Kavya Nair', 'CS Fundamentals', 1, 'gold', 15);
select pg_temp.attempt('Kavya Nair', 'Applied Gen AI Development', 1, 'gold', 15);
select pg_temp.past_interview('Kavya Nair', 'AI Product Mastery', 'Novice', 'Ananya Rao',
                              pg_temp.ist_at(-2, time '11:00'), 'fail');

-- Vikram -> Passed (qualiflyer).
select pg_temp.product_novice_skills('Vikram Singh', 25);
select pg_temp.past_interview('Vikram Singh', 'AI Product Mastery', 'Novice', 'Karthik Menon',
                              pg_temp.ist_at(-10, time '10:30'), 'pass');

-- Meera -> Not eligible: attendance 72%.
select pg_temp.product_novice_skills('Meera Joshi', 18);

-- Aditya -> Under review: passed Novice, then an open malpractice case.
-- Still ranks normally on the leaderboard.
select pg_temp.product_novice_skills('Aditya Kulkarni', 22);
select pg_temp.past_interview('Aditya Kulkarni', 'AI Product Mastery', 'Novice', 'Ananya Rao',
                              pg_temp.ist_at(-8, time '12:00'), 'pass');
select flag_malpractice(
  (select id from badge_awards where student_id = pg_temp.student('Aditya Kulkarni') and status = 'active'),
  'Second screen visible during the live coding round.',
  'interviewer', pg_temp.interviewer('Ananya Rao')::text);

-- Rohan (Robotics) -> Project pending: skills cleared, project submitted, not yet approved.
select pg_temp.attempt('Rohan Das', 'Physical AI', 1, 'gold', 16);
select pg_temp.attempt('Rohan Das', 'CS Fundamentals', 1, 'gold', 16);
select pg_temp.attempt('Rohan Das', 'Computational Thinking', 1, 'silver', 16);
select pg_temp.attempt('Rohan Das', 'Applied Gen AI Development', 1, 'gold', 16);
select pg_temp.attempt('Rohan Das', 'UI Engineering', 1, 'gold', 16);
select submit_project(pg_temp.student('Rohan Das'), pg_temp.badge('AI Robotics Mastery', 'Novice'),
                      'https://github.com/example/line-follower-bot',
                      'student', pg_temp.student('Rohan Das')::text);

-- Ishita -> Revoked: passed Novice and Specialist, then a Novice case was
-- confirmed. Cascade: Novice -150, Specialist -250, conduct_ok = false.
select pg_temp.product_novice_skills('Ishita Gupta', 40);
select pg_temp.product_specialist_skills('Ishita Gupta', 25);
select pg_temp.past_interview('Ishita Gupta', 'AI Product Mastery', 'Novice', 'Karthik Menon',
                              pg_temp.ist_at(-30, time '10:00'), 'pass');
select pg_temp.past_interview('Ishita Gupta', 'AI Product Mastery', 'Specialist', 'Ananya Rao',
                              pg_temp.ist_at(-12, time '11:30'), 'pass');
select flag_malpractice(
  (select a.id from badge_awards a
   where a.student_id = pg_temp.student('Ishita Gupta')
     and a.badge_id = pg_temp.badge('AI Product Mastery', 'Novice')),
  'Novice submission matched another student''s code line for line.',
  'admin', 'admin-demo');
select decide_case(
  (select id from malpractice_cases where student_id = pg_temp.student('Ishita Gupta')),
  'confirmed', 'Plagiarism confirmed after reviewing both submissions.',
  'admin', 'admin-demo');

commit;

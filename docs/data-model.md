# GRIT Layover data model

> Generated from the database catalog by `docs/generate-data-model.sql`. Do not edit by hand:
> change the `COMMENT ON` statements in `supabase/migrations/` and regenerate.

## Principles

1. Miles are a passbook: `miles_ledger` rows are only ever inserted. Miles = `SUM(amount)`.
2. Nothing is deleted: badges are revoked, bookings cancelled, contest attempts kept.
3. Every change is recorded in `audit_log` by triggers.
4. The database enforces the rules (constraints, triggers, functions), not just the app.
5. Journey state is derived by the `student_journey` view, never stored.
6. Date logic uses Asia/Kolkata; timestamps are `timestamptz`.

## Tables

### `program_settings`

Single-row table of program-wide rules, so policy changes are data changes (audited), not code changes.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | integer | yes |  |
| `badge_deadline` | date | yes | Last date (IST) to earn a first badge and qualify. Used for at-risk reporting only; it does not block bookings. |
| `retake_gap_days` | integer | yes | Default cooldown after fail / retake_later / no_show before the student can book again. |
| `slot_minutes` | integer | yes | Length of every interview slot created through create_slot(). |
| `min_booking_notice_hours` | integer | yes | A slot must start at least this many hours after the moment of booking. |
| `review_limit_days` | integer | yes | Days an admin has to decide a malpractice case. Copied into each case at creation. |
| `min_attendance_pct` | numeric(5,2) | yes | Minimum attendance to be eligible to book (GRIT rule: 75%). |
| `updated_at` | timestamp with time zone | yes |  |

**Rules enforced**

- `program_settings_id_check`: `CHECK ((id = 1))`
- `program_settings_min_attendance_pct_check`: `CHECK (((min_attendance_pct >= (0)::numeric) AND (min_attendance_pct <= (100)::numeric)))`
- `program_settings_min_booking_notice_hours_check`: `CHECK ((min_booking_notice_hours >= 0))`
- `program_settings_retake_gap_days_check`: `CHECK ((retake_gap_days >= 0))`
- `program_settings_review_limit_days_check`: `CHECK ((review_limit_days > 0))`
- `program_settings_slot_minutes_check`: `CHECK ((slot_minutes > 0))`

**Triggers:** `program_settings_audit`, `program_settings_no_delete`, `program_settings_no_truncate`, `program_settings_touch`

### `students`

NIAT students in the GRIT program, with the eligibility flags that gate interview booking.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `name` | text | yes |  |
| `phone` | text | yes |  |
| `batch` | integer | yes |  |
| `campus` | text | yes |  |
| `section` | text | yes |  |
| `primary_track` | grit_track | yes | The track the student is pursuing; drives "next badge" in admin views. Journeys still list every unlocked badge. |
| `is_registered_approved` | boolean | yes | Registered for GRIT and approved by an admin. Required to book and to appear on the leaderboard. |
| `attendance_pct` | numeric(5,2) | yes |  |
| `has_admin_hold` | boolean | yes |  |
| `conduct_ok` | boolean | yes | Set to false when a malpractice case is confirmed; only restore_eligibility() (admin) sets it back. Blocks booking. |
| `has_surprise_ticket` | boolean | yes | GRIT surprise ticket flag, carried for the app; no rule depends on it yet. |
| `created_at` | timestamp with time zone | yes |  |

**Rules enforced**

- `students_attendance_pct_check`: `CHECK (((attendance_pct >= (0)::numeric) AND (attendance_pct <= (100)::numeric)))`
- `students_batch_check`: `CHECK ((batch = ANY (ARRAY[2023, 2024, 2025])))`
- `students_name_check`: `CHECK ((btrim(name) <> ''::text))`
- `students_phone_key`: `UNIQUE (phone)`

**Triggers:** `students_audit`, `students_no_delete`, `students_no_truncate`

### `interviewers`

People who publish slots, run badge interviews and record results.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `name` | text | yes |  |
| `email` | text | yes |  |
| `is_active` | boolean | yes | Inactive interviewers keep their history but cannot be booked or create slots. |
| `created_at` | timestamp with time zone | yes |  |

**Rules enforced**

- `interviewers_email_check`: `CHECK ((email ~~ '%@%'::text))`
- `interviewers_email_key`: `UNIQUE (email)`
- `interviewers_name_check`: `CHECK ((btrim(name) <> ''::text))`

**Triggers:** `interviewers_audit`, `interviewers_no_delete`, `interviewers_no_truncate`

### `skills`

GRIT contest skills. Each has levels 1..max_level; badges require cleared levels.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `name` | text | yes |  |
| `max_level` | integer | yes |  |

**Rules enforced**

- `skills_max_level_check`: `CHECK (((max_level >= 1) AND (max_level <= 4)))`
- `skills_name_key`: `UNIQUE (name)`

**Triggers:** `skills_no_delete`, `skills_no_truncate`

### `badges`

The 4 tracks x 5 levels of GRIT badges. A badge is earned by passing an interview.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `track` | grit_track | yes |  |
| `level` | text | yes |  |
| `sequence` | integer | yes | Position in the track (1 = Novice). A badge needs the previous one in the same track: no skipping. |
| `bonus_miles` | integer |  | Miles credited when the badge is awarded and debited if it is revoked. Null only for locked badges. |
| `needs_project` | boolean | yes | Robotics badges need an approved project submission before booking. |
| `is_locked` | boolean | yes | Not offered yet (Expert and above). Locked badges cannot be booked and are hidden from journeys. |

**Rules enforced**

- `badges_bonus_miles_check`: `CHECK ((bonus_miles > 0))`
- `badges_bonus_required_when_open`: `CHECK ((is_locked OR (bonus_miles IS NOT NULL)))`
- `badges_level_check`: `CHECK ((level = ANY (ARRAY['Novice'::text, 'Specialist'::text, 'Expert'::text, 'Master'::text, 'Grand Master'::text])))`
- `badges_level_matches_sequence`: `CHECK ((sequence =
CASE level
    WHEN 'Novice'::text THEN 1
    WHEN 'Specialist'::text THEN 2
    WHEN 'Expert'::text THEN 3
    WHEN 'Master'::text THEN 4
    WHEN 'Grand Master'::text THEN 5
    ELSE NULL::integer
END))`
- `badges_sequence_check`: `CHECK (((sequence >= 1) AND (sequence <= 5)))`
- `badges_track_sequence_key`: `UNIQUE (track, sequence)`

**Triggers:** `badges_no_delete`, `badges_no_truncate`

### `badge_requirements`

Skill levels a student must clear (gold or silver, at that level or higher) before booking a badge interview.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `badge_id` | uuid | yes |  |
| `skill_id` | uuid | yes |  |
| `required_level` | integer | yes |  |

**Rules enforced**

- `badge_requirements_badge_id_fkey`: `FOREIGN KEY (badge_id) REFERENCES badges(id)`
- `badge_requirements_badge_id_skill_id_key`: `UNIQUE (badge_id, skill_id)`
- `badge_requirements_required_level_check`: `CHECK (((required_level >= 1) AND (required_level <= 4)))`
- `badge_requirements_skill_id_fkey`: `FOREIGN KEY (skill_id) REFERENCES skills(id)`

**Triggers:** `badge_requirements_level_check`, `badge_requirements_no_delete`, `badge_requirements_no_truncate`

### `skill_results`

One row per contest attempt, exactly as sent by the contest system. Never overwritten, so the history of upgrades is kept.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `student_id` | uuid | yes |  |
| `skill_id` | uuid | yes |  |
| `level` | integer | yes |  |
| `medal` | text | yes |  |
| `miles` | integer | yes | Miles the contest system attached to this attempt. Only the improvement over the previous best at this level reaches the ledger. |
| `attempted_at` | timestamp with time zone | yes |  |
| `created_at` | timestamp with time zone | yes |  |

**Rules enforced**

- `skill_results_level_check`: `CHECK (((level >= 1) AND (level <= 4)))`
- `skill_results_medal_check`: `CHECK ((medal = ANY (ARRAY['gold'::text, 'silver'::text, 'try_again'::text])))`
- `skill_results_miles_check`: `CHECK ((miles >= 0))`
- `skill_results_skill_id_fkey`: `FOREIGN KEY (skill_id) REFERENCES skills(id)`
- `skill_results_student_id_fkey`: `FOREIGN KEY (student_id) REFERENCES students(id)`

**Triggers:** `skill_results_append_only`, `skill_results_audit`, `skill_results_credit_miles`, `skill_results_level_check`, `skill_results_no_truncate`

### `slots`

Interview time windows published by interviewers. "Booked" is not stored here; it is derived from bookings.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `interviewer_id` | uuid | yes |  |
| `starts_at` | timestamp with time zone | yes |  |
| `ends_at` | timestamp with time zone | yes |  |
| `status` | text | yes |  |
| `withdrawn_at` | timestamp with time zone |  |  |
| `withdraw_reason` | text |  |  |
| `created_at` | timestamp with time zone | yes |  |

**Rules enforced**

- `slots_ends_after_start`: `CHECK ((ends_at > starts_at))`
- `slots_interviewer_id_fkey`: `FOREIGN KEY (interviewer_id) REFERENCES interviewers(id)`
- `slots_no_overlap`: `EXCLUDE USING gist (interviewer_id WITH =, tstzrange(starts_at, ends_at) WITH &&) WHERE ((status = 'open'::text))`
- `slots_status_check`: `CHECK ((status = ANY (ARRAY['open'::text, 'withdrawn'::text])))`
- `slots_withdrawn_has_time`: `CHECK (((status = 'withdrawn'::text) = (withdrawn_at IS NOT NULL)))`

**Triggers:** `slots_audit`, `slots_no_delete`, `slots_no_truncate`

### `bookings`

A student's reservation of a slot for a badge interview. Cancelled, never deleted.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `student_id` | uuid | yes |  |
| `badge_id` | uuid | yes |  |
| `slot_id` | uuid | yes |  |
| `status` | text | yes |  |
| `cancelled_by` | actor_role |  |  |
| `cancel_reason` | text |  |  |
| `cancelled_at` | timestamp with time zone |  |  |
| `rescheduled_from_id` | uuid |  | The cancelled booking this one replaced, so a reschedule chain can be followed. |
| `created_at` | timestamp with time zone | yes |  |
| `updated_at` | timestamp with time zone | yes |  |

**Rules enforced**

- `bookings_badge_id_fkey`: `FOREIGN KEY (badge_id) REFERENCES badges(id)`
- `bookings_cancel_fields`: `CHECK (((status = 'cancelled'::text) = ((cancelled_by IS NOT NULL) AND (cancelled_at IS NOT NULL))))`
- `bookings_cancelled_by_check`: `CHECK (((cancelled_by)::text = ANY (ARRAY['student'::text, 'interviewer'::text, 'admin'::text])))`
- `bookings_id_student_badge_key`: `UNIQUE (id, student_id, badge_id)`
- `bookings_rescheduled_from_fk`: `FOREIGN KEY (rescheduled_from_id, student_id, badge_id) REFERENCES bookings(id, student_id, badge_id)`
- `bookings_slot_id_fkey`: `FOREIGN KEY (slot_id) REFERENCES slots(id)`
- `bookings_status_check`: `CHECK ((status = ANY (ARRAY['active'::text, 'cancelled'::text, 'completed'::text])))`
- `bookings_student_id_fkey`: `FOREIGN KEY (student_id) REFERENCES students(id)`
- `bookings_one_active_per_badge`: `USING btree (student_id, badge_id) WHERE (status = 'active'::text)`
- `bookings_one_per_slot`: `USING btree (slot_id) WHERE (status = ANY (ARRAY['active'::text, 'completed'::text]))`

**Triggers:** `bookings_audit`, `bookings_no_delete`, `bookings_no_truncate`, `bookings_touch`

### `interview_results`

The outcome of one completed booking. Corrections update it in place; audit_log keeps every earlier version.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `booking_id` | uuid | yes |  |
| `student_id` | uuid | yes |  |
| `badge_id` | uuid | yes |  |
| `outcome` | text | yes |  |
| `feedback` | text |  |  |
| `retake_after` | date |  | IST date from which the student may book again. Null = no cooldown. |
| `interview_held_at` | timestamp with time zone | yes | When the interview happened. Badges are dated by this, not by when the result was typed in. |
| `recorded_at` | timestamp with time zone | yes | When the result was entered. Interviewers may self-correct only on this IST calendar day. |
| `recorded_by` | uuid | yes |  |
| `corrected_at` | timestamp with time zone |  |  |
| `correction_reason` | text |  |  |
| `updated_at` | timestamp with time zone | yes |  |

**Rules enforced**

- `interview_results_booking_fk`: `FOREIGN KEY (booking_id, student_id, badge_id) REFERENCES bookings(id, student_id, badge_id)`
- `interview_results_booking_id_key`: `UNIQUE (booking_id)`
- `interview_results_id_student_badge_key`: `UNIQUE (id, student_id, badge_id)`
- `interview_results_outcome_check`: `CHECK ((outcome = ANY (ARRAY['pass'::text, 'fail'::text, 'retake_later'::text, 'no_show'::text, 'technical_issue'::text])))`
- `interview_results_recorded_by_fkey`: `FOREIGN KEY (recorded_by) REFERENCES interviewers(id)`
- `interview_results_retake_only_when_penalised`: `CHECK (((retake_after IS NULL) OR (outcome = ANY (ARRAY['fail'::text, 'retake_later'::text, 'no_show'::text]))))`

**Triggers:** `interview_results_audit`, `interview_results_no_delete`, `interview_results_no_truncate`, `interview_results_touch`

### `project_submissions`

Project evidence for badges with needs_project (Robotics). An approved project unlocks booking.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `student_id` | uuid | yes |  |
| `badge_id` | uuid | yes |  |
| `link` | text | yes |  |
| `status` | text | yes |  |
| `submitted_at` | timestamp with time zone | yes |  |
| `reviewed_at` | timestamp with time zone |  |  |
| `reviewed_by` | uuid |  |  |
| `review_note` | text |  |  |

**Rules enforced**

- `project_submissions_badge_id_fkey`: `FOREIGN KEY (badge_id) REFERENCES badges(id)`
- `project_submissions_link_check`: `CHECK ((link ~* '^https?://'::text))`
- `project_submissions_review_fields`: `CHECK (((status = 'submitted'::text) = (reviewed_at IS NULL)))`
- `project_submissions_reviewed_by_fkey`: `FOREIGN KEY (reviewed_by) REFERENCES interviewers(id)`
- `project_submissions_status_check`: `CHECK ((status = ANY (ARRAY['submitted'::text, 'approved'::text, 'rejected'::text])))`
- `project_submissions_student_id_fkey`: `FOREIGN KEY (student_id) REFERENCES students(id)`
- `project_submissions_one_live`: `USING btree (student_id, badge_id) WHERE (status = ANY (ARRAY['submitted'::text, 'approved'::text]))`

**Triggers:** `project_submissions_audit`, `project_submissions_no_delete`, `project_submissions_no_truncate`

### `badge_awards`

A badge earned by a student. Revoked (with cause), never deleted, so the history stays visible.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `student_id` | uuid | yes |  |
| `badge_id` | uuid | yes |  |
| `result_id` | uuid | yes |  |
| `status` | text | yes |  |
| `awarded_at` | timestamp with time zone | yes | Equals the interview's interview_held_at, not when the result was recorded. |
| `created_at` | timestamp with time zone | yes |  |
| `revoked_at` | timestamp with time zone |  |  |
| `revoke_reason` | text |  |  |
| `revoke_cause` | text |  |  |
| `caused_by_award_id` | uuid |  | For cascade revocations: the lower badge whose revocation removed this one. |
| `revoked_by` | text |  | Actor id that triggered the revocation (admin, interviewer, or system). |

**Rules enforced**

- `badge_awards_cascade_has_cause`: `CHECK (((revoke_cause = 'prerequisite_revoked'::text) = (caused_by_award_id IS NOT NULL)))`
- `badge_awards_caused_by_award_id_fkey`: `FOREIGN KEY (caused_by_award_id) REFERENCES badge_awards(id)`
- `badge_awards_id_student_key`: `UNIQUE (id, student_id)`
- `badge_awards_result_fk`: `FOREIGN KEY (result_id, student_id, badge_id) REFERENCES interview_results(id, student_id, badge_id)`
- `badge_awards_revoke_cause_check`: `CHECK ((revoke_cause = ANY (ARRAY['malpractice'::text, 'result_corrected'::text, 'prerequisite_revoked'::text])))`
- `badge_awards_revoke_fields`: `CHECK (((status = 'revoked'::text) = ((revoked_at IS NOT NULL) AND (revoke_cause IS NOT NULL))))`
- `badge_awards_status_check`: `CHECK ((status = ANY (ARRAY['active'::text, 'revoked'::text])))`
- `badge_awards_one_active_per_result`: `USING btree (result_id) WHERE (status = 'active'::text)`
- `badge_awards_one_active`: `USING btree (student_id, badge_id) WHERE (status = 'active'::text)`

**Triggers:** `badge_awards_audit`, `badge_awards_no_delete`, `badge_awards_no_truncate`

### `miles_ledger`

The Miles passbook. Rows are only ever inserted; a student's Miles = SUM(amount).

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `student_id` | uuid | yes |  |
| `amount` | integer | yes |  |
| `reason` | text | yes |  |
| `source_id` | uuid |  | Row that caused the entry: skill_results.id for medals, badge_awards.id for bonuses and revocations. |
| `note` | text |  |  |
| `effective_at` | timestamp with time zone | yes | When the Miles were earned or lost (e.g. interview time), as opposed to created_at (when the row was written). |
| `created_at` | timestamp with time zone | yes |  |

**Rules enforced**

- `miles_ledger_amount_check`: `CHECK ((amount <> 0))`
- `miles_ledger_reason_check`: `CHECK ((reason = ANY (ARRAY['skill_medal'::text, 'medal_upgrade'::text, 'badge_bonus'::text, 'badge_revoked'::text, 'bonus_milestone'::text])))`
- `miles_ledger_student_id_fkey`: `FOREIGN KEY (student_id) REFERENCES students(id)`

**Triggers:** `miles_ledger_append_only`, `miles_ledger_audit`, `miles_ledger_no_truncate`

### `malpractice_cases`

Flags raised against an awarded badge. While open, the student's badges count but final steps are on hold.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | uuid | yes |  |
| `student_id` | uuid | yes |  |
| `badge_award_id` | uuid | yes |  |
| `flagged_by` | text | yes |  |
| `flagged_at` | timestamp with time zone | yes |  |
| `evidence` | text | yes |  |
| `status` | text | yes |  |
| `review_due_at` | timestamp with time zone | yes | flagged_at + review_limit_days, fixed at creation so later setting changes do not move existing deadlines. |
| `decided_by` | text |  |  |
| `decided_at` | timestamp with time zone |  |  |
| `decision_note` | text |  |  |
| `eligibility_restored_at` | timestamp with time zone |  | When an admin let the student book again after this confirmed case (restore_eligibility). Revoked badges stay revoked. |
| `eligibility_restored_by` | text |  |  |
| `restore_note` | text |  |  |

**Rules enforced**

- `malpractice_cases_award_fk`: `FOREIGN KEY (badge_award_id, student_id) REFERENCES badge_awards(id, student_id)`
- `malpractice_cases_decision_fields`: `CHECK (((status = 'open'::text) = (decided_at IS NULL)))`
- `malpractice_cases_evidence_check`: `CHECK ((btrim(evidence) <> ''::text))`
- `malpractice_cases_restore_fields`: `CHECK (((eligibility_restored_at IS NULL) OR ((status = 'confirmed'::text) AND (eligibility_restored_by IS NOT NULL) AND (restore_note IS NOT NULL))))`
- `malpractice_cases_status_check`: `CHECK ((status = ANY (ARRAY['open'::text, 'confirmed'::text, 'dismissed'::text])))`
- `malpractice_cases_one_open_per_award`: `USING btree (badge_award_id) WHERE (status = 'open'::text)`

**Triggers:** `malpractice_cases_audit`, `malpractice_cases_no_delete`, `malpractice_cases_no_truncate`, `malpractice_cases_review_due`

### `audit_log`

Row-level history of every change to business tables, written by triggers. Who did what, and the before/after values.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `id` | bigint | yes |  |
| `actor_role` | actor_role | yes | From app.actor_role, set by the function that made the change. "system" when changed by direct SQL. |
| `actor_id` | text |  |  |
| `action` | text | yes |  |
| `table_name` | text | yes |  |
| `record_id` | text |  |  |
| `before` | jsonb |  |  |
| `after` | jsonb |  |  |
| `created_at` | timestamp with time zone | yes |  |

**Rules enforced**

- `audit_log_action_check`: `CHECK ((action = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))`

**Triggers:** `audit_log_append_only`, `audit_log_no_truncate`

## Views

### `skill_progress`

Internal. Highest cleared (gold/silver) and attempted level per student and skill.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `student_id` | uuid |  |  |
| `skill_id` | uuid |  |  |
| `best_cleared_level` | integer |  |  |
| `best_attempted_level` | integer |  |  |

### `available_slots`

Open, unbooked slots of active interviewers that are still outside the booking notice window.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `slot_id` | uuid |  |  |
| `interviewer_id` | uuid |  |  |
| `interviewer_name` | text |  |  |
| `starts_at` | timestamp with time zone |  |  |
| `ends_at` | timestamp with time zone |  |  |
| `ist_day` | date |  |  |

### `student_journey`

Derived journey state per student and unlocked badge. Never stored, so it cannot drift from the facts.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `student_id` | uuid |  |  |
| `student_name` | text |  |  |
| `primary_track` | grit_track |  |  |
| `badge_id` | uuid |  |  |
| `track` | grit_track |  |  |
| `level` | text |  |  |
| `sequence` | integer |  |  |
| `state` | text |  |  |
| `not_eligible_reason` | text |  |  |
| `previous_badge_held` | boolean |  |  |
| `skills_cleared` | integer |  |  |
| `skills_total` | integer |  |  |
| `slot_starts_at` | timestamp with time zone |  |  |
| `interviewer_name` | text |  |  |
| `retake_after` | date |  |  |
| `final_steps_on_hold` | boolean |  |  |

### `leaderboard`

Registered, approved, not disqualified students ranked by Miles, highest badge, skill depth, then who reached their total first.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `rank` | bigint |  |  |
| `name` | text |  |  |
| `batch` | integer |  |  |
| `campus` | text |  |  |
| `section` | text |  |  |
| `highest_badge` | text |  |  |
| `total_miles` | integer |  |  |
| `skill_depth` | integer |  |  |
| `is_qualiflyer` | boolean |  |  |
| `student_id` | uuid |  |  |

### `admin_booking_status`

Admin: each eligible student's next badge in their primary track, its journey state, and whether it is booked.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `student_id` | uuid |  |  |
| `name` | text |  |  |
| `batch` | integer |  |  |
| `campus` | text |  |  |
| `section` | text |  |  |
| `primary_track` | grit_track |  |  |
| `next_badge` | text |  |  |
| `journey_state` | text |  |  |
| `is_booked` | boolean |  |  |
| `slot_starts_at` | timestamp with time zone |  |  |
| `interviewer_name` | text |  |  |

### `admin_overdue_cases`

Admin: open malpractice cases past their review deadline.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `case_id` | uuid |  |  |
| `student_id` | uuid |  |  |
| `student_name` | text |  |  |
| `track` | grit_track |  |  |
| `level` | text |  |  |
| `flagged_by` | text |  |  |
| `flagged_at` | timestamp with time zone |  |  |
| `review_due_at` | timestamp with time zone |  |  |
| `days_overdue` | integer |  |  |
| `evidence` | text |  |  |

### `admin_at_risk`

Admin: registered students with no active badge and no active booking, with days left to the badge deadline.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `student_id` | uuid |  |  |
| `name` | text |  |  |
| `batch` | integer |  |  |
| `campus` | text |  |  |
| `section` | text |  |  |
| `primary_track` | grit_track |  |  |
| `not_eligible_reason` | text |  |  |
| `badge_deadline` | date |  |  |
| `days_left` | integer |  |  |

### `interviewer_schedule`

Interviewer: their active and completed bookings by IST day, with any recorded outcome.

| Column | Type | Not null | Notes |
|---|---|---|---|
| `interviewer_id` | uuid |  |  |
| `interviewer_name` | text |  |  |
| `ist_day` | date |  |  |
| `bookings_that_day` | bigint |  |  |
| `slot_id` | uuid |  |  |
| `starts_at` | timestamp with time zone |  |  |
| `ends_at` | timestamp with time zone |  |  |
| `booking_id` | uuid |  |  |
| `booking_status` | text |  |  |
| `student_id` | uuid |  |  |
| `student_name` | text |  |  |
| `track` | grit_track |  |  |
| `level` | text |  |  |
| `result_id` | uuid |  |  |
| `outcome` | text |  |  |

## Functions

Public functions are the only write path for the app. Internal helpers (prefixed `_`) are not listed and not granted.

### `admin_audit_log(p_actor_role text, p_actor_id text, p_table text, p_record_id text, p_limit integer)`

Admin only. Recent audit rows, optionally for one table / record.

### `admin_list_cases(p_actor_role text, p_actor_id text)`

Admin only. All malpractice cases, open first, soonest deadline first.

### `book_slot(p_student uuid, p_badge uuid, p_slot uuid, p_actor_role text, p_actor_id text)`

Books a badge interview after checking eligibility, badge order, skills, project, cooldown and slot rules in one transaction.

### `cancel_booking(p_booking uuid, p_reason text, p_actor_role text, p_actor_id text)`

Cancels an active booking (never deletes it). After the slot starts, admin only.

### `correct_result(p_result uuid, p_new_outcome text, p_reason text, p_actor_role text, p_actor_id text, p_retake_after date)`

Changes an outcome. Interviewers: same IST day as recorded_at, own results only. Admins: any time. A corrected pass revokes the badge with no retake cooldown.

### `create_slot(p_interviewer uuid, p_starts_at timestamp with time zone, p_actor_role text, p_actor_id text)`

Publishes a slot of program_settings.slot_minutes. Overlaps are rejected by the exclusion constraint.

### `decide_case(p_case uuid, p_decision text, p_note text, p_actor_role text, p_actor_id text)`

Admin decision. Confirmed: revoke the badge (cascading) and set conduct_ok = false until an admin calls restore_eligibility(). Dismissed: no change.

### `flag_malpractice(p_award uuid, p_evidence text, p_actor_role text, p_actor_id text)`

Opens a malpractice case. The badge still counts; final steps wait. Review deadline is set by trigger.

### `format_ist(p_ts timestamp with time zone)`

Human-readable IST timestamp for error messages.

### `ist_date(p_ts timestamp with time zone)`

Calendar date of a timestamp in Asia/Kolkata.

### `ist_today()`

Today in Asia/Kolkata. now() is fixed for a transaction, so this is too.

### `record_result(p_booking uuid, p_interviewer uuid, p_outcome text, p_feedback text, p_actor_role text, p_actor_id text, p_retake_after date, p_interview_held_at timestamp with time zone)`

Records an interview outcome, completes the booking, and on pass awards the badge and its bonus Miles.

### `record_skill_result(p_student uuid, p_skill uuid, p_level integer, p_medal text, p_miles integer, p_actor_role text, p_actor_id text, p_attempted_at timestamp with time zone)`

Stores one contest attempt; a trigger credits only the improvement over the previous best.

### `reschedule_booking(p_booking uuid, p_new_slot uuid, p_actor_role text, p_actor_id text)`

Moves a booking to a new slot atomically; the new booking links back via rescheduled_from_id.

### `restore_eligibility(p_student uuid, p_note text, p_actor_role text, p_actor_id text)`

Admin only. Lets a student book again after a confirmed malpractice case: conduct_ok = true, with who/why stamped on the case. Revoked badges stay revoked.

### `review_project(p_submission uuid, p_decision text, p_note text, p_actor_role text, p_actor_id text)`

Approves or rejects a submitted project.

### `student_ineligibility_reason(p_student students)`

Why a student may not book, or null if eligible: approval, attendance, hold, conduct, missed badge deadline. Used by book_slot and every view.

### `submit_project(p_student uuid, p_badge uuid, p_link text, p_actor_role text, p_actor_id text)`

Submits a project link for a needs_project badge. One live submission per badge; resubmit after rejection.

### `withdraw_slot(p_slot uuid, p_interviewer uuid, p_reason text, p_actor_role text, p_actor_id text)`

Withdraws a future slot and cancels any active booking on it (cancelled_by = interviewer).


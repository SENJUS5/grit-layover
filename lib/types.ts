// Row shapes returned by the database (views and functions in supabase/migrations).
// Dates come as ISO strings: timestamptz -> "2026-11-14T04:30:00+00:00",
// date -> "2026-11-14".

export type Role = "student" | "interviewer" | "admin";

/** Who the app is acting as. Passed to every function as p_actor_role / p_actor_id. */
export type Actor = { role: Role; id: string; name: string };

export type JourneyState =
  | "Not eligible"
  | "Not ready"
  | "Project pending"
  | "Ready to book"
  | "Booked"
  | "Waiting for result"
  | "Retake later"
  | "Passed"
  | "Under review"
  | "Revoked";

export type ListName = "Qualiflyers" | "Pre-Qualiflyers";
export type Outcome = "pass" | "fail" | "retake_later" | "no_show" | "technical_issue";
export type RevokeCause = "malpractice" | "result_corrected" | "prerequisite_revoked";
export type LedgerReason = "skill_medal" | "medal_upgrade" | "badge_bonus" | "badge_revoked" | "bonus_milestone";

export type StudentDirectoryRow = {
  student_id: string;
  name: string;
  primary_track: string;
  batch: number;
  campus: string;
  section: string;
};

export type InterviewerRow = { id: string; name: string };

export type Settings = {
  badge_deadline: string;
  retake_gap_days: number;
  slot_minutes: number;
  min_booking_notice_hours: number;
  min_attendance_pct: number;
};

/** student_journey view */
export type JourneyRow = {
  student_id: string;
  student_name: string;
  primary_track: string;
  badge_id: string;
  track: string;
  level: string;
  sequence: number;
  state: JourneyState;
  not_eligible_reason: string | null;
  previous_badge_held: boolean;
  skills_cleared: number;
  skills_total: number;
  slot_starts_at: string | null;
  interviewer_name: string | null;
  retake_after: string | null;
  final_steps_on_hold: boolean;
};

/** leaderboard_lists view */
export type LeaderboardRow = {
  list: ListName;
  list_rank: number;
  student_id: string;
  name: string;
  batch: number;
  campus: string;
  section: string;
  highest_badge: string | null;
  total_miles: number;
  skill_depth: number;
  is_qualiflyer: boolean;
  overall_rank: number;
};

/** available_slots view */
export type AvailableSlot = {
  slot_id: string;
  interviewer_id: string;
  interviewer_name: string;
  starts_at: string;
  ends_at: string;
  ist_day: string;
};

/** student_overview() */
export type Overview = {
  student_id: string;
  name: string;
  primary_track: string;
  total_miles: number;
  list: ListName | null;
  list_rank: number | null;
  attendance_pct: number;
  min_attendance_pct: number;
  attendance_ok: boolean;
  registered_ok: boolean;
  conduct_ok: boolean;
  badge_deadline: string;
  badge_by_deadline: boolean;
};

/** student_passbook() */
export type PassbookRow = {
  entry_id: string;
  seq: number;
  effective_at: string;
  amount: number;
  balance: number;
  reason: LedgerReason;
  skill_name: string | null;
  skill_level: number | null;
  medal: "gold" | "silver" | "try_again" | null;
  badge_track: string | null;
  badge_level: string | null;
  note: string | null;
};

/** student_requirements() */
export type RequirementRow = {
  badge_id: string;
  track: string;
  level: string;
  sequence: number;
  skill_name: string;
  required_level: number;
  best_cleared_level: number | null;
  best_attempted_level: number | null;
  is_cleared: boolean;
};

/** student_projects() */
export type ProjectRow = {
  badge_id: string;
  track: string;
  level: string;
  submission_id: string | null;
  link: string | null;
  status: "submitted" | "approved" | "rejected" | null;
  submitted_at: string | null;
  reviewed_at: string | null;
  review_note: string | null;
};

/** student_bookings() */
export type BookingRow = {
  booking_id: string;
  badge_id: string;
  track: string;
  level: string;
  slot_id: string;
  starts_at: string;
  ends_at: string;
  interviewer_name: string;
};

/** student_timeline() */
export type TimelineEvent = {
  kind: "result" | "badge_removed";
  happened_at: string;
  track: string;
  levels: string[];
  outcome: Outcome | null;
  feedback: string | null;
  retake_after: string | null;
  interview_held_at: string | null;
  corrected: boolean | null;
  correction_reason: string | null;
  bonus_miles: number | null;
  cause: RevokeCause | null;
  miles_change: number | null;
};

/** student_last_change() */
export type LastChange = {
  change: "badge_earned" | "badge_removed";
  happened_at: string;
  track: string;
  levels: string[];
  cause: RevokeCause | null;
  miles_before: number;
  miles_after: number;
  list_before: ListName | null;
  rank_before: number | null;
  list_after: ListName | null;
  rank_after: number | null;
  deadline_badge_before: boolean;
  deadline_badge_after: boolean;
};

/** interviewer_schedule view */
export type ScheduleRow = {
  interviewer_id: string;
  interviewer_name: string;
  ist_day: string;
  bookings_that_day: number;
  slot_id: string;
  starts_at: string;
  ends_at: string;
  booking_id: string;
  booking_status: "active" | "completed";
  student_id: string;
  student_name: string;
  track: string;
  level: string;
  result_id: string | null;
  outcome: Outcome | null;
};

/** interviewer_slots() */
export type InterviewerSlot = {
  slot_id: string;
  starts_at: string;
  ends_at: string;
  ist_day: string;
  status: "open" | "withdrawn";
  withdraw_reason: string | null;
  booking_id: string | null;
  booking_status: "active" | "completed" | null;
  student_name: string | null;
  track: string | null;
  level: string | null;
};

/** interviewer_results() */
export type InterviewerResult = {
  result_id: string;
  booking_id: string;
  student_name: string;
  track: string;
  level: string;
  outcome: Outcome;
  feedback: string | null;
  retake_after: string | null;
  interview_held_at: string;
  recorded_at: string;
  corrected_at: string | null;
  correction_reason: string | null;
  can_correct_today: boolean;
};

/** project_review_queue() */
export type ProjectQueueRow = {
  submission_id: string;
  student_id: string;
  student_name: string;
  track: string;
  level: string;
  link: string;
  submitted_at: string;
};

/** admin_booking_status view */
export type BookingStatusRow = {
  student_id: string;
  name: string;
  batch: number;
  campus: string;
  section: string;
  primary_track: string;
  next_badge: string | null;
  journey_state: string;
  is_booked: boolean;
  slot_starts_at: string | null;
  interviewer_name: string | null;
};

/** admin_at_risk view */
export type AtRiskRow = {
  student_id: string;
  name: string;
  batch: number;
  campus: string;
  section: string;
  primary_track: string;
  not_eligible_reason: string | null;
  badge_deadline: string;
  days_left: number;
};

/** admin_overdue_cases view */
export type OverdueCaseRow = {
  case_id: string;
  student_id: string;
  student_name: string;
  track: string;
  level: string;
  flagged_by: string;
  flagged_at: string;
  review_due_at: string;
  days_overdue: number;
  evidence: string;
};

/** admin_list_cases() */
export type CaseRow = {
  case_id: string;
  student_id: string;
  student_name: string;
  track: string;
  level: string;
  status: "open" | "confirmed" | "dismissed";
  flagged_by: string;
  flagged_at: string;
  review_due_at: string;
  is_overdue: boolean;
  evidence: string;
  decided_by: string | null;
  decided_at: string | null;
  decision_note: string | null;
  eligibility_restored_at: string | null;
  eligibility_restored_by: string | null;
  restore_note: string | null;
};

/** admin_active_awards() */
export type ActiveAward = {
  award_id: string;
  student_id: string;
  student_name: string;
  track: string;
  level: string;
  awarded_at: string;
  has_open_case: boolean;
};

/** admin_audit_log() */
export type AuditRow = {
  id: number;
  actor_role: string;
  actor_id: string | null;
  action: "INSERT" | "UPDATE" | "DELETE";
  table_name: string;
  record_id: string | null;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
  created_at: string;
};

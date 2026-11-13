// Every database call the app makes. Reads go to views, to the reference
// tables that 004_security.sql opens to everyone, or to read functions in
// 005_app_reads.sql. Writes only ever call the functions in 002_functions.sql.
// Errors are raised as written by the database: they are meant for users.

import type { PostgrestError } from "@supabase/supabase-js";
import { supabase } from "./supabase";
import type {
  ActiveAward,
  Actor,
  AtRiskRow,
  AuditRow,
  AvailableSlot,
  BookingRow,
  BookingStatusRow,
  CaseRow,
  InterviewerResult,
  InterviewerRow,
  InterviewerSlot,
  JourneyRow,
  LastChange,
  LeaderboardRow,
  Outcome,
  OverdueCaseRow,
  Overview,
  PassbookRow,
  ProjectQueueRow,
  ProjectRow,
  RequirementRow,
  ScheduleRow,
  Settings,
  StudentDirectoryRow,
  TimelineEvent,
} from "./types";

type Result<T> = { data: T | null; error: PostgrestError | null };

async function unwrap<T>(query: PromiseLike<Result<T>>): Promise<T> {
  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return data as T;
}

function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  return unwrap<T>(supabase().rpc(fn, args));
}

const as = (actor: Actor) => ({ p_actor_role: actor.role, p_actor_id: actor.id });

// ---------------------------------------------------------------- reads ----

export const getStudentDirectory = () =>
  unwrap<StudentDirectoryRow[]>(supabase().from("student_directory").select("*").order("name"));

export const getInterviewers = () =>
  unwrap<InterviewerRow[]>(supabase().from("interviewers").select("id, name").eq("is_active", true).order("name"));

export const getSettings = async () => {
  const rows = await unwrap<Settings[]>(
    supabase()
      .from("program_settings")
      .select("badge_deadline, retake_gap_days, slot_minutes, min_booking_notice_hours, min_attendance_pct"),
  );
  return rows[0];
};

export const getJourney = (studentId: string) =>
  unwrap<JourneyRow[]>(
    supabase().from("student_journey").select("*").eq("student_id", studentId).order("track").order("sequence"),
  );

export const getLeaderboard = () =>
  unwrap<LeaderboardRow[]>(
    supabase()
      .from("leaderboard_lists")
      .select("*")
      .order("is_qualiflyer", { ascending: false })
      .order("list_rank")
      .order("name"),
  );

export const getAvailableSlots = () =>
  unwrap<AvailableSlot[]>(supabase().from("available_slots").select("*").order("starts_at").order("interviewer_name"));

export const getInterviewerSchedule = (interviewerId: string) =>
  unwrap<ScheduleRow[]>(
    supabase().from("interviewer_schedule").select("*").eq("interviewer_id", interviewerId).order("starts_at"),
  );

export const getBookingStatus = () =>
  unwrap<BookingStatusRow[]>(supabase().from("admin_booking_status").select("*").order("is_booked").order("name"));

export const getAtRisk = () =>
  unwrap<AtRiskRow[]>(supabase().from("admin_at_risk").select("*").order("days_left").order("name"));

export const getOverdueCases = () =>
  unwrap<OverdueCaseRow[]>(supabase().from("admin_overdue_cases").select("*").order("review_due_at"));

export const studentOverview = async (actor: Actor, studentId: string) => {
  const rows = await rpc<Overview[]>("student_overview", { p_student: studentId, ...as(actor) });
  return rows[0] ?? null;
};

export const studentPassbook = (actor: Actor, studentId: string) =>
  rpc<PassbookRow[]>("student_passbook", { p_student: studentId, ...as(actor) });

export const studentRequirements = (actor: Actor, studentId: string) =>
  rpc<RequirementRow[]>("student_requirements", { p_student: studentId, ...as(actor) });

export const studentProjects = (actor: Actor, studentId: string) =>
  rpc<ProjectRow[]>("student_projects", { p_student: studentId, ...as(actor) });

export const studentBookings = (actor: Actor, studentId: string) =>
  rpc<BookingRow[]>("student_bookings", { p_student: studentId, ...as(actor) });

export const studentTimeline = (actor: Actor, studentId: string) =>
  rpc<TimelineEvent[]>("student_timeline", { p_student: studentId, ...as(actor) });

export const studentLastChange = async (actor: Actor, studentId: string) => {
  const rows = await rpc<LastChange[]>("student_last_change", { p_student: studentId, ...as(actor) });
  return rows[0] ?? null;
};

export const interviewerSlots = (actor: Actor, interviewerId: string) =>
  rpc<InterviewerSlot[]>("interviewer_slots", { p_interviewer: interviewerId, ...as(actor) });

export const interviewerResults = (actor: Actor, interviewerId: string) =>
  rpc<InterviewerResult[]>("interviewer_results", { p_interviewer: interviewerId, ...as(actor) });

export const projectReviewQueue = (actor: Actor) => rpc<ProjectQueueRow[]>("project_review_queue", as(actor));

export const adminActiveAwards = (actor: Actor) => rpc<ActiveAward[]>("admin_active_awards", as(actor));

export const adminListCases = (actor: Actor) => rpc<CaseRow[]>("admin_list_cases", as(actor));

export const adminAuditLog = (actor: Actor, table: string | null, limit = 200) =>
  rpc<AuditRow[]>("admin_audit_log", { ...as(actor), p_table: table, p_record_id: null, p_limit: limit });

// --------------------------------------------------------------- writes ----

export const bookSlot = (actor: Actor, studentId: string, badgeId: string, slotId: string) =>
  rpc<string>("book_slot", { p_student: studentId, p_badge: badgeId, p_slot: slotId, ...as(actor) });

export const cancelBooking = (actor: Actor, bookingId: string, reason: string) =>
  rpc<null>("cancel_booking", { p_booking: bookingId, p_reason: reason, ...as(actor) });

export const rescheduleBooking = (actor: Actor, bookingId: string, newSlotId: string) =>
  rpc<string>("reschedule_booking", { p_booking: bookingId, p_new_slot: newSlotId, ...as(actor) });

export const submitProject = (actor: Actor, studentId: string, badgeId: string, link: string) =>
  rpc<string>("submit_project", { p_student: studentId, p_badge: badgeId, p_link: link, ...as(actor) });

export const createSlot = (actor: Actor, interviewerId: string, startsAt: string) =>
  rpc<string>("create_slot", { p_interviewer: interviewerId, p_starts_at: startsAt, ...as(actor) });

export const withdrawSlot = (actor: Actor, slotId: string, interviewerId: string, reason: string) =>
  rpc<null>("withdraw_slot", { p_slot: slotId, p_interviewer: interviewerId, p_reason: reason, ...as(actor) });

export const recordResult = (
  actor: Actor,
  bookingId: string,
  interviewerId: string,
  outcome: Outcome,
  feedback: string,
  retakeAfter: string | null,
) =>
  rpc<string>("record_result", {
    p_booking: bookingId,
    p_interviewer: interviewerId,
    p_outcome: outcome,
    p_feedback: feedback || null,
    p_retake_after: retakeAfter,
    ...as(actor),
  });

export const correctResult = (
  actor: Actor,
  resultId: string,
  outcome: Outcome,
  reason: string,
  retakeAfter: string | null,
) =>
  rpc<null>("correct_result", {
    p_result: resultId,
    p_new_outcome: outcome,
    p_reason: reason,
    p_retake_after: retakeAfter,
    ...as(actor),
  });

export const reviewProject = (actor: Actor, submissionId: string, decision: "approved" | "rejected", note: string) =>
  rpc<null>("review_project", { p_submission: submissionId, p_decision: decision, p_note: note || null, ...as(actor) });

export const flagMalpractice = (actor: Actor, awardId: string, evidence: string) =>
  rpc<string>("flag_malpractice", { p_award: awardId, p_evidence: evidence, ...as(actor) });

export const decideCase = (actor: Actor, caseId: string, decision: "confirmed" | "dismissed", note: string) =>
  rpc<null>("decide_case", { p_case: caseId, p_decision: decision, p_note: note, ...as(actor) });

export const restoreEligibility = (actor: Actor, studentId: string, note: string) =>
  rpc<null>("restore_eligibility", { p_student: studentId, p_note: note, ...as(actor) });

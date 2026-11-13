"use client";

import useSWR from "swr";
import { ADMIN } from "./actor";
import * as api from "./api";
import type { Actor } from "./types";

// One SWR key per read, shared by every screen, so a write (which re-reads
// everything, see use-action.ts) updates all of them at once.

// Student reads: the actor is the student (the database checks it).
export const useOverview = (s: Actor) => useSWR(["overview", s.id], () => api.studentOverview(s, s.id));
export const useJourney = (s: Actor) => useSWR(["journey", s.id], () => api.getJourney(s.id));
export const useTimeline = (s: Actor) => useSWR(["timeline", s.id], () => api.studentTimeline(s, s.id));
export const useLastChange = (s: Actor) => useSWR(["last-change", s.id], () => api.studentLastChange(s, s.id));
export const useRequirements = (s: Actor) => useSWR(["requirements", s.id], () => api.studentRequirements(s, s.id));
export const useProjects = (s: Actor) => useSWR(["projects", s.id], () => api.studentProjects(s, s.id));
export const useBookings = (s: Actor) => useSWR(["bookings", s.id], () => api.studentBookings(s, s.id));
export const usePassbook = (s: Actor) => useSWR(["passbook", s.id], () => api.studentPassbook(s, s.id));

// Shared reads.
export const useLeaderboard = () => useSWR(["leaderboard"], api.getLeaderboard);
export const useAvailableSlots = () => useSWR(["available-slots"], api.getAvailableSlots);
export const useSettings = () => useSWR(["settings"], api.getSettings);
export const useDirectory = () => useSWR(["directory"], api.getStudentDirectory);
export const useInterviewers = () => useSWR(["interviewers"], api.getInterviewers);

// Interviewer reads: the actor is the interviewer.
export const useSchedule = (i: Actor) => useSWR(["schedule", i.id], () => api.getInterviewerSchedule(i.id));
export const useInterviewerSlots = (i: Actor) => useSWR(["interviewer-slots", i.id], () => api.interviewerSlots(i, i.id));
export const useInterviewerResults = (i: Actor) =>
  useSWR(["interviewer-results", i.id], () => api.interviewerResults(i, i.id));
export const useProjectQueue = (a: Actor) => useSWR(["project-queue", a.role], () => api.projectReviewQueue(a));

// Admin reads.
export const useBookingStatus = () => useSWR(["booking-status"], api.getBookingStatus);
export const useAtRisk = () => useSWR(["at-risk"], api.getAtRisk);
export const useOverdueCases = () => useSWR(["overdue-cases"], api.getOverdueCases);
export const useCases = (a: Actor) => useSWR(["cases"], () => api.adminListCases(a));
export const useActiveAwards = (a: Actor) => useSWR(["active-awards"], () => api.adminActiveAwards(a));
export const useAuditLog = (a: Actor, table: string | null) =>
  useSWR(["audit", table ?? "all"], () => api.adminAuditLog(a, table));

/** Names for the ids stored in cases and the audit log (students, interviewers, the demo admin). */
export function usePeople() {
  const directory = useDirectory();
  const interviewers = useInterviewers();
  const names = new Map<string, string>([[ADMIN.id, "Admin"]]);
  for (const s of directory.data ?? []) names.set(s.student_id, s.name);
  for (const i of interviewers.data ?? []) names.set(i.id, i.name);
  return (id: string | null) => (id ? (names.get(id) ?? id) : "—");
}

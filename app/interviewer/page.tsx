import type { Metadata } from "next";
import { ScheduleScreen } from "@/components/screens/schedule";

export const metadata: Metadata = { title: "Schedule" };

export default function Page() {
  return <ScheduleScreen />;
}

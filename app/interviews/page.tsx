import type { Metadata } from "next";
import { InterviewsScreen } from "@/components/screens/interviews";

export const metadata: Metadata = { title: "Interviews" };

export default function Page() {
  return <InterviewsScreen />;
}

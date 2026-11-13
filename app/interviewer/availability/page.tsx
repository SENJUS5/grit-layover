import type { Metadata } from "next";
import { AvailabilityScreen } from "@/components/screens/availability";

export const metadata: Metadata = { title: "Availability" };

export default function Page() {
  return <AvailabilityScreen />;
}

import type { Metadata } from "next";
import { AdminAtRiskScreen } from "@/components/screens/admin-at-risk";

export const metadata: Metadata = { title: "At risk" };

export default function Page() {
  return <AdminAtRiskScreen />;
}

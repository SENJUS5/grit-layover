import type { Metadata } from "next";
import { AdminCasesScreen } from "@/components/screens/admin-cases";

export const metadata: Metadata = { title: "Cases" };

export default function Page() {
  return <AdminCasesScreen />;
}

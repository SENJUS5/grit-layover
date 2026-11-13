import type { Metadata } from "next";
import { AdminAuditScreen } from "@/components/screens/admin-audit";

export const metadata: Metadata = { title: "Audit log" };

export default function Page() {
  return <AdminAuditScreen />;
}

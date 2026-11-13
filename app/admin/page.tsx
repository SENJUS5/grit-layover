import type { Metadata } from "next";
import { AdminBookingsScreen } from "@/components/screens/admin-bookings";

export const metadata: Metadata = { title: "Bookings" };

export default function Page() {
  return <AdminBookingsScreen />;
}

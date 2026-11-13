import type { Metadata } from "next";
import { MilesScreen } from "@/components/screens/miles";

export const metadata: Metadata = { title: "Miles" };

export default function Page() {
  return <MilesScreen />;
}

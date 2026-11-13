import type { Metadata } from "next";
import { LeaderboardScreen } from "@/components/screens/leaderboard";

export const metadata: Metadata = { title: "Leaderboard" };

export default function Page() {
  return <LeaderboardScreen />;
}

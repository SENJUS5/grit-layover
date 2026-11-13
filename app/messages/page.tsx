import type { Metadata } from "next";
import { MessagesScreen } from "@/components/screens/messages";

export const metadata: Metadata = { title: "Messages" };

export default function Page() {
  return <MessagesScreen />;
}

import type { Metadata } from "next";
import { ProjectsScreen } from "@/components/screens/projects";

export const metadata: Metadata = { title: "Project review" };

export default function Page() {
  return <ProjectsScreen />;
}

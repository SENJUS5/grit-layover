import type { Metadata, Viewport } from "next";
import { Familjen_Grotesk } from "next/font/google";
import { AppShell } from "@/components/app-shell";
import { Providers } from "@/components/providers";
import "./globals.css";

const familjen = Familjen_Grotesk({
  variable: "--font-familjen",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: { default: "GRIT Layover", template: "%s · GRIT Layover" },
  description: "Book GRIT badge interviews, follow your journey, Miles and rank.",
};

export const viewport: Viewport = {
  themeColor: "#1e0404",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${familjen.variable} h-full antialiased`}>
      <body className="min-h-full font-sans">
        <Providers>
          <AppShell>{children}</AppShell>
        </Providers>
      </body>
    </html>
  );
}

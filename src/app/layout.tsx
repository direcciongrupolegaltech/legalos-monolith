import type { ReactNode } from "react";

export const metadata = {
  title: "LegalOS AI",
  description: "Plataforma jurídica modular con arquitectura Zero-Trust",
};

export default function RootLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}

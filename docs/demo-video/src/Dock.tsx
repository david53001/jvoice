import React from "react";
import { Img, staticFile } from "remotion";

// Dock geometry (comp coordinates). The Notes icon center is exported for cursor targeting.
export const DOCK = {
  bottom: 14,
  iconSize: 62,
  gap: 8,
  padding: 8,
  dividerW: 17, // 8px margin + 1px line + 8px margin
};

type DockEntry = { key: string; asset: string } | { key: "divider" };

const ENTRIES: DockEntry[] = [
  { key: "finder", asset: "app-finder.png" },
  { key: "safari", asset: "app-safari.png" },
  { key: "messages", asset: "app-messages.png" },
  { key: "notes", asset: "app-notes.png" },
  { key: "settings", asset: "app-settings.png" },
  { key: "divider" },
  { key: "trash", asset: "app-trash.png" },
];

export const NOTES_INDEX = ENTRIES.findIndex((e) => e.key === "notes");

const entryWidth = (e: DockEntry) => ("asset" in e ? DOCK.iconSize : DOCK.dividerW);

const totalWidth = () =>
  ENTRIES.reduce((acc, e) => acc + entryWidth(e), 0) +
  (ENTRIES.length - 1) * DOCK.gap +
  DOCK.padding * 2;

// Returns the center (x,y) of the dock entry at index, given comp dims.
export const dockIconCenter = (
  index: number,
  compW: number,
  compH: number,
): { x: number; y: number } => {
  const startX = (compW - totalWidth()) / 2 + DOCK.padding;
  let x = startX;
  for (let i = 0; i < index; i++) x += entryWidth(ENTRIES[i]) + DOCK.gap;
  x += entryWidth(ENTRIES[index]) / 2;
  const dockTop = compH - DOCK.bottom - (DOCK.iconSize + DOCK.padding * 2);
  const y = dockTop + DOCK.padding + DOCK.iconSize / 2;
  return { x, y };
};

export const Dock: React.FC<{ compW: number; compH: number; bounceNotes?: number }> = ({
  compW,
  compH,
  bounceNotes = 0,
}) => {
  return (
    <div
      style={{
        position: "absolute",
        bottom: DOCK.bottom,
        left: (compW - totalWidth()) / 2,
        width: totalWidth(),
        padding: DOCK.padding,
        borderRadius: 22,
        background: "rgba(160,160,170,0.26)",
        backdropFilter: "blur(40px) saturate(1.6)",
        WebkitBackdropFilter: "blur(40px) saturate(1.6)",
        border: "0.5px solid rgba(255,255,255,0.25)",
        boxShadow: "0 12px 40px rgba(0,0,0,0.35)",
        display: "flex",
        alignItems: "center",
        gap: DOCK.gap,
        zIndex: 40,
        boxSizing: "border-box",
      }}
    >
      {ENTRIES.map((e) =>
        "asset" in e ? (
          <Img
            key={e.key}
            src={staticFile(`system/${e.asset}`)}
            style={{
              width: DOCK.iconSize,
              height: DOCK.iconSize,
              transform: e.key === "notes" ? `translateY(${-bounceNotes}px)` : "none",
            }}
          />
        ) : (
          <div
            key="divider"
            style={{
              width: 1,
              height: DOCK.iconSize * 0.85,
              margin: "0 8px",
              background: "rgba(255,255,255,0.28)",
            }}
          />
        ),
      )}
    </div>
  );
};

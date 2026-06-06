import React from "react";

// Dock geometry (comp coordinates). The Notes icon center is exported for cursor targeting.
export const DOCK = {
  bottom: 18,
  iconSize: 58,
  gap: 12,
  padding: 10,
};

type IconDef = { key: string; render: React.ReactNode; label: string };

const FinderIcon = (
  <div
    style={{
      width: "100%",
      height: "100%",
      borderRadius: 13,
      background: "linear-gradient(180deg,#3da2ff 0%,#1a72e0 100%)",
      display: "flex",
    }}
  >
    <div style={{ width: "50%", background: "rgba(255,255,255,0.92)", borderTopLeftRadius: 13, borderBottomLeftRadius: 13 }} />
  </div>
);

const SafariIcon = (
  <div
    style={{
      width: "100%",
      height: "100%",
      borderRadius: 13,
      background: "radial-gradient(circle at 50% 40%, #e9f3fb 0%, #cfe6f7 60%, #9ec7ea 100%)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    <svg width="78%" height="78%" viewBox="0 0 40 40">
      <circle cx="20" cy="20" r="18" fill="#1488d8" />
      <circle cx="20" cy="20" r="15" fill="#e8f3fb" />
      <polygon points="20,8 24,20 20,32 16,20" fill="#fff" />
      <polygon points="20,8 24,20 20,20" fill="#f24" />
      <polygon points="20,32 16,20 20,20" fill="#bcd" />
    </svg>
  </div>
);

const MessagesIcon = (
  <div
    style={{
      width: "100%",
      height: "100%",
      borderRadius: 13,
      background: "linear-gradient(180deg,#5ef07a 0%,#16c63c 100%)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    <div
      style={{
        width: "62%",
        height: "54%",
        background: "#fff",
        borderRadius: "50% 50% 50% 8%",
      }}
    />
  </div>
);

// Notes app icon — yellow with lined paper.
const NotesIcon = (
  <div
    style={{
      width: "100%",
      height: "100%",
      borderRadius: 13,
      overflow: "hidden",
      background: "#fff",
      display: "flex",
      flexDirection: "column",
    }}
  >
    <div style={{ height: "26%", background: "linear-gradient(180deg,#ffe14d,#fdd835)" }} />
    <div style={{ flex: 1, background: "#fff", padding: "6px 7px", display: "flex", flexDirection: "column", gap: 4 }}>
      <div style={{ height: 2.5, background: "#e4c84a", borderRadius: 2, width: "85%" }} />
      <div style={{ height: 2.5, background: "#eee", borderRadius: 2 }} />
      <div style={{ height: 2.5, background: "#eee", borderRadius: 2 }} />
      <div style={{ height: 2.5, background: "#eee", borderRadius: 2, width: "70%" }} />
    </div>
  </div>
);

const SettingsGear = (
  <div
    style={{
      width: "100%",
      height: "100%",
      borderRadius: 13,
      background: "linear-gradient(180deg,#9aa0a6 0%,#5c6166 100%)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    <svg width="70%" height="70%" viewBox="0 0 40 40" fill="#e8eaed">
      <path d="M20 13a7 7 0 100 14 7 7 0 000-14zm0 4a3 3 0 110 6 3 3 0 010-6z" />
      <g>
        {Array.from({ length: 8 }).map((_, i) => (
          <rect key={i} x="18.5" y="3" width="3" height="6" rx="1" transform={`rotate(${i * 45} 20 20)`} />
        ))}
      </g>
    </svg>
  </div>
);

const TrashIcon = (
  <div
    style={{
      width: "100%",
      height: "100%",
      borderRadius: 13,
      background: "linear-gradient(180deg,#c7ccd1,#8d9399)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    <svg width="50%" height="60%" viewBox="0 0 24 30" fill="none" stroke="#3b3f44" strokeWidth="1.6">
      <rect x="4" y="6" width="16" height="22" rx="2" />
      <line x1="2" y1="6" x2="22" y2="6" />
      <line x1="9" y1="3" x2="15" y2="3" />
    </svg>
  </div>
);

const ICONS: IconDef[] = [
  { key: "finder", render: FinderIcon, label: "Finder" },
  { key: "safari", render: SafariIcon, label: "Safari" },
  { key: "messages", render: MessagesIcon, label: "Messages" },
  { key: "notes", render: NotesIcon, label: "Notes" },
  { key: "settings", render: SettingsGear, label: "System Settings" },
  { key: "trash", render: TrashIcon, label: "Trash" },
];

export const NOTES_INDEX = ICONS.findIndex((i) => i.key === "notes");

// Returns the center (x,y) of the dock icon at index, given comp dims.
export const dockIconCenter = (
  index: number,
  compW: number,
  compH: number,
): { x: number; y: number } => {
  const n = ICONS.length;
  const totalW = n * DOCK.iconSize + (n - 1) * DOCK.gap + DOCK.padding * 2;
  const startX = (compW - totalW) / 2 + DOCK.padding;
  const x = startX + index * (DOCK.iconSize + DOCK.gap) + DOCK.iconSize / 2;
  const dockTop = compH - DOCK.bottom - (DOCK.iconSize + DOCK.padding * 2);
  const y = dockTop + DOCK.padding + DOCK.iconSize / 2;
  return { x, y };
};

export const Dock: React.FC<{ compW: number; compH: number; bounceNotes?: number }> = ({
  compW,
  compH,
  bounceNotes = 0,
}) => {
  const n = ICONS.length;
  const totalW = n * DOCK.iconSize + (n - 1) * DOCK.gap + DOCK.padding * 2;
  return (
    <div
      style={{
        position: "absolute",
        bottom: DOCK.bottom,
        left: (compW - totalW) / 2,
        width: totalW,
        padding: DOCK.padding,
        borderRadius: 22,
        background: "rgba(180,180,190,0.28)",
        backdropFilter: "blur(34px)",
        WebkitBackdropFilter: "blur(34px)",
        border: "0.5px solid rgba(255,255,255,0.22)",
        boxShadow: "0 12px 40px rgba(0,0,0,0.35), inset 0 0 0 0.5px rgba(255,255,255,0.08)",
        display: "flex",
        gap: DOCK.gap,
        zIndex: 40,
      }}
    >
      {ICONS.map((ic, i) => (
        <div
          key={ic.key}
          style={{
            width: DOCK.iconSize,
            height: DOCK.iconSize,
            transform: ic.key === "notes" ? `translateY(${-bounceNotes}px)` : "none",
            filter: "drop-shadow(0 4px 6px rgba(0,0,0,0.30))",
          }}
        >
          {ic.render}
        </div>
      ))}
    </div>
  );
};

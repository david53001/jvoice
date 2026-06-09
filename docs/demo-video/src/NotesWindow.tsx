import React from "react";
import { Img, staticFile } from "remotion";
import { SYSTEM_FONT } from "./tokens";

const Tool: React.FC<{ src: string; h?: number; dim?: boolean }> = ({ src, h = 17, dim }) => (
  <Img
    src={staticFile(`system/${src}`)}
    style={{ height: h, width: "auto", display: "block", opacity: dim ? 0.55 : 0.9 }}
  />
);

// A macOS 14 dark-mode Notes window: unified dark toolbar (real Notes has no
// colored title bar), notes-list pane + editor pane, real SF Symbol toolbar.
export const NotesWindow: React.FC<{
  width: number;
  height: number;
  text: string;
  caretVisible: boolean;
  showCaret: boolean;
}> = ({ width, height, text, caretVisible, showCaret }) => {
  const listW = Math.round(width * 0.28);
  return (
    <div
      style={{
        width,
        height,
        borderRadius: 11,
        overflow: "hidden",
        background: "#1e1e1e",
        boxShadow:
          "0 30px 80px rgba(0,0,0,0.55), 0 0 0 0.5px rgba(255,255,255,0.14), inset 0 0.5px 0 rgba(255,255,255,0.10)",
        fontFamily: SYSTEM_FONT,
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* Unified toolbar — dark chrome, like the real app */}
      <div
        style={{
          height: 52,
          background: "rgba(44,42,40,0.98)",
          display: "flex",
          alignItems: "center",
          flexShrink: 0,
          borderBottom: "1px solid rgba(0,0,0,0.4)",
        }}
      >
        {/* traffic lights */}
        <div style={{ display: "flex", gap: 8, paddingLeft: 20, width: listW - 20, alignItems: "center", boxSizing: "border-box" }}>
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#ff5f57", boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.2)" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#febc2e", boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.2)" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#28c840", boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.2)" }} />
          <div style={{ marginLeft: 14, display: "flex", alignItems: "center", gap: 16 }}>
            <Tool src="nt-sidebar.png" h={16} dim />
          </div>
        </div>
        {/* over the list/editor boundary: window title + tools */}
        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "space-between", paddingRight: 16 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <span style={{ fontSize: 15, fontWeight: 700, color: "rgba(255,255,255,0.9)" }}>Notes</span>
            <div style={{ display: "flex", alignItems: "center", gap: 13, marginLeft: 4 }}>
              <Tool src="nt-list.png" h={14} />
              <Tool src="nt-grid.png" h={14} dim />
              <Tool src="nt-trash.png" h={15} dim />
            </div>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 17 }}>
            <Tool src="nt-compose.png" h={16} />
            <Tool src="nt-format.png" h={15} dim />
            <Tool src="nt-checklist.png" h={15} dim />
            <Tool src="nt-table.png" h={15} dim />
            <Tool src="nt-media.png" h={15} dim />
            <Tool src="nt-link.png" h={14} dim />
            <Tool src="nt-lock.png" h={14} dim />
            <Tool src="nt-share.png" h={15} dim />
            <Tool src="mb-search.png" h={14} dim />
          </div>
        </div>
      </div>

      <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
        {/* Notes list pane */}
        <div
          style={{
            width: listW,
            background: "#1e1e1e",
            borderRight: "1px solid rgba(255,255,255,0.09)",
            padding: "12px 8px",
            display: "flex",
            flexDirection: "column",
            gap: 2,
            boxSizing: "border-box",
          }}
        >
          <span style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.92)", margin: "2px 8px 8px" }}>
            Today
          </span>
          {/* selected note row */}
          <div
            style={{
              background: "#3f3f43",
              borderRadius: 8,
              padding: "9px 11px",
              display: "flex",
              flexDirection: "column",
              gap: 3,
            }}
          >
            <span style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.95)" }}>
              {text ? text.split(/[.!?]/)[0].slice(0, 26) : "New Note"}
            </span>
            <span style={{ fontSize: 11, color: "rgba(255,255,255,0.45)" }}>
              9:41 AM {text ? text.slice(0, 16) : "No additional text"}
            </span>
          </div>
          <span style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.92)", margin: "14px 8px 8px" }}>
            Yesterday
          </span>
          {["Team practice", "Grocery list", "Ideas"].map((t) => (
            <div key={t} style={{ display: "flex", flexDirection: "column", gap: 2, padding: "6px 11px" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.85)" }}>{t}</span>
              <span style={{ fontSize: 11, color: "rgba(255,255,255,0.40)" }}>Yesterday</span>
            </div>
          ))}
        </div>

        {/* Editor pane */}
        <div style={{ flex: 1, background: "#1e1e1e", padding: "20px 34px", position: "relative" }}>
          <div style={{ fontSize: 11, color: "rgba(255,255,255,0.35)", textAlign: "center", marginBottom: 22 }}>
            June 6, 2026 at 9:41 AM
          </div>
          <div
            style={{
              fontSize: 22,
              lineHeight: 1.5,
              color: "rgba(255,255,255,0.92)",
              fontWeight: 400,
              whiteSpace: "pre-wrap",
              minHeight: 30,
            }}
          >
            {text}
            {showCaret && (
              <span
                style={{
                  display: "inline-block",
                  width: 2,
                  height: 24,
                  background: "#f0b429",
                  marginLeft: 1,
                  verticalAlign: "text-bottom",
                  opacity: caretVisible ? 1 : 0,
                  transform: "translateY(4px)",
                }}
              />
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

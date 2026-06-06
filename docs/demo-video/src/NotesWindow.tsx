import React from "react";
import { SYSTEM_FONT } from "./tokens";

// A macOS Notes window. Sidebar + note area. The note body shows `text` with an
// optional blinking caret.
export const NotesWindow: React.FC<{
  width: number;
  height: number;
  text: string;
  caretVisible: boolean;
  showCaret: boolean;
}> = ({ width, height, text, caretVisible, showCaret }) => {
  return (
    <div
      style={{
        width,
        height,
        borderRadius: 12,
        overflow: "hidden",
        background: "#1e1e1e",
        boxShadow: "0 30px 80px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.08)",
        fontFamily: SYSTEM_FONT,
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* Title bar */}
      <div
        style={{
          height: 44,
          background: "#fbbf24",
          backgroundImage: "linear-gradient(180deg,#f7c948,#f0b429)",
          display: "flex",
          alignItems: "center",
          paddingLeft: 14,
          flexShrink: 0,
          borderBottom: "0.5px solid rgba(0,0,0,0.15)",
        }}
      >
        <div style={{ display: "flex", gap: 9 }}>
          <div style={{ width: 13, height: 13, borderRadius: "50%", background: "#ff5f57" }} />
          <div style={{ width: 13, height: 13, borderRadius: "50%", background: "#febc2e" }} />
          <div style={{ width: 13, height: 13, borderRadius: "50%", background: "#28c840" }} />
        </div>
      </div>
      <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
        {/* Sidebar */}
        <div
          style={{
            width: width * 0.26,
            background: "#2a2a2a",
            borderRight: "0.5px solid rgba(255,255,255,0.06)",
            padding: "14px 12px",
            display: "flex",
            flexDirection: "column",
            gap: 8,
          }}
        >
          <span style={{ fontSize: 13, fontWeight: 700, color: "rgba(255,255,255,0.5)", marginBottom: 4 }}>
            Notes
          </span>
          {/* selected note card */}
          <div
            style={{
              background: "#f7c948",
              borderRadius: 7,
              padding: "9px 11px",
              display: "flex",
              flexDirection: "column",
              gap: 3,
            }}
          >
            <span style={{ fontSize: 13, fontWeight: 700, color: "#1a1a1a" }}>New Note</span>
            <span style={{ fontSize: 11, color: "rgba(0,0,0,0.55)" }}>
              {text ? text.slice(0, 22) : "No additional text"}
            </span>
          </div>
          {["Team practice", "Grocery list", "Ideas"].map((t) => (
            <div key={t} style={{ display: "flex", flexDirection: "column", gap: 2, padding: "4px 11px" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.8)" }}>{t}</span>
              <span style={{ fontSize: 11, color: "rgba(255,255,255,0.35)" }}>Yesterday</span>
            </div>
          ))}
        </div>
        {/* Note body */}
        <div style={{ flex: 1, background: "#262626", padding: "26px 34px", position: "relative" }}>
          <div style={{ fontSize: 12, color: "rgba(255,255,255,0.35)", marginBottom: 18 }}>
            Today at 9:41 AM
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

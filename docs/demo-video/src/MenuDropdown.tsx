import React from "react";
import { MENU_ITEMS, SYSTEM_FONT } from "./tokens";

// macOS dark NSMenu dropdown. `highlightIndex` highlights one item row (Settings…).
export const MenuDropdown: React.FC<{
  x: number;
  y: number;
  highlightTitle?: string;
  reveal?: number; // 0..1 open progress
}> = ({ x, y, highlightTitle, reveal = 1 }) => {
  return (
    <div
      style={{
        position: "absolute",
        top: y,
        left: x,
        transform: `scale(${0.96 + 0.04 * reveal})`,
        transformOrigin: "top right",
        opacity: reveal,
        width: 200,
        padding: "5px 0",
        borderRadius: 8,
        background: "rgba(40,40,44,0.78)",
        backdropFilter: "blur(40px)",
        WebkitBackdropFilter: "blur(40px)",
        border: "0.5px solid rgba(255,255,255,0.12)",
        boxShadow: "0 18px 50px rgba(0,0,0,0.45), inset 0 0 0 0.5px rgba(255,255,255,0.06)",
        fontFamily: SYSTEM_FONT,
        zIndex: 200,
      }}
    >
      {MENU_ITEMS.map((it, i) => {
        if (it.type === "sep") {
          return (
            <div
              key={`sep-${i}`}
              style={{ height: 1, margin: "5px 12px", background: "rgba(255,255,255,0.12)" }}
            />
          );
        }
        const isHi = highlightTitle === it.title;
        return (
          <div
            key={it.title}
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              margin: "0 6px",
              padding: "3px 10px",
              borderRadius: 5,
              fontSize: 13,
              color: isHi ? "#fff" : "rgba(255,255,255,0.92)",
              background: isHi
                ? "linear-gradient(180deg,#3b82f6,#2563eb)"
                : "transparent",
            }}
          >
            <span>{it.title}</span>
          </div>
        );
      })}
    </div>
  );
};

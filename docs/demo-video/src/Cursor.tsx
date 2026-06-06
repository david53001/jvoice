import React from "react";

// Accurate macOS arrow pointer. Hotspot is the tip at the top-left (0,0).
export const Cursor: React.FC<{ x: number; y: number; scale?: number }> = ({
  x,
  y,
  scale = 1,
}) => {
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: 0,
        height: 0,
        transform: `scale(${scale})`,
        transformOrigin: "top left",
        zIndex: 9999,
        pointerEvents: "none",
        filter: "drop-shadow(0px 1px 1.5px rgba(0,0,0,0.45))",
      }}
    >
      <svg width="24" height="36" viewBox="0 0 24 36" fill="none">
        {/* black fill arrow with white outline — classic macOS cursor */}
        <path
          d="M1 1 L1 25.5 L7.2 19.6 L11.1 28.9 L14.6 27.4 L10.7 18.2 L19.3 18.1 Z"
          fill="#000000"
          stroke="#ffffff"
          strokeWidth="1.4"
          strokeLinejoin="round"
        />
      </svg>
    </div>
  );
};

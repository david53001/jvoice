import React from "react";
import { SYSTEM_FONT } from "./tokens";

// macOS menu bar height in the comp's coordinate space.
export const MENUBAR_H = 28;

// SF "waveform" approximation (idle JVoice icon): vertical bars of varying height.
const WaveformIcon: React.FC<{ color: string; size?: number }> = ({
  color,
  size = 17,
}) => {
  const bars = [0.42, 0.7, 1.0, 0.62, 0.86, 0.34];
  const bw = size / 11;
  return (
    <svg width={size} height={size} viewBox="0 0 22 22">
      {bars.map((h, i) => {
        const x = 2 + i * 3.1;
        const ht = h * 14;
        return (
          <rect
            key={i}
            x={x}
            y={11 - ht / 2}
            width={bw + 0.6}
            height={ht}
            rx={(bw + 0.6) / 2}
            fill={color}
          />
        );
      })}
    </svg>
  );
};

// SF "mic.fill" approximation for the recording state.
export const MicFillIcon: React.FC<{ color: string; size?: number }> = ({
  color,
  size = 17,
}) => (
  <svg width={size} height={size} viewBox="0 0 22 22">
    <rect x="8" y="2.5" width="6" height="11" rx="3" fill={color} />
    <path
      d="M5.5 10.5 a5.5 5.5 0 0 0 11 0"
      stroke={color}
      strokeWidth="1.6"
      fill="none"
      strokeLinecap="round"
    />
    <rect x="10.2" y="16" width="1.6" height="3" rx="0.8" fill={color} />
    <rect x="7.5" y="18.6" width="7" height="1.6" rx="0.8" fill={color} />
  </svg>
);

export const MenuBar: React.FC<{
  recording?: boolean;
  highlightJVoice?: boolean;
}> = ({ recording = false, highlightJVoice = false }) => {
  return (
    <div
      style={{
        position: "absolute",
        top: 0,
        left: 0,
        right: 0,
        height: MENUBAR_H,
        background: "rgba(28,28,32,0.55)",
        backdropFilter: "blur(28px)",
        WebkitBackdropFilter: "blur(28px)",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        paddingLeft: 12,
        paddingRight: 12,
        fontFamily: SYSTEM_FONT,
        color: "rgba(255,255,255,0.92)",
        fontSize: 13,
        borderBottom: "0.5px solid rgba(255,255,255,0.08)",
        zIndex: 50,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
        {/* Apple logo */}
        <svg width="15" height="18" viewBox="0 0 14 17" fill="rgba(255,255,255,0.92)">
          <path d="M11.6 9.1c0-1.6 1.3-2.4 1.4-2.4-0.8-1.1-2-1.3-2.4-1.3-1-0.1-2 0.6-2.5 0.6s-1.3-0.6-2.2-0.6c-1.1 0-2.2 0.7-2.7 1.7-1.2 2-0.3 5 0.8 6.6 0.6 0.8 1.2 1.7 2.1 1.6 0.8 0 1.2-0.5 2.2-0.5s1.3 0.5 2.2 0.5c0.9 0 1.5-0.8 2.1-1.6 0.7-1 0.9-1.9 0.9-2-0.1 0-1.8-0.7-1.8-2.6zM9.9 4.2c0.4-0.5 0.7-1.3 0.6-2-0.6 0-1.4 0.4-1.9 1-0.4 0.5-0.8 1.2-0.7 2 0.7 0 1.4-0.4 1.9-1z" />
        </svg>
        <span style={{ fontWeight: 700 }}>Notes</span>
        <span style={{ opacity: 0.92 }}>File</span>
        <span style={{ opacity: 0.92 }}>Edit</span>
        <span style={{ opacity: 0.92 }}>Format</span>
        <span style={{ opacity: 0.92 }}>View</span>
        <span style={{ opacity: 0.92 }}>Window</span>
        <span style={{ opacity: 0.92 }}>Help</span>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
        {/* JVoice status item */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            padding: "2px 5px",
            borderRadius: 5,
            background: highlightJVoice ? "rgba(255,255,255,0.18)" : "transparent",
          }}
        >
          {recording ? (
            <MicFillIcon color="rgb(255,69,58)" size={17} />
          ) : (
            <WaveformIcon color="rgba(255,255,255,0.92)" size={17} />
          )}
        </div>
        {/* battery */}
        <svg width="26" height="13" viewBox="0 0 26 13">
          <rect x="0.5" y="0.5" width="22" height="12" rx="3" fill="none" stroke="rgba(255,255,255,0.65)" />
          <rect x="2" y="2" width="16" height="9" rx="1.5" fill="rgba(255,255,255,0.92)" />
          <rect x="23.5" y="4" width="1.6" height="5" rx="0.8" fill="rgba(255,255,255,0.5)" />
        </svg>
        {/* wifi */}
        <svg width="17" height="13" viewBox="0 0 17 13" fill="rgba(255,255,255,0.92)">
          <path d="M8.5 11.5l2-2.4a3 3 0 0 0-4 0z" />
          <path d="M8.5 6.2a6.4 6.4 0 0 1 4.4 1.8l1.3-1.5a8.5 8.5 0 0 0-11.4 0l1.3 1.5A6.4 6.4 0 0 1 8.5 6.2z" opacity="0.85" />
          <path d="M8.5 2.2a10.5 10.5 0 0 1 7 2.7l1.3-1.5a12.6 12.6 0 0 0-16.6 0L1.5 4.9A10.5 10.5 0 0 1 8.5 2.2z" opacity="0.7" />
        </svg>
        {/* control center */}
        <svg width="16" height="13" viewBox="0 0 16 13" fill="none" stroke="rgba(255,255,255,0.85)" strokeWidth="1.2">
          <rect x="1" y="2" width="14" height="4" rx="2" />
          <rect x="1" y="7.5" width="14" height="4" rx="2" />
          <circle cx="5" cy="4" r="1.4" fill="rgba(255,255,255,0.85)" stroke="none" />
          <circle cx="11" cy="9.5" r="1.4" fill="rgba(255,255,255,0.85)" stroke="none" />
        </svg>
        <span style={{ fontSize: 13, opacity: 0.92 }}>Fri 9:41 AM</span>
      </div>
    </div>
  );
};

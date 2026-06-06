import React from "react";
import { HUD, SYSTEM_FONT } from "./tokens";

const rgba = (col: { r: number; g: number; b: number }, a: number) =>
  `rgba(${Math.round(col.r * 255)}, ${Math.round(col.g * 255)}, ${Math.round(col.b * 255)}, ${a})`;

// SF mic.fill
const MicGlyph: React.FC<{ color: string }> = ({ color }) => (
  <svg width="13" height="13" viewBox="0 0 22 22">
    <rect x="8" y="2.5" width="6" height="11" rx="3" fill={color} />
    <path d="M5.5 10.5 a5.5 5.5 0 0 0 11 0" stroke={color} strokeWidth="1.7" fill="none" strokeLinecap="round" />
    <rect x="10.2" y="16" width="1.6" height="3" rx="0.8" fill={color} />
    <rect x="7.5" y="18.6" width="7" height="1.6" rx="0.8" fill={color} />
  </svg>
);

// SF waveform.path
const WaveformPathGlyph: React.FC<{ color: string }> = ({ color }) => {
  const bars = [0.4, 0.72, 1.0, 0.55, 0.85, 0.32];
  return (
    <svg width="14" height="14" viewBox="0 0 22 22">
      {bars.map((h, i) => {
        const ht = h * 13;
        return (
          <rect key={i} x={3 + i * 2.9} y={11 - ht / 2} width="1.7" height={ht} rx="0.85" fill={color} />
        );
      })}
    </svg>
  );
};

const CheckGlyph: React.FC<{ color: string }> = ({ color }) => (
  <svg width="13" height="13" viewBox="0 0 22 22">
    <circle cx="11" cy="11" r="9" fill="none" stroke={color} strokeWidth="1.7" />
    <path d="M6.8 11.3 l2.7 2.7 l5-5.6" stroke={color} strokeWidth="1.9" fill="none" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

// The animated orbital ring: pulsing aura + spinning trimmed arc + center glyph.
const OrbitalRing: React.FC<{
  accent: { r: number; g: number; b: number };
  accentCss: string;
  glyph: React.ReactNode;
  t: number; // seconds
}> = ({ accent, accentCss, glyph, t }) => {
  const rot = ((t % 4.0) / 4.0) * 360; // one rotation / 4s
  const pulse = 0.9 + 0.15 * (0.5 - 0.5 * Math.cos((t / 1.8) * Math.PI)); // 0.9..1.05, 1.8s autoreverse

  // Arc: a 28x28 circle stroked for 28% of its circumference (trim 0..0.28).
  const R = 14;
  const circ = 2 * Math.PI * R;
  return (
    <div style={{ position: "relative", width: 36, height: 36 }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: "50%",
          background: `radial-gradient(circle, ${rgba(accent, 0.18)} 0%, transparent 60%)`,
          transform: `scale(${pulse})`,
        }}
      />
      <svg
        width="36"
        height="36"
        viewBox="0 0 36 36"
        style={{
          position: "absolute",
          inset: 0,
          transform: `rotate(${rot}deg)`,
          filter: `drop-shadow(0 0 3px ${rgba(accent, 0.85)}) drop-shadow(0 0 6px ${rgba(accent, 0.4)})`,
        }}
      >
        <circle
          cx="18"
          cy="18"
          r={R}
          fill="none"
          stroke={accentCss}
          strokeWidth="1.5"
          strokeLinecap="round"
          strokeDasharray={`${circ * 0.28} ${circ}`}
        />
      </svg>
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          filter: `drop-shadow(0 0 4px ${rgba(accent, 0.6)})`,
        }}
      >
        {glyph}
      </div>
    </div>
  );
};

const StaticDisc: React.FC<{
  accent: { r: number; g: number; b: number };
  glyph: React.ReactNode;
}> = ({ accent, glyph }) => (
  <div
    style={{
      width: 28,
      height: 28,
      borderRadius: "50%",
      background: rgba(accent, 0.12),
      border: `1px solid ${rgba(accent, 0.3)}`,
      boxShadow: `0 0 6px ${rgba(accent, 0.22)}`,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    {glyph}
  </div>
);

type PillKind = "recording" | "transcribing" | "done";

const pillShell = (accent: { r: number; g: number; b: number }): React.CSSProperties => ({
  minWidth: HUD.pillW,
  minHeight: HUD.pillH,
  borderRadius: HUD.radius,
  background: HUD.bg,
  border: `1px solid ${rgba(accent, 0.22)}`,
  padding: "7px 10px",
  display: "flex",
  alignItems: "center",
  gap: 10,
  boxShadow: [
    `0 0 16px ${rgba(accent, 0.18)}`,
    `0 0 32px ${rgba(accent, 0.07)}`,
    `0 6px 12px rgba(0,0,0,0.35)`,
  ].join(", "),
  fontFamily: SYSTEM_FONT,
  position: "relative",
  overflow: "hidden",
});

const topGradient = (accent: { r: number; g: number; b: number }): React.CSSProperties => ({
  position: "absolute",
  inset: 0,
  borderRadius: HUD.radius,
  background: `linear-gradient(135deg, ${rgba(accent, 0.06)} 0%, transparent 50%)`,
  pointerEvents: "none",
});

export const HudPill: React.FC<{ kind: PillKind; t: number }> = ({ kind, t }) => {
  if (kind === "recording") {
    const a = HUD.recording;
    return (
      <div style={pillShell(a.accent)}>
        <div style={topGradient(a.accent)} />
        <OrbitalRing accent={a.accent} accentCss={a.accentCss} glyph={<MicGlyph color={a.accentCss} />} t={t} />
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span
            style={{
              fontSize: 12,
              fontWeight: 600,
              color: a.text,
              textShadow: `0 0 6px ${rgba(a.accent, 0.55)}, 0 0 18px ${rgba(a.accent, 0.2)}`,
            }}
          >
            {a.title}
          </span>
          <span style={{ fontSize: 10, fontWeight: 500, color: a.sub }}>{a.subtitle}</span>
        </div>
        <div style={{ flex: 1 }} />
        {/* stop button */}
        <div
          style={{
            width: 22,
            height: 22,
            borderRadius: 6,
            background: "rgba(255,96,96,0.12)",
            border: "1px solid rgba(255,96,96,0.30)",
            boxShadow: "0 0 4px rgba(255,96,96,0.20)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div
            style={{
              width: 7,
              height: 7,
              borderRadius: 2,
              background: HUD.stopRed,
              boxShadow: "0 0 3px rgba(255,96,96,0.8)",
            }}
          />
        </div>
      </div>
    );
  }

  if (kind === "transcribing") {
    const a = HUD.transcribing;
    return (
      <div style={pillShell(a.accent)}>
        <div style={topGradient(a.accent)} />
        <OrbitalRing accent={a.accent} accentCss={a.accentCss} glyph={<WaveformPathGlyph color={a.accentCss} />} t={t} />
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span
            style={{
              fontSize: 12,
              fontWeight: 600,
              color: a.text,
              textShadow: `0 0 6px ${rgba(a.accent, 0.55)}, 0 0 18px ${rgba(a.accent, 0.2)}`,
            }}
          >
            {a.title}
          </span>
          <span style={{ fontSize: 10, fontWeight: 500, color: a.sub }}>{a.subtitle}</span>
        </div>
        <div style={{ flex: 1 }} />
      </div>
    );
  }

  // done
  const a = HUD.done;
  return (
    <div style={pillShell(a.accent)}>
      <div style={topGradient(a.accent)} />
      <StaticDisc accent={a.accent} glyph={<CheckGlyph color={a.accentCss} />} />
      <span
        style={{
          fontSize: 12,
          fontWeight: 600,
          color: a.text,
          textShadow: `0 0 6px ${rgba(a.accent, 0.55)}, 0 0 18px ${rgba(a.accent, 0.2)}`,
        }}
      >
        {a.headline}
      </span>
      <div style={{ flex: 1 }} />
    </div>
  );
};

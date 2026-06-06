import React from "react";
import { HUD } from "./tokens";

// A smooth live waveform that sits above the recording pill. `t` is seconds,
// `energy` 0..1 modulates amplitude (rises while "speaking").
export const Waveform: React.FC<{ t: number; energy: number; width: number }> = ({
  t,
  energy,
  width,
}) => {
  const bars = 48;
  const accent = HUD.recording.accentCss;
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 3,
        height: 60,
        width,
      }}
    >
      {Array.from({ length: bars }).map((_, i) => {
        // layered sines for an organic, smooth motion
        const p = i / bars;
        const wave =
          0.5 +
          0.5 *
            Math.sin(t * 6.5 + i * 0.55) *
            Math.sin(t * 2.1 + i * 0.21 + 0.6) *
            Math.cos(t * 3.3 - i * 0.13);
        const env = Math.sin(p * Math.PI); // taper at edges
        const h = 4 + Math.abs(wave) * env * 52 * (0.25 + 0.75 * energy);
        return (
          <div
            key={i}
            style={{
              width: 3,
              height: h,
              borderRadius: 2,
              background: accent,
              opacity: 0.55 + 0.45 * env,
              boxShadow: `0 0 6px ${accent}`,
            }}
          />
        );
      })}
    </div>
  );
};

import React from "react";
import { Img, staticFile } from "remotion";
import { SYSTEM_FONT } from "./tokens";

// macOS menu bar height (macOS 14 at 1x).
export const MENUBAR_H = 25;

const MenuGlyph: React.FC<{ src: string; h: number; style?: React.CSSProperties }> = ({
  src,
  h,
  style,
}) => (
  <Img
    src={staticFile(`system/${src}`)}
    style={{ height: h, width: "auto", display: "block", ...style }}
  />
);

export const MenuBar: React.FC<{
  recording?: boolean;
  transcribing?: boolean;
  highlightJVoice?: boolean;
}> = ({ recording = false, transcribing = false, highlightJVoice = false }) => {
  return (
    <div
      style={{
        position: "absolute",
        top: 0,
        left: 0,
        right: 0,
        height: MENUBAR_H,
        background: "rgba(24,24,28,0.62)",
        backdropFilter: "blur(50px) saturate(1.6)",
        WebkitBackdropFilter: "blur(50px) saturate(1.6)",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        paddingLeft: 16,
        paddingRight: 16,
        fontFamily: SYSTEM_FONT,
        color: "rgba(255,255,255,0.95)",
        fontSize: 13,
        zIndex: 50,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 19 }}>
        <MenuGlyph src="mb-apple.png" h={16} style={{ marginTop: -1 }} />
        <span style={{ fontWeight: 600 }}>Notes</span>
        <span>File</span>
        <span>Edit</span>
        <span>Format</span>
        <span>View</span>
        <span>Window</span>
        <span>Help</span>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
        {/* JVoice status item — the product's "J" mark (template-style white) */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            minWidth: 24,
            height: MENUBAR_H - 4,
            padding: "0 4px",
            borderRadius: 4,
            background: highlightJVoice ? "rgba(255,255,255,0.22)" : "transparent",
          }}
        >
          {recording ? (
            <MenuGlyph src="mb-mic-recording.png" h={15} />
          ) : transcribing ? (
            <MenuGlyph src="mb-waveform-transcribing.png" h={14} />
          ) : (
            <span style={{ fontWeight: 700, fontSize: 15, lineHeight: 1 }}>J</span>
          )}
        </div>
        <MenuGlyph src="mb-battery.png" h={12} />
        <MenuGlyph src="mb-wifi.png" h={12} />
        <MenuGlyph src="mb-search.png" h={13} />
        <MenuGlyph src="mb-controlcenter.png" h={13} />
        <span style={{ fontSize: 13 }}>Fri Jun 6  9:41 AM</span>
      </div>
    </div>
  );
};

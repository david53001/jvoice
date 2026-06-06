import React from "react";
import { SP, SYSTEM_FONT } from "./tokens";

// Native SettingsView frame is 320x520. We render at the native pt scale and let
// the caller scale the whole panel up for legibility, preserving exact proportions.

const Section: React.FC<{
  title: string;
  accent: string;
  children: React.ReactNode;
}> = ({ title, accent, children }) => (
  <div
    style={{
      background: SP.sectionBg,
      border: `1px solid ${SP.border}`,
      borderRadius: 10,
      overflow: "hidden",
    }}
  >
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 7,
        padding: "7px 12px 6px",
      }}
    >
      <div
        style={{
          width: 5,
          height: 5,
          borderRadius: "50%",
          background: accent,
          boxShadow: `0 0 3px ${accent}`,
        }}
      />
      <span
        style={{
          fontSize: 9.5,
          fontWeight: 700,
          letterSpacing: 0.7,
          color: SP.headerText,
        }}
      >
        {title.toUpperCase()}
      </span>
    </div>
    <div style={{ height: 0.5, background: SP.border }} />
    <div style={{ padding: "9px 12px" }}>{children}</div>
  </div>
);

const Segmented: React.FC<{
  options: string[];
  selected: number;
  accent?: string;
}> = ({ options, selected }) => (
  <div
    style={{
      display: "flex",
      background: "rgba(255,255,255,0.06)",
      borderRadius: 6,
      padding: 1.5,
      gap: 1.5,
    }}
  >
    {options.map((o, i) => (
      <div
        key={o}
        style={{
          flex: 1,
          textAlign: "center",
          fontSize: 11,
          fontWeight: i === selected ? 600 : 500,
          padding: "4px 0",
          borderRadius: 5,
          color: i === selected ? "#fff" : "rgba(255,255,255,0.7)",
          background: i === selected ? "rgba(120,120,128,0.55)" : "transparent",
          boxShadow: i === selected ? "0 1px 2px rgba(0,0,0,0.3)" : "none",
        }}
      >
        {o}
      </div>
    ))}
  </div>
);

export const SettingsPanel: React.FC = () => {
  return (
    <div
      style={{
        width: 320,
        background: SP.panelBg,
        fontFamily: SYSTEM_FONT,
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div
        style={{
          padding: "14px 16px",
          display: "flex",
          flexDirection: "column",
          gap: 8,
        }}
      >
        {/* Header */}
        <div style={{ display: "flex", flexDirection: "column", gap: 3, paddingBottom: 4 }}>
          <span style={{ fontSize: 17, fontWeight: 700, color: "#fff" }}>JVoice</span>
          <span style={{ fontSize: 11, color: SP.white45 }}>
            Menu bar transcription controls
          </span>
        </div>

        {/* Last Transcript */}
        <Section title="Last Transcript" accent={SP.blue}>
          <div
            style={{
              fontSize: 11,
              color: SP.white75,
              background: SP.inputBg,
              border: `1px solid ${SP.border}`,
              borderRadius: 6,
              padding: "7px 8px",
              minHeight: 40,
              lineHeight: 1.4,
            }}
          >
            Hey! Can we move practice to Thursday at 5?
          </div>
          <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
            <div
              style={{
                fontSize: 11,
                fontWeight: 600,
                color: SP.blue,
                padding: "5px 12px",
                borderRadius: 7,
                background: "rgba(74,158,255,0.12)",
                border: "1px solid rgba(74,158,255,0.28)",
              }}
            >
              Fix
            </div>
            <div
              style={{
                fontSize: 11,
                fontWeight: 600,
                color: SP.gray,
                padding: "5px 12px",
                borderRadius: 7,
                background: "rgba(135,135,135,0.12)",
                border: "1px solid rgba(135,135,135,0.28)",
              }}
            >
              Revert
            </div>
          </div>
        </Section>

        {/* Keyboard Shortcut */}
        <Section title="Keyboard Shortcut" accent={SP.gray}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <span style={{ fontSize: 11, color: SP.white75 }}>Toggle Recording:</span>
            <div
              style={{
                fontSize: 11,
                color: SP.white75,
                padding: "3px 10px",
                borderRadius: 5,
                background: SP.inputBg,
                border: `1px solid ${SP.border}`,
              }}
            >
              ⌥ Space
            </div>
          </div>
          <div style={{ fontSize: 10, color: SP.white35, marginTop: 8 }}>Default: ⌥ Space</div>
        </Section>

        {/* Language */}
        <Section title="Language" accent={SP.indigo}>
          <Segmented options={["English", "Romanian"]} selected={0} />
        </Section>

        {/* Voice Style */}
        <Section title="Voice Style" accent={SP.purple}>
          <Segmented options={["Casual", "Formal", "Very Casual"]} selected={0} />
        </Section>

        {/* Processing */}
        <Section title="Processing" accent={SP.teal}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
              <span style={{ fontSize: 12, fontWeight: 500, color: SP.white85 }}>
                Remove Filler Words
              </span>
              <span style={{ fontSize: 10, color: SP.white38 }}>
                Strip um, uh, er, ah, hmm from output
              </span>
            </div>
            {/* macOS switch (on) */}
            <div
              style={{
                width: 32,
                height: 19,
                borderRadius: 10,
                background: SP.teal,
                position: "relative",
                flexShrink: 0,
              }}
            >
              <div
                style={{
                  position: "absolute",
                  top: 1.5,
                  left: 15,
                  width: 16,
                  height: 16,
                  borderRadius: "50%",
                  background: "#fff",
                  boxShadow: "0 1px 2px rgba(0,0,0,0.3)",
                }}
              />
            </div>
          </div>
        </Section>

        {/* Whisper Model */}
        <Section title="Whisper Model" accent={SP.cyan}>
          <Segmented options={["Tiny", "Base", "Small", "Large"]} selected={0} />
        </Section>

        {/* Custom Words */}
        <Section title="Custom Words" accent={SP.orange}>
          <div style={{ display: "flex", flexDirection: "column", gap: 4, marginBottom: 8 }}>
            {["JVoice", "Thursday"].map((w) => (
              <div
                key={w}
                style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}
              >
                <span style={{ fontSize: 11, color: SP.white75 }}>{w}</span>
                <div style={{ color: "rgba(255,96,96,0.8)", fontSize: 13 }}>⊖</div>
              </div>
            ))}
          </div>
          <div style={{ display: "flex", gap: 6 }}>
            <div
              style={{
                flex: 1,
                fontSize: 11,
                color: SP.white40,
                padding: "5px 8px",
                borderRadius: 6,
                background: SP.inputBg,
                border: `1px solid ${SP.border}`,
              }}
            >
              Add word (e.g. VS Code)
            </div>
            <div
              style={{
                fontSize: 11,
                fontWeight: 600,
                color: SP.orange,
                padding: "5px 12px",
                borderRadius: 7,
                background: "rgba(240,160,48,0.12)",
                border: "1px solid rgba(240,160,48,0.28)",
              }}
            >
              Add
            </div>
          </div>
        </Section>

        {/* Stats */}
        <Section title="Stats" accent={SP.green}>
          <div style={{ display: "flex", alignItems: "center" }}>
            <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 3 }}>
              <span
                style={{
                  fontSize: 26,
                  fontWeight: 700,
                  color: "#fff",
                  fontVariantNumeric: "tabular-nums",
                  textShadow: "0 0 8px rgba(74,158,255,0.45), 0 0 20px rgba(74,158,255,0.18)",
                }}
              >
                1,284
              </span>
              <span style={{ fontSize: 10, color: SP.white38 }}>total words</span>
            </div>
            <div style={{ width: 0.5, height: 44, background: SP.border }} />
            <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 3 }}>
              <span
                style={{
                  fontSize: 26,
                  fontWeight: 700,
                  color: "#fff",
                  fontVariantNumeric: "tabular-nums",
                  textShadow: "0 0 8px rgba(74,222,160,0.45), 0 0 20px rgba(74,222,160,0.18)",
                }}
              >
                118
              </span>
              <span style={{ fontSize: 10, color: SP.white38 }}>avg WPM</span>
            </div>
          </div>
        </Section>

        {/* Footer */}
        <div style={{ display: "flex", justifyContent: "space-between" }}>
          <div
            style={{
              fontSize: 11,
              fontWeight: 600,
              color: SP.red,
              padding: "5px 12px",
              borderRadius: 7,
              background: "rgba(255,96,96,0.10)",
              border: "1px solid rgba(255,96,96,0.24)",
            }}
          >
            Restore Default Settings
          </div>
          <div
            style={{
              fontSize: 11,
              fontWeight: 600,
              color: SP.red,
              padding: "5px 12px",
              borderRadius: 7,
              background: "rgba(255,96,96,0.10)",
              border: "1px solid rgba(255,96,96,0.24)",
            }}
          >
            Quit JVoice
          </div>
        </div>
      </div>
    </div>
  );
};

// Wraps the panel in a macOS titled window chrome ("Settings" title + traffic lights).
export const SettingsWindow: React.FC<{ scale?: number }> = ({ scale = 1 }) => {
  return (
    <div
      style={{
        transform: `scale(${scale})`,
        transformOrigin: "center center",
        borderRadius: 12,
        overflow: "hidden",
        boxShadow: "0 30px 80px rgba(0,0,0,0.55), 0 0 0 0.5px rgba(255,255,255,0.08)",
        fontFamily: SYSTEM_FONT,
      }}
    >
      {/* Title bar */}
      <div
        style={{
          height: 38,
          background: "rgba(40,40,46,0.92)",
          display: "flex",
          alignItems: "center",
          paddingLeft: 13,
          position: "relative",
          borderBottom: "0.5px solid rgba(0,0,0,0.5)",
        }}
      >
        <div style={{ display: "flex", gap: 8 }}>
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#ff5f57" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#febc2e" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#28c840" }} />
        </div>
        <span
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            textAlign: "center",
            fontSize: 13,
            fontWeight: 600,
            color: "rgba(255,255,255,0.85)",
          }}
        >
          Settings
        </span>
      </div>
      <SettingsPanel />
    </div>
  );
};

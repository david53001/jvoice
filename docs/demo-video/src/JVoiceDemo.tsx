import React from "react";
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";
import { MenuBar, MENUBAR_H } from "./Desktop";
import { Dock, dockIconCenter, NOTES_INDEX } from "./Dock";
import { Cursor } from "./Cursor";
import { NotesWindow } from "./NotesWindow";
import { HudPill } from "./HudPill";
import { Waveform } from "./Waveform";
import { MenuDropdown } from "./MenuDropdown";
import { SettingsWindow } from "./SettingsPanel";
import { charsVisible } from "./typing";
import { RAW_SPEECH, CLEAN_TEXT, END_CAPTION, SYSTEM_FONT } from "./tokens";

const W = 1600;
const H = 1000;

// Scene boundaries (frames @30fps)
const S = {
  notesClick: 60, // cursor reaches dock + click
  notesOpen: 75,
  noteFocusClick: 105,
  recStart: 135,
  recEnd: 270,
  transStart: 285,
  transEnd: 330,
  typeStart: 345,
  typeEnd: 420,
  doneStart: 420,
  pillFade: 450,
  menuCursorStart: 450,
  menuOpen: 480,
  settingsClick: 510,
  settingsOpen: 525,
};

// Notes window geometry
const NOTE_W = 920;
const NOTE_H = 600;
const NOTE_X = (W - NOTE_W) / 2;
const NOTE_Y = MENUBAR_H + 60;

export const JVoiceDemo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;

  const notesCenter = dockIconCenter(NOTES_INDEX, W, H);
  // JVoice menu-bar icon location (right cluster). Time label is far right; JVoice
  // status item sits left of the system icons. Approximate its center.
  const jvoiceIcon = { x: W - 226, y: MENUBAR_H / 2 };

  // ---------- CURSOR PATH ----------
  // Start off to the side, glide to Notes dock icon by S.notesClick, then to note
  // body by S.noteFocusClick, idle, then to menu-bar icon, then to Settings row.
  const cursor = getCursorPos(frame, fps, notesCenter, jvoiceIcon);

  // ---------- NOTES WINDOW open spring ----------
  const notesOpenSpr = spring({
    frame: frame - S.notesOpen,
    fps,
    config: { damping: 16, stiffness: 130, mass: 0.8 },
  });
  const notesVisible = frame >= S.notesOpen;
  const notesScale = interpolate(notesOpenSpr, [0, 1], [0.86, 1]);
  const notesOpacity = interpolate(notesOpenSpr, [0, 1], [0, 1]);

  // ---------- CARET ----------
  const caretActive = frame >= S.noteFocusClick;
  const caretBlink = Math.floor(((frame - S.noteFocusClick) / fps) / 0.53) % 2 === 0;

  // ---------- TYPED TEXT ----------
  const typedCount =
    frame < S.typeStart
      ? 0
      : charsVisible(CLEAN_TEXT, frame - S.typeStart, S.typeEnd - S.typeStart);
  const typedText = CLEAN_TEXT.slice(0, typedCount);
  const noteText = frame < S.typeStart ? "" : typedText;
  // caret shown while focused & before/while typing & shortly after
  const showCaret = caretActive && frame < S.menuCursorStart;

  // ---------- HUD PILL ----------
  let pillKind: "recording" | "transcribing" | "done" | null = null;
  if (frame >= S.recStart && frame < S.transStart) pillKind = "recording";
  else if (frame >= S.transStart && frame < S.transEnd) pillKind = "transcribing";
  else if (frame >= S.doneStart && frame < S.pillFade + 30) pillKind = "done";

  // pill entrance spring (per phase)
  const pillEnterFrame =
    pillKind === "recording"
      ? frame - S.recStart
      : pillKind === "transcribing"
        ? frame - S.transStart
        : frame - S.doneStart;
  const pillSpr = spring({
    frame: pillEnterFrame,
    fps,
    config: { damping: 15, stiffness: 150, mass: 0.7 },
  });
  // pill fade-out at the very end of done
  const pillFadeOut =
    pillKind === "done"
      ? interpolate(frame, [S.pillFade + 12, S.pillFade + 30], [1, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        })
      : 1;
  const pillOpacity = interpolate(pillSpr, [0, 1], [0, 1]) * pillFadeOut;
  const pillY = interpolate(pillSpr, [0, 1], [40, 0]);

  // ---------- RECORDING WAVEFORM + CAPTION ----------
  const recLocal = frame - S.recStart;
  const recDur = S.recEnd - S.recStart;
  // energy ramps up after pill appears, sustains, dips at end
  const energy = interpolate(
    recLocal,
    [0, 25, recDur - 30, recDur],
    [0.15, 1, 1, 0.3],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  const captionCount =
    frame < S.recStart + 12
      ? 0
      : charsVisible(RAW_SPEECH, frame - (S.recStart + 12), recDur - 24);
  const captionText = RAW_SPEECH.slice(0, Math.min(captionCount, RAW_SPEECH.length));
  const showRecordingExtras = frame >= S.recStart && frame < S.transStart;
  const recExtrasOpacity = interpolate(
    frame,
    [S.recStart, S.recStart + 10, S.transStart - 8, S.transStart],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  // ---------- MENU DROPDOWN ----------
  const menuReveal = spring({
    frame: frame - S.menuOpen,
    fps,
    config: { damping: 18, stiffness: 200, mass: 0.6 },
  });
  const menuVisible = frame >= S.menuOpen && frame < S.settingsOpen + 6;
  const menuFade = interpolate(frame, [S.settingsOpen, S.settingsOpen + 6], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const highlightSettings = frame >= S.settingsClick - 12;

  // recording icon in menu bar active during recording/transcribing
  const menuBarRecording = frame >= S.recStart && frame < S.transEnd;
  const highlightJVoiceMB = frame >= S.menuCursorStart - 6 && frame < S.settingsOpen;

  // ---------- SETTINGS WINDOW ----------
  const settingsSpr = spring({
    frame: frame - S.settingsOpen,
    fps,
    config: { damping: 17, stiffness: 130, mass: 0.85 },
  });
  const settingsVisible = frame >= S.settingsOpen;
  const settingsScale = interpolate(settingsSpr, [0, 1], [0.82, 1.04]);
  const settingsOpacity = interpolate(settingsSpr, [0, 1], [0, 1]);

  // ---------- END CAPTION ----------
  const endCapOpacity = interpolate(frame, [555, 575], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Notes dock bounce on launch
  const bounce =
    frame >= S.notesClick && frame < S.notesOpen
      ? Math.abs(Math.sin((frame - S.notesClick) / 6)) * 14
      : 0;

  // click ripple on the dock icon / note / menu
  const clickRipple = getClickRipple(frame, cursor);

  return (
    <AbsoluteFill style={{ background: wallpaper(), overflow: "hidden" }}>
      {/* Wallpaper vignette */}
      <AbsoluteFill style={{ background: "radial-gradient(120% 90% at 50% 0%, transparent 40%, rgba(0,0,0,0.35) 100%)" }} />

      <MenuBar recording={menuBarRecording} highlightJVoice={highlightJVoiceMB} />

      {/* Notes window */}
      {notesVisible && (
        <div
          style={{
            position: "absolute",
            left: NOTE_X,
            top: NOTE_Y,
            transform: `scale(${notesScale})`,
            transformOrigin: "center 70%",
            opacity: notesOpacity,
          }}
        >
          <NotesWindow
            width={NOTE_W}
            height={NOTE_H}
            text={noteText}
            caretVisible={caretBlink}
            showCaret={showCaret}
          />
        </div>
      )}

      <Dock compW={W} compH={H} bounceNotes={bounce} />

      {/* HUD pill (bottom center) + recording extras */}
      {pillKind && (
        <div
          style={{
            position: "absolute",
            bottom: 190,
            left: 0,
            right: 0,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 22,
            opacity: pillOpacity,
            transform: `translateY(${pillY}px)`,
          }}
        >
          {showRecordingExtras && (
            <div style={{ opacity: recExtrasOpacity, display: "flex", flexDirection: "column", alignItems: "center", gap: 18 }}>
              <div
                style={{
                  fontFamily: SYSTEM_FONT,
                  fontSize: 21,
                  color: "rgba(255,255,255,0.88)",
                  background: "rgba(10,10,16,0.6)",
                  backdropFilter: "blur(14px)",
                  WebkitBackdropFilter: "blur(14px)",
                  padding: "10px 20px",
                  borderRadius: 14,
                  border: "0.5px solid rgba(255,255,255,0.12)",
                  maxWidth: 760,
                  textAlign: "center",
                  minHeight: 26,
                }}
              >
                {captionText}
                <span style={{ opacity: 0.5 }}>{captionText.length < RAW_SPEECH.length ? "▏" : ""}</span>
              </div>
              <Waveform t={t} energy={energy} width={440} />
            </div>
          )}
          <div style={{ transform: "scale(1.7)", transformOrigin: "center bottom" }}>
            <HudPill kind={pillKind} t={t} />
          </div>
        </div>
      )}

      {/* Menu dropdown from JVoice menu-bar icon */}
      {menuVisible && (
        <div style={{ opacity: menuFade }}>
          <MenuDropdown
            x={jvoiceIcon.x - 178}
            y={MENUBAR_H - 2}
            reveal={menuReveal}
            highlightTitle={highlightSettings ? "Settings…" : undefined}
          />
        </div>
      )}

      {/* Settings window (centered) */}
      {settingsVisible && (
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
          <div style={{ opacity: settingsOpacity, transform: `translateY(-40px) scale(${settingsScale})` }}>
            <SettingsWindow scale={1} />
          </div>
        </AbsoluteFill>
      )}

      {/* End caption — floating badge in the clear lower-left, above the dock */}
      {endCapOpacity > 0 && (
        <div
          style={{
            position: "absolute",
            bottom: 150,
            left: 90,
            opacity: endCapOpacity,
            fontFamily: SYSTEM_FONT,
            fontSize: 22,
            fontWeight: 600,
            color: "rgba(255,255,255,0.95)",
            background: "rgba(10,10,16,0.6)",
            backdropFilter: "blur(16px)",
            WebkitBackdropFilter: "blur(16px)",
            padding: "12px 22px",
            borderRadius: 16,
            border: "0.5px solid rgba(255,255,255,0.14)",
            boxShadow: "0 10px 40px rgba(0,0,0,0.45)",
            textShadow: "0 2px 10px rgba(0,0,0,0.6)",
            zIndex: 9990,
          }}
        >
          {END_CAPTION}
        </div>
      )}

      {/* Click ripple */}
      {clickRipple && (
        <div
          style={{
            position: "absolute",
            left: clickRipple.x - clickRipple.r,
            top: clickRipple.y - clickRipple.r,
            width: clickRipple.r * 2,
            height: clickRipple.r * 2,
            borderRadius: "50%",
            border: "2px solid rgba(255,255,255,0.7)",
            opacity: clickRipple.opacity,
            zIndex: 9998,
            pointerEvents: "none",
          }}
        />
      )}

      {/* Cursor (always on top) */}
      <Cursor x={cursor.x} y={cursor.y} scale={cursor.scale} />
    </AbsoluteFill>
  );
};

// ---------- helpers ----------

function wallpaper(): string {
  // tasteful Sonoma-like gradient
  return "linear-gradient(160deg, #3a1d6e 0%, #5b2a8c 22%, #8a3b9e 45%, #c2557e 68%, #e8845c 88%, #f0a85f 100%)";
}

type Pt = { x: number; y: number; scale: number };

function getCursorPos(
  frame: number,
  fps: number,
  notes: { x: number; y: number },
  jvoice: { x: number; y: number },
): Pt {
  // Key waypoints
  const start = { x: 300, y: 760 };
  const noteBody = { x: NOTE_X + NOTE_W * 0.55, y: NOTE_Y + NOTE_H * 0.5 };
  const settingsRow = { x: jvoice.x - 90, y: MENUBAR_H + 64 }; // over "Settings…" row

  // segment 1: start -> notes dock icon  (frame 8..S.notesClick)
  // hold during open
  // segment 2: notes dock -> note body (S.notesOpen+6 .. S.noteFocusClick)
  // idle through recording/transcribing/typing
  // segment 3: note body -> jvoice menu-bar icon (S.menuCursorStart .. S.menuOpen)
  // segment 4: jvoice icon -> settings row (S.menuOpen+4 .. S.settingsClick)
  // then to center toward settings window briefly

  const seg = (
    from: { x: number; y: number },
    to: { x: number; y: number },
    f0: number,
    f1: number,
  ): { x: number; y: number } => {
    const p = interpolate(frame, [f0, f1], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.33, 0.0, 0.2, 1.0),
    });
    return { x: from.x + (to.x - from.x) * p, y: from.y + (to.y - from.y) * p };
  };

  let pos: { x: number; y: number };
  let scale = 1;

  if (frame < S.notesOpen + 6) {
    pos = seg(start, notes, 8, S.notesClick);
  } else if (frame < S.menuCursorStart) {
    pos = seg(notes, noteBody, S.notesOpen + 6, S.noteFocusClick);
  } else if (frame < S.menuOpen + 4) {
    pos = seg(noteBody, jvoice, S.menuCursorStart, S.menuOpen);
  } else if (frame < S.settingsOpen) {
    pos = seg(jvoice, settingsRow, S.menuOpen + 4, S.settingsClick);
  } else {
    // drift toward settings window center
    pos = seg(settingsRow, { x: W / 2 + 60, y: H / 2 }, S.settingsOpen, S.settingsOpen + 30);
  }

  // click press feedback: shrink slightly at click frames
  const clickFrames = [S.notesClick, S.noteFocusClick, S.menuOpen - 2, S.settingsClick];
  for (const cf of clickFrames) {
    const d = Math.abs(frame - cf);
    if (d < 4) scale = 0.82 + (d / 4) * 0.18;
  }

  return { x: pos.x, y: pos.y, scale };
}

function getClickRipple(
  frame: number,
  cursor: Pt,
): { x: number; y: number; r: number; opacity: number } | null {
  const clicks = [S.notesClick, S.noteFocusClick, S.menuOpen - 2, S.settingsClick];
  for (const cf of clicks) {
    if (frame >= cf && frame < cf + 12) {
      const p = (frame - cf) / 12;
      return {
        x: cursor.x,
        y: cursor.y,
        r: 6 + p * 22,
        opacity: (1 - p) * 0.8,
      };
    }
  }
  return null;
}

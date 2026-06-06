// JVoice design tokens — mirrors DESIGN-TOKENS.md (extracted from Swift sources).
// SwiftUI Color(r,g,b) 0-1 -> css rgb via round(c*255).

const c = (r: number, g: number, b: number) =>
  `rgb(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)})`;
const ca = (r: number, g: number, b: number, a: number) =>
  `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${a})`;

// HUD pill
export const HUD = {
  pillW: 220,
  pillH: 50,
  radius: 22,
  bg: c(0.027, 0.027, 0.055), // rgb(7,7,14)
  recording: {
    accent: { r: 0.29, g: 0.62, b: 1.0 }, // blue rgb(74,158,255)
    accentCss: c(0.29, 0.62, 1.0),
    text: c(0.82, 0.91, 1.0),
    sub: ca(0.29, 0.62, 1.0, 0.55),
    title: "Recording",
    subtitle: "Listening…",
  },
  transcribing: {
    accent: { r: 0.0, g: 0.831, b: 0.878 }, // cyan rgb(0,212,224)
    accentCss: c(0.0, 0.831, 0.878),
    text: c(0.627, 0.941, 0.969),
    sub: ca(0.0, 0.831, 0.878, 0.55),
    title: "Transcribing",
    subtitle: "Processing…",
  },
  done: {
    accent: { r: 0.431, g: 0.906, b: 0.718 }, // green rgb(110,231,183)
    accentCss: c(0.431, 0.906, 0.718),
    text: c(0.694, 0.988, 0.718),
    headline: "Pasted",
  },
  stopRed: c(1.0, 0.376, 0.376), // rgb(255,96,96)
};

// Settings palette
export const SP = {
  panelBg: c(0.051, 0.051, 0.086),
  sectionBg: c(0.059, 0.059, 0.102),
  border: c(0.118, 0.118, 0.173),
  headerText: c(0.29, 0.502, 0.8),
  inputBg: c(0.039, 0.039, 0.078),
  blue: c(0.29, 0.62, 1.0),
  gray: c(0.53, 0.53, 0.53),
  indigo: c(0.376, 0.627, 1.0),
  purple: c(0.502, 0.376, 1.0),
  cyan: c(0.125, 0.847, 1.0),
  orange: c(0.941, 0.627, 0.188),
  green: c(0.29, 0.871, 0.627),
  teal: c(0.125, 0.753, 0.627),
  red: c(1.0, 0.376, 0.376),
  white85: "rgba(255,255,255,0.85)",
  white75: "rgba(255,255,255,0.75)",
  white45: "rgba(255,255,255,0.45)",
  white40: "rgba(255,255,255,0.40)",
  white38: "rgba(255,255,255,0.38)",
  white35: "rgba(255,255,255,0.35)",
};

export const SYSTEM_FONT =
  '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif';

// Scripted demo content
export const RAW_SPEECH = "hey um can we move practice to thursday at five";
export const CLEAN_TEXT = "Hey! Can we move practice to Thursday at 5?";
export const END_CAPTION = "100% on-device · free";

// Menu items (exact, in order) from MenuBarController.swift
export const MENU_ITEMS = [
  { type: "item", title: "Start Dictation" },
  { type: "sep" },
  { type: "item", title: "Settings…" },
  { type: "item", title: "Launch at Login", check: false },
  { type: "sep" },
  { type: "item", title: "Quit JVoice" },
] as const;

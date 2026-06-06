// Per-character typing with slight raggedness. Returns how many chars of `full`
// are visible at local frame `f` (0-based within the typing window), given an
// fps and total duration in frames. Deterministic (seeded by char index).

export const charsVisible = (
  full: string,
  f: number,
  durationFrames: number,
): number => {
  const n = full.length;
  if (f <= 0) return 0;
  if (f >= durationFrames) return n;

  // Build cumulative per-char delays once (cheap for short strings).
  // Base interval + raggedness; spaces / punctuation get a small extra pause.
  let cum = 0;
  const stops: number[] = [];
  for (let i = 0; i < n; i++) {
    const ch = full[i];
    // pseudo-random jitter in [-0.4, 0.6], seeded by index
    const seed = Math.sin(i * 12.9898) * 43758.5453;
    const jitter = (seed - Math.floor(seed)) * 1.0 - 0.4;
    let w = 1 + jitter;
    if (ch === " ") w += 0.5;
    if (",.!?".includes(ch)) w += 1.2;
    w = Math.max(0.3, w);
    cum += w;
    stops.push(cum);
  }
  const totalWeight = cum;
  const progress = (f / durationFrames) * totalWeight;
  let count = 0;
  for (let i = 0; i < n; i++) {
    if (stops[i] <= progress) count = i + 1;
    else break;
  }
  return count;
};

#!/usr/bin/env python3
"""End-to-end transcription verification harness.

Generates many real `say`-synthesised clips (varied length, pause density, and
voice) and runs each through BOTH the whole-file and streaming bench paths with
the SHIPPING settings (vocabulary prompt on + regurgitation recovery). For each
it scores:

  * retention  — fraction of ground-truth words present, in order (LCS). A big
                 dropped span (the "it cut out a big chunk" bug) tanks this.
  * spurious   — custom-vocabulary words that appear though they were never
                 spoken (the "spews random custom words" bug). Must be 0.
  * accuracy   — for clips that DO speak the vocab, that each word is recovered.

Usage:  python3 scripts/verify-transcription.py [--model tiny|base|small|large] [--quick]
"""
import os, re, subprocess, sys, tempfile, itertools

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, ".build/release/JVoice")
CLIPS = os.path.join(tempfile.gettempdir(), "jv-verify-clips")
os.makedirs(CLIPS, exist_ok=True)

VOCAB = ["sub agents", "claude", "li-fraumeni", "vs code"]
VOCAB_ARG = ", ".join(VOCAB)

# Ground-truth passages with NO vocabulary words — any vocab word in the output
# is a hallucination.
PASSAGES = {
    "tariffs": "So basically what tariffs are is when governments put taxes on products that come from other countries and ultimately who actually pays them is the people who are buying the item so if someone wanted to buy a product from a country that has a really high tariff then the price would go up quite a lot",
    "weather": "The weather this week has been completely unpredictable with sunshine in the morning and heavy rain by the afternoon which makes it really hard to plan anything outdoors so most people have just decided to stay inside and wait for the weekend when things are supposed to finally calm down a little",
    "cooking": "When you are making a really good pasta sauce the most important thing is to start with good tomatoes and to cook the garlic slowly so that it never burns because burnt garlic will make the whole sauce taste bitter and then you simply let it simmer for a long time until the flavours come together",
    "travel": "Last summer we drove all the way across the country stopping in small towns that we had never heard of before and meeting people who were incredibly kind and generous with their time and by the end of the trip we had collected so many stories that we could barely remember which town each one happened in",
    "history": "The industrial revolution changed almost everything about how people lived and worked because suddenly machines could do the work of dozens of people and that meant cities grew very quickly as workers moved in from the countryside looking for jobs in the new factories that were opening up everywhere",
}

# Passages that DO speak the vocabulary (accuracy check).
VOCAB_PASSAGES = {
    "dev": ("I use vs code and claude every single day my favourite tool is the one we built and in the lab we studied li fraumeni syndrome and then I created a whole system of sub agents",
            ["vs code", "claude", "li-fraumeni", "sub agents"]),
}

VOICES = ["Samantha", "Daniel"]

def pause(ms):
    return f" [[slnc {ms}]] "

def build_clip_text(passage, pause_ms):
    # Insert a pause after roughly every ~12 words to create low-confidence gaps.
    words = passage.split()
    out = []
    for i, w in enumerate(words):
        out.append(w)
        if (i + 1) % 12 == 0:
            out.append(pause(pause_ms))
    return " ".join(out)

def gen_clip(name, text, voice):
    wav = os.path.join(CLIPS, f"{name}.wav")
    if os.path.exists(wav):
        return wav
    aiff = os.path.join(CLIPS, f"{name}.aiff")
    subprocess.run(["say", "-v", voice, "-o", aiff, text], check=True)
    subprocess.run(["afconvert", aiff, "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", wav], check=True)
    os.remove(aiff)
    return wav

def normalize(text):
    return re.sub(r"[^a-z0-9 ]+", " ", text.lower()).split()

def lcs_len(a, b):
    if not a or not b:
        return 0
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0] * (len(b) + 1)
        for j, y in enumerate(b):
            cur[j + 1] = prev[j] + 1 if x == y else max(prev[j + 1], cur[j])
        prev = cur
    return prev[-1]

def retention(gt, hyp):
    g, h = normalize(gt), normalize(hyp)
    return lcs_len(g, h) / max(1, len(g))

def spurious_vocab(hyp, gt):
    """Vocab phrases in hyp beyond those in the ground truth."""
    hn, gn = " " + " ".join(normalize(hyp)) + " ", " " + " ".join(normalize(gt)) + " "
    total = 0
    for v in VOCAB:
        vn = " " + " ".join(normalize(v)) + " "
        total += max(0, hn.count(vn) - gn.count(vn))
    return total

def run_bench(wav, stream):
    """Returns (text, fell_back). For stream mode this models the REAL app:
    when finish() returns nil the app uses the whole-file transcript, so we
    score that — a fallback is correct behavior, not a miss."""
    cmd = [BIN, "--bench", wav, "--model", MODEL, "--vocab", VOCAB_ARG]
    if stream:
        cmd.append("--stream")
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    lines = out.splitlines()
    if not stream:
        for line in lines:
            if line.startswith("raw:"):
                m = re.search(r'"(.*)"', line)
                return (m.group(1) if m else "", False)
        return ("", False)
    streamed, wholefile, fell_back = None, "", False
    for line in lines:
        if line.startswith("streamed:"):
            if "session fell back" in line:
                fell_back = True
            else:
                m = re.search(r'"(.*)"', line)
                streamed = m.group(1) if m else ""
        elif line.startswith("wholefile:"):
            m = re.search(r'"(.*)"', line)
            if m:
                wholefile = m.group(1)
    # App behavior: streamed transcript if present, else whole-file fallback.
    return (streamed if streamed is not None else wholefile, fell_back)

MODEL = "base"
QUICK = False
for i, a in enumerate(sys.argv[1:], 1):
    if a == "--model":
        MODEL = sys.argv[i + 1]
    if a == "--quick":
        QUICK = True

def main():
    pause_patterns = {"short": 500, "med": 2200} if QUICK else {"short": 500, "med": 2200, "long": 6500}
    voices = VOICES[:1] if QUICK else VOICES

    scenarios = []  # (name, text, voice, ground_truth, expect_vocab_present)
    # No-vocab passages × pauses × voices, plus long concatenations.
    for (pname, passage), (plabel, pms), voice in itertools.product(PASSAGES.items(), pause_patterns.items(), voices):
        scenarios.append((f"{pname}-{plabel}-{voice}", build_clip_text(passage, pms), voice, passage, None))
    # Long (~2 min) clips: concatenate three passages with medium pauses.
    long_text = (pause(2500)).join(PASSAGES.values())
    for voice in voices:
        scenarios.append((f"long3-{voice}", build_clip_text(long_text, 2500), voice, long_text, None))
    # Vocab-spoken accuracy clips.
    for voice in voices:
        for vname, (vtext, expect) in VOCAB_PASSAGES.items():
            scenarios.append((f"vocab-{vname}-{voice}", build_clip_text(vtext, 1500), voice, vtext, expect))

    print(f"model={MODEL}  scenarios={len(scenarios)}  (×2 paths = {len(scenarios)*2} transcriptions)\n")
    fails = []
    n_pass = 0
    for name, text, voice, gt, expect in scenarios:
        wav = gen_clip(name, text, voice)
        row = []
        for stream in (False, True):
            hyp, fell_back = run_bench(wav, stream)
            ret = retention(gt, hyp)
            spur = spurious_vocab(hyp, gt)
            tag = "stream" if stream else "whole "
            fb = "*" if fell_back else " "
            ok = ret >= 0.85 and spur == 0
            vmiss = ""
            if expect is not None:
                miss = [v for v in expect if (" " + " ".join(normalize(v)) + " ") not in (" " + " ".join(normalize(hyp)) + " ")]
                # For vocab clips, words ARE in ground truth so spurious is moot; check accuracy instead.
                ok = ret >= 0.80 and len(miss) == 0
                vmiss = f" miss={miss}" if miss else ""
            status = "PASS" if ok else "FAIL"
            if ok:
                n_pass += 1
            else:
                fails.append((name, tag.strip(), ret, spur, vmiss, hyp))
            row.append(f"{tag}{fb} ret={ret:.2f} spur={spur}{vmiss} {status}")
        print(f"  {name:28s} | {row[0]:42s} | {row[1]}")

    total = len(scenarios) * 2
    print(f"\n{n_pass}/{total} path-runs passed.")
    if fails:
        print("\nFAILURES:")
        for name, tag, ret, spur, vmiss, hyp in fails:
            print(f"  ✗ {name} [{tag}] ret={ret:.2f} spur={spur}{vmiss}")
            print(f"      hyp: {hyp[:200]}")
        sys.exit(1)
    print("ALL PASS")

if __name__ == "__main__":
    main()

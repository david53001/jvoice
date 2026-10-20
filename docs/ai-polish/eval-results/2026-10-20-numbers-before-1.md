# AI Polish eval — 2026-10-20, claude-haiku-5-5, thinking off

Cases: `scripts/ai-polish-eval/cases-numbers.json` (12). Per-call deadline 30 s (the app uses 3 s).

## Summary

- **Overall accuracy: 100.0% (12/12) — by a real polish 100.0% (12/12); do-nothing baseline 100.0% (12/12); fallbacks 0**
- preserve: 100.0% (12/12) — by a real polish 100.0% (12/12); do-nothing baseline 100.0% (12/12); fallbacks 0
- context-fix hold-out (words not in the prompt): — — by a real polish —; do-nothing baseline —; fallbacks 0
- **Latency:** p50 1081 ms, p95 1612 ms, max 1612 ms; over the app's 3 s deadline (graded as the local text): 0
- Tokens: 9309 in / 417 out — estimated cost $0.0011 ($0.000095 per dictation)

## Cases

| id | category | verdict | ms | outcome | transcript | output | why |
|---|---|---|---|---|---|---|---|
| n1 | preserve | PASS | 918 | ok | 78.44 I'm currently having an issue saying the number at the start of this message | I am currently having an issue saying the number at the start of this message. |  |
| n2 | preserve | PASS | 1081 | ok | I have the mass, I mean, sorry, the distance. I have it as 0.70, 42 kilograms is the mass, 7.41 is the final velocity, and the acceleration is negative 9.8. | I have the mass, I mean, sorry, the distance. I have it as 0.70, 42 kilograms is the mass, 7.41 is the final velocity, and the acceleration is negative 9.8. |  |
| n3 | preserve | PASS | 1612 | ok | so I had 0.7 m and my initial velocity was 7.41 and my final velocity was zero | So I had 0.7 m, and my initial velocity was 7.41, and my final velocity was zero. |  |
| n4 | preserve | PASS | 1119 | ok | and so I did 7.41² = 2 · 0.70 · a and then I got a to be 37.8 meters per second squared | And so I did 7.41² = 2 · 0.70 · a, and then I got a to be 37.8 meters per second squared. |  |
| n5 | preserve | PASS | 1102 | ok | the displacement was 0.70 since he's pushing up with his legs and that gave us 3294.48 | The displacement was 0.70 since he is pushing up with his legs, and that gave us 3294.48. |  |
| n6 | preserve | PASS | 1066 | ok | 3294.48 newtons minus 411.6 newtons gave us 2882.88 newtons which is the answer | 3294.48 newtons minus 411.6 newtons gave us 2882.88 newtons, which is the answer. |  |
| n7 | preserve | PASS | 1238 | ok | the price went from 78.44 to 81.2 dollars which is about a 3.5% increase | The price went from 78.44 to 81.2 dollars, which is about a 3.5% increase. |  |
| n8 | preserve | PASS | 674 | ok | so 42 × -9.8 is minus 411.6 newtons | So 42 × -9.8 is minus 411.6 newtons. |  |
| n9 | preserve | PASS | 748 | ok | my acceleration was 37.8 and my mass was 42 so the force is 1587.6 | My acceleration was 37.8 and my mass was 42, so the force is 1587.6. |  |
| n10 | preserve | PASS | 1309 | ok | the answer is 0.0045 and the error was 1.20 percent | The answer is 0.0045, and the error was 1.20 percent. |  |
| n11 | preserve | PASS | 1362 | ok | I scored 78.44 on the test, she got 81 and he got 90.5 | I scored 78.44 on the test. She got 81, and he got 90.5. |  |
| n12 | preserve | PASS | 755 | ok | the speed of light is 3 × 10^8 meters per second and I wrote 3.0 × 10^8 | The speed of light is 3 × 10^8 meters per second, and I wrote 3.0 × 10^8. |  |

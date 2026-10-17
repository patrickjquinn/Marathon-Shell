# On-device intelligence for Pilot: research and plan

Research of 2026-10-16. The question: would on-device intelligence suit
Marathon OS better than Pilot's current hosted stack (Jev for decisions,
Qwen 3.8 27B on Groq for generation)? Marathon's values are privacy,
working offline, open source and modest hardware.

**Short answer: yes for the decision layer, speech and the simple
commands; no (not yet) for open-ended generation and multi-tool plans.**
On every Marathon target, the parts that run on almost every turn
(intent, domain, triage, needs-web, slots, STT, TTS) can run on the phone
within Pilot's latency budget. A local model good enough to replace
Qwen 27B at tool calling only fits on the A76-class devices (HackberryPi
CM5, Zinwa Q25, OnePlus 6 by estimate), and even there it is clearly
weaker and slow to answer unless the prompt prefix is cached. So the
recommendation is a **local-first hybrid**: decide, act and speak on the
device; send a request out only when it needs generation, and only with
consent.

**Organisation rules.** Check every application, service, runtime and
model named here with the IT team before adopting it. This document does
not recommend signing up for any free account, free tier or trial
(Groq's free plan included). Send the terms of service of any free tier,
trial, early-access programme or waitlist (Jev's included) to the legal
team before anyone signs up. Model licences (Gemma terms, Llama
Community Licence, LFM Open License, Piper's GPL-3.0 line, per-voice
licences) also need legal review before they ship in an image.

Number tags used below: **M** means measured by the cited source;
**E** means estimated here, with the method given; **V** means a vendor
claim not independently checked.

## 1. Sources

### Local (read-only)

| Key | Source | Version | Licence | Used for |
|---|---|---|---|---|
| P | Shipwright `shoal/pilot/README.md` | Shipwright HEAD | LicenseRef-Shipwright-Proprietary | pilotd turn, backends, local_intent, speech |
| S | Shipwright `docs/specs/pilot.md` | HEAD | same | Jev question set (§5.1), thresholds (§5.2), Qwen layer (§6), Lighthouse (§10.1), cost (§12), latency budget (§13) |
| R | Shipwright `services/pilot-relay/README.md` | HEAD | same | Quotas, spend ceiling, region stamping, Groq retention |
| J | Shipwright `pilotd/src/jev.rs`, `config.rs`, `llm.rs` | HEAD | same | `JevClient`, `ScoreJev`, `JevConfig`, `is_local`, region check |
| D | Marathon `packaging/packages/shoal-pilotd/` | this repo | patches follow pilotd | 0001 Marathon adapters, 0002 direct mode, `/etc/shoal-pilot/pilotd.toml` |

### Web

| Key | Source | Date | Licence / terms | Used for |
|---|---|---|---|---|
| W1 | [Groq model page, qwen3.8-27b](https://console.groq.com/docs/model/qwen/qwen3.8-27b), [models](https://console.groq.com/docs/models) | read 2026-10-16 | Groq commercial terms | Preview status, $0.80/$4.00 per M tokens, 131K context |
| W2 | [Groq rate limits](https://console.groq.com/docs/rate-limits) | read 2026-10-16 | — | 30 RPM, 1K RPD, 8K TPM, 200K TPD per organisation for this model |
| W3 | [Groq: your data](https://console.groq.com/docs/your-data), [DPA](https://console.groq.com/docs/legal/customer-data-processing-addendum), [Helsinki DC](https://groq.com/newsroom/groq-launches-european-data-center-footprint-in-helsinki-finland) | read 2026-10-16 | — | No retention by default (up to 30 days for abuse), ZDR, GCP US storage, SCCs |
| W4 | [typesafe.ai: System One and Jev](https://typesafe.ai/blog/introducing-system-one-models-and-jev), [docs](https://docs.typesafe.ai/introduction) | 2026-09-15 | Commercial, early access (waitlist) | Price, latency claims; retention/region not public |
| W5 | [QwenLM/Qwen3.8](https://github.com/QwenLM/Qwen3.8), [Qwen3.5-4B card](https://huggingface.co/Qwen/Qwen3.5-4B), [Qwen3.5-2B card](https://huggingface.co/Qwen/Qwen3.5-2B) | 2026-08 / 2026-03-02 | Apache-2.0 | No small Qwen 3.6/3.8; Qwen3.5 0.8B/2B/4B/9B, BFCL-V4 on the cards |
| W6 | [BFCL V4 leaderboard](https://gorilla.cs.berkeley.edu/leaderboard.html) ([csv](https://gorilla.cs.berkeley.edu/data_overall.csv)) | updated 2026-04-12 | — | Comparable function-calling scores |
| W7 | [Gemma 4 E2B card](https://huggingface.co/google/gemma-4-E2B-it), [Gemma 4 Apache licence](https://ai.google.dev/gemma/apache_2), [Gemma Terms](https://ai.google.dev/gemma/terms) | terms modified 2026-04-01 | Gemma 4: Apache-2.0; Gemma 3/3n/FunctionGemma: Gemma Terms | Licence split |
| W8 | [Granite 4.0 1B card](https://huggingface.co/ibm-granite/granite-4.0-1b) | 2025-10-28 | Apache-2.0 | BFCL v3 54.8 (vendor) |
| W9 | [LFM2.5 cards](https://huggingface.co/LiquidAI/LFM2.5-2.6B), [LFM licence](https://huggingface.co/LiquidAI/LFM2.5-2.6B/raw/main/LICENSE) | 2026 | LFM Open License v1.0 ($10M revenue threshold) | Excluded on licence |
| W10 | [Llama 3.2 licence](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/blob/main/LICENSE.txt) | — | Llama 3.2 Community | Attribution, naming, AUP |
| W11 | [BTZSC benchmark](https://huggingface.co/blog/aarabil/btzsc-benchmark) ([paper](https://arxiv.org/html/2603.11991)) | 2026-08-09 | — | Zero-shot label-probability classification by small LLMs |
| W12 | [llama.cpp discussion #30069](https://github.com/ggml-org/llama.cpp/discussions/30069) | 2026-10-06 | MIT (llama.cpp) | Pi 5 llama-bench, build 836d571 (re-read by me 2026-10-16) |
| W13 | [llama.cpp issue #26484](https://github.com/ggml-org/llama.cpp/issues/26484) | 2026-08 | — | Pi 5 decode by quant, board power |
| W14 | [note.com Pi 5 llama-bench](https://note.com/sakuya_mikagami/n/na61e0c077d17) | 2026-09-09 | — | 2B-class pp/tg and peak RSS on Pi 5 8 GB |
| W15 | [llama.cpp discussion #30549](https://github.com/ggml-org/llama.cpp/discussions/30549) | 2026-10-14 | — | Kirin 980 (2+2 A76) Qwen3-4B |
| W16 | [llama.cpp discussion #10879](https://github.com/ggml-org/llama.cpp/discussions/10879) | 2025-01/02 | — | Dimensity 1080 CPU, Mali Vulkan |
| W17 | [llama.cpp #9830](https://github.com/ggml-org/llama.cpp/discussions/9830), [#10757](https://github.com/ggml-org/llama.cpp/issues/10757) | 2024-10/12 | — | Q4_0 online repack: 2.6x pp on Pi 5; needs dotprod/i8mm (not on A53) |
| W18 | [llama.cpp #26213](https://github.com/ggml-org/llama.cpp/issues/26213), [#5441 comment](https://github.com/ggml-org/llama.cpp/issues/5441#issuecomment-3518701014) | 2026-09-14 / 2025-11 | — | Vulkan on v3dv broken/0.15 t/s; panvk failures |
| W19 | [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) | master 2a667032, 2026-10-16 | MIT | `n_probs`, `logit_bias`, `grammar`, `/v1/embeddings`, `/rerank`, `cache_prompt`, slots |
| W20 | [Alpine packages](https://pkgs.alpinelinux.org/packages?name=llama.cpp&branch=edge&arch=aarch64), [aports libggml](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/community/libggml) | read 2026-10-16 | — | `llama.cpp` 0.6.0-r0, `libggml` 0.26.0, `whisper.cpp` 1.9.4, `onnxruntime` 1.30.0, `vosk-api` (community); `piper-tts` 1.7.0 (testing) |
| W21 | [Moonshine v2 paper](https://arxiv.org/abs/2602.12241), [Pi forum thread](https://forums.raspberrypi.com/viewtopic.php?t=396227) | 2026-02 | MIT (English models) | Streaming ASR WER and Pi 5 latency |
| W22 | [sherpa-onnx whisper tiny.en](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/tiny.en.html), [sherpa VITS/Piper](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/vits.html) | — | Apache-2.0 | Pi 4 RTFs |
| W23 | [kokoro-pi](https://github.com/zreecespieces/kokoro-pi) | 2026 | MIT code; Kokoro weights Apache-2.0 | Pi 5 Piper and Kokoro RTF / first audio |
| W24 | [Vosk models](https://alphacephei.com/vosk/models) | — | Apache-2.0 | small-en-us 40 MB, 9.85 WER LibriSpeech clean |
| W25 | [FastFit paper](https://arxiv.org/abs/2404.12365) | 2024-04 | — | SetFit few-shot CLINC150/Banking77/HWU64 |
| W26 | [jarvis-pi5-vulkan-embeddings](https://github.com/karolfurtak/jarvis-pi5-vulkan-embeddings) | 2026 | — | MiniLM-L12 embeddings on Pi 5 CPU vs Vulkan |
| W27 | [Apple Foundation Models 2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025), [Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/) | 2025-07 / 2024-06 | — | ~3B on-device + attested server tier |
| W28 | [Gemini Nano / AICore](https://developer.android.com/ai/gemini-nano) | updated 2026-10-08 | — | On-device with Firebase "hybrid" cloud fallback |
| W29 | [Home Assistant: prefer local](https://www.home-assistant.io/voice_control/assist_create_open_ai_personality/), [Speech-to-Phrase](https://www.home-assistant.io/blog/2025/02/13/voice-chapter-9-speech-to-phrase/) | 2025-02-13 | Apache-2.0 | Local intents first, LLM fallback |
| W30 | [OVOS persona](https://github.com/OpenVoiceOS/ovos-persona), [Jolla Mind2](https://commerce.jolla.com/products/jolla-mind2-ai-assistant-2nd-batch), [TechCrunch on Venho](https://techcrunch.com/2025/03/03/jolla-founders-take-the-wraps-off-an-ai-assistant-to-power-up-their-push-for-privacy-friendly-genai/) | 2025 | — | Linux-world assistant patterns |
| W31 | [Latombe v Commission, T-553/23](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex%3A62023TJ0553); appeal C-703/25 P ([tracker](https://digitalpolicyalert.org/event/35459)) | 2025-09-03 / 2025-10-31 | — | EU-US DPF upheld, appeal pending |
| W32 | [EU AI Act GPAI guidelines](https://digital-strategy.ec.europa.eu/en/policies/guidelines-gpai-providers) | 2025 | — | Provider vs deployer |
| W33 | [Raspberry Pi CM5 docs](https://www.raspberrypi.com/documentation/computers/compute-module.html), [Pi 5 cooling](https://www.raspberrypi.com/news/heating-and-cooling-raspberry-pi-5/) | — | — | CM5 RAM 2/4/8/16 GB; throttle at 80/85 °C |

## 2. What Pilot sends out today

From P, S, R, J and D:

| Step | Where today | What it needs | Volume |
|---|---|---|---|
| Redaction | Device (`redact.rs`) | Regex + address book | Every turn |
| `local_intent` | Device, **only** when offline / no consent / Jev unreachable | English phrasings: timer, alarm, reminder, media, calendar, cancel, memory | — |
| Decide | Jev (US, waitlist) or Lighthouse `ScoreJev` (SGLang `/v1/score`) | Choice over 13 intents, Noul `needs_generation`, Score `ambiguity`; plus `domain` Choice, a stage-two action Choice when a domain has >6 tools, Noul `needs_web` | 1–2 requests per turn; quota 165/day |
| Triage | Jev | Noul `worth_interrupting`, Choice `bucket` (4), Score `urgency` (3) on a redacted ≤500-char notification | Up to 60/hour |
| Generate / tools / vision | Qwen 3.8 27B on Groq (US), via relay or 0002 direct mode | OpenAI chat with tools, JSON mode, `reasoning_effort`, image input | Quota 66 requests and 165K tokens/day |
| Web search | Relay `/v1/search` (Cloudflare) | Query text | 33/day |
| STT / TTS | Device: whisper.cpp tiny/base (`pilot-voice`), Piper subprocess (`pilot-tts`) | — | **Not built for Marathon** (D: "Speech is not built") |

Jev's answers only route. Pilot's own thresholds act on them (S §5.2: confidence ≥ 0.85, `needs_generation` < 0.3, ambiguity < 1.0 → deterministic handler). So a local scorer does not need Jev's calibration. It needs to be calibrated itself, against `pilotd --calibrate` and the decision log.

Two facts change the picture for Marathon in particular:

1. **The hosted path does not scale as configured.** Groq lists `qwen/qwen3.8-27b` as **Preview** ("evaluation only… may be discontinued at short notice"; W1). Its published limits are **per organisation**: 30 RPM, 1K RPD, 8K TPM, 200K TPD (W2).
   - 200K TPD is about 6 typical users (34K tokens/day each) or about 1.2 users at the relay's 165K per-licence cap.
   - 8K TPM is about two turns a minute across all users.
   - The docs label these Developer-plan limits; whether the Free plan is the same is unclear (W2).
   - Production use needs negotiated limits. That is an IT/legal/procurement question, not a sign-up.
2. **Jev is waitlist-only.** Its retention, region and DPA are not public (W4; S §16 lists them as open). It is the dependency that is on every turn.

## 3. Findings

### 3.1 Small models (as of 2026-10-16)

There is no small Qwen 3.6 or 3.8. The newest small Qwen is **Qwen3.5 (0.8B, 2B, 4B, 9B; 2026-03-02; Apache-2.0)**, so a local model is a different, much smaller model than the 27B Pilot is tuned against (W5).

| Model | Params | Licence | Function calling (source, comparable?) | Zero-shot label scoring |
|---|---|---|---|---|
| Qwen3.5-0.8B / 2B / 4B | 0.8 / 2 / ~4B | Apache-2.0 | BFCL-V4 25.3 / 43.6 / 50.3, thinking mode (W5, vendor card, **not** on the official board) | — |
| Qwen3-4B-Instruct-2507 | 4.0B | Apache-2.0 | BFCL V4 overall 35.68%, rank 54 (W6, official) | Qwen3-4B macro-F1 0.65 over 22 datasets, best small model (W11) |
| Qwen3-1.7B / 0.6B | 1.7 / 0.6B | Apache-2.0 | BFCL V4 28.41% / 23.93% (W6) | not reported |
| Granite 4.0 1B | 1.6B | Apache-2.0 | BFCL v3 54.82 (W8, vendor) | — |
| Gemma 4 E2B / E4B | 2.3B eff. (5.1B with embeddings) / — | **Apache-2.0** (new for Gemma 4) | Tau2 24.5 / 42.2, no BFCL (W7) | — |
| Gemma 3 1B / 4B, FunctionGemma 270M | | Gemma Terms (§3.1 pass-through of use restrictions; §3.2 remote restriction right) | BFCL V4 7.17% / 19.62% (W6) | Gemma-3-1B 0.36 (W11) |
| Llama 3.2 1B / 3B | | Llama 3.2 Community (attribution, "Llama" naming of derivatives, AUP) | BFCL V4 10.82% / 21.95% (W6) | 3B ≈ 0.43 (W11) |
| Phi-4-mini | 3.8B | MIT | none published | ≈ 0.43 (W11) |
| LFM2.5-1.2B / 2.6B | | LFM Open License ($10M revenue threshold) | BFCLv3 49.1 / BFCLv4 56.9 (vendor) | — |
| xLAM-2-3b, Hammer2.1 | | CC-BY-NC-4.0 | BFCL V4 41.22% (W6) | — |

**Takeaways.**

- **Licences.** Only the Apache-2.0/MIT models fit an open-source OS that ships or downloads weights: Qwen3/3.5, Granite 4, Gemma 4, SmolLM3, Ministral 3, Phi-4-mini. Gemma 3/3n terms would make Marathon pass usage restrictions on to its users. LFM and the NC models are out.
- **Function calling.** Even the best small models score well below a 27B. On the official BFCL V4, Qwen3-4B-2507's multi-turn sub-score is about 22% (W6). Pilot's two-stage routing helps a lot, because it offers the model at most three to six tools. But plans (`keel__plan.run`) and multi-round tool loops should stay on a large model.
- **Zero-shot routing.** Below 1B it is weak (W11). Restricting the answer to label tokens removes the formatting failures that sink small models in free-text tests.

### 3.2 Runtimes and measured speed

**Runtime.** llama.cpp is the only practical LLM runtime here. It is in Alpine **community** (`llama.cpp` 0.6.0-r0, built 2026-10-06, re-checked by me), with `llama-server` and `llama-bench` subpackages and the system `libggml` 0.26.0 built with `GGML_CPU_ALL_VARIANTS=ON` (runtime kernel selection from A53 to A76). KleidiAI is **not** enabled in that build (W20). ExecuTorch, MLC-LLM, MNN and onnxruntime-genai are not packaged.

**GPU.** No Marathon GPU helps.

- Vulkan on Pi 5 v3dv is broken or about 0.15 t/s against 11–16 t/s on the CPU; the issue was closed "not planned" on 2026-09-14 (W18).
- On the Pi 5, embeddings are 25–44x slower on Vulkan than on the CPU (W26).
- turnip on Adreno 6xx and Mali-G57/G68 are slower than the CPU or fail (W16, W18).
- etnaviv and lima have no Vulkan at all.
- So: CPU everywhere.

| Device | Model | pp (prompt t/s) | tg (gen t/s) | Tag |
|---|---|---|---|---|
| Pi 5 (= CM5 SoC) | Qwen2.5-0.5B Q4_0, 403 MiB | 289.9 (4 threads), 173.7 (2t) | 27.3 (4t), **33.8 (2t)** | M W12, build 836d571, KleidiAI off. The table labels it "qwen2 1B, 630M params"; the text says 0.5B |
| Pi 5 | Qwen2.5-0.5B by quant, 4t | — | Q4_K_M 25.8, Q8_0 19.9; board 5.5–6.7 W | M W13 |
| Pi 5 8 GB | MiniCPM5-2B Q4_K_M | 38.8 | 8.5 (2t); peak RSS 2.9 GiB | M W14 |
| Pi 5 8 GB | Gemma 4 E2B Q4_K_M | 29.7 | 7.2; peak RSS 4.4 GiB | M W14 |
| Pi 5 | Qwen ~1.5B Q4_0 | ~80 | ~12–14 | E: pp scaled by non-embedding params from W12; tg from ~10 GB/s effective bandwidth over a ~0.9 GB file |
| Pi 5 | ~4B Q4_0 | ~25–30 | ~4–5 | E, same method; consistent with W14 |
| Kirin 980 (2+2 A76; nearest to G99's 2 A76) | Qwen3-4B Q4_0 | short-prompt TTFT 1.4 s | 9.0 | M W15 |
| Dimensity 1080 (2 A78 + 6 A55) | Llama 3.2 1B Q4_0 | 73.9 | 14.2 | M W16 |
| Librem 5 (4 A53 @1.5 GHz) | 0.5B Q4_0 | ~15–25 | ~8–12 | E: clock ratio × no-dotprod GEMM penalty (no repack on ARMv8.0, W17); LPDDR4 bandwidth. **No measurement exists** |
| PinePhone (4 A53 @1.15 GHz) | 0.5B Q4_0 | ~10–18 | ~5–7 | E, same method |
| SD845, Helio G99 | — | — | — | **No measurement found.** Expect them between the Dimensity 1080 and Kirin 980 rows (E). A75/A76 cores have dotprod |

**Q4_0 repacking.** Online repack gave the Pi 5 **2.6x prompt speed** at the same generation speed (W17). It needs dotprod or i8mm, so the A53 phones get nothing from it.

**Thermals.** The Pi 5 throttles at 80 °C. Without a cooler, Raspberry Pi's own test reached that in about 200 s of sustained load (W33). Pilot's load is bursty, so this matters for long generations more than for scoring.

**Prompt processing is the bottleneck.** Pilot's Qwen turn is about 3,000 input tokens (S §12). The system prompt alone is about 4.7 KB of text in `pipeline.rs::system_prompt` (≈1,200 tokens, E), and tool schemas come on top. Time to first token without a cache (E, prompt length ÷ pp, a lower bound):

| Device / model | 1,500 tokens | 3,000 tokens | 50-token turn after a cached prefix |
|---|---|---|---|
| Pi 5, 0.5B | ~5 s | ~10 s | ~0.2 s |
| Pi 5, ~1.5B | ~19 s | ~38 s | ~0.6 s |
| Pi 5, 2B (W14) | ~39 s | ~77 s | ~1.3 s |
| Librem 5, 0.5B | ~1–1.7 min | ~2–3.5 min | ~2–3 s |
| PinePhone, 0.5B | ~1.5–2.5 min | ~3–5 min | ~3–5 s |

Uncached local generation is unusable on every target. `llama-server` reuses an identical prompt prefix by default (`cache_prompt`). It can also persist it per slot (`--slot-save-path`, `POST /slots/{id}?action=save|restore`; W19). This only works if pilotd keeps the system prompt and tool block byte-stable and puts the per-turn parts (time, memory, hints, the redacted utterance) **after** them. Today `system_prompt(hints)` puts hints into the system message, so the order would need to change.

**Uncertainty.** Qwen3.5 small models are reported to use a hybrid linear-attention design. Check that llama.cpp's prompt cache and slot restore behave for them as they do for dense Qwen3 (benchmark plan, B3).

### 3.3 Replacing Jev locally

Pilot already speaks two scorer protocols (J): `HttpJev` (Jev) and `ScoreJev`. `ScoreJev` sends each question as one prompt with labelled options ("A. alarm …") and reads the softmax restricted to the label tokens from SGLang `/v1/score`. Two local equivalents:

**(a) A small LLM through `llama-server`, one forward pass per question.**

- llama-server has no `/v1/score`.
- `/completion` with `n_probs: N`, `max_tokens: 1` and `temperature: 0` returns the top-N log-probabilities at the answer position (W19).
- Restricting those to the label tokens and renormalising gives exactly the restricted softmax SGLang computes, provided every label falls inside the top N. With 13 intents, use N ≥ 64 and count a missing label as 0.
- Alternative: `grammar: root ::= "A" | "B" | …` with `post_sampling_probs: true` asks the server for probabilities after the grammar is applied.
- Cost per question: the shared prefix ("You answer with a single label. State: …") is cached, so only the question and options are new, ≈60–150 tokens.
- That is ≈0.2–0.5 s on a Pi 5 at 0.5B and ≈1–2 s at 1.5B (E). A turn asks 3–5 questions, so ≈1–2.5 s at 0.5B: inside S §13's budget only at the small end.
- On A53 it is several seconds per question (E), which is too slow.

**(b) A sentence-embedding classifier (recommended default for the hot path).**

- Accuracy: frozen all-MiniLM-L6-v2 embeddings plus logistic regression reach 86.9% on Banking77 with 10 examples per class and 93.3% with full data (unrefereed model card). SetFit on a 110M encoder gets 89.0/90.9% on CLINC150 at 5/10 shots (W25). Both are far better than zero-shot NLI, which scores 46% on held-out Banking77.
- Latency on Pi 5: ≈35 ms per sentence for MiniLM-L12 through llama.cpp on 4 threads (M, derived from W26). L6 should be ≈15–20 ms (E).
- Latency on A53: ≈3–5x slower (E), still well under 200 ms.
- Model: about 23M parameters and tens of MB, Apache-2.0.
- Coverage: intent, domain, `needs_web` and triage `bucket` are classification problems. `needs_generation`, `ambiguity` and `urgency` can be logistic heads on the same embedding.
- Training data: synthetic, generated once offline (by the large model, or from Jev's answers on a synthetic set) and shipped as a small head file. Real utterances never leave the phone; the decision log keeps no utterances anyway.
- **Keel app domains are dynamic.** For those, use embedding similarity between the utterance and each domain's tool titles and descriptions (kNN or cosine). This is what S §9.3 already feeds Jev as criteria.
- Calibration: the outputs are probabilities that `pilotd --calibrate` already knows how to calibrate.

**Accuracy caveat.** No published numbers exist for Pilot's exact question set. B5 in the benchmark plan measures it against Jev on a synthetic set before anything switches.

### 3.4 Speech

| Piece | Choice | Evidence | Licence |
|---|---|---|---|
| STT, A76 devices | **Moonshine v2 Tiny/Small streaming** | Pi 5 end-of-speech → text 237 ms (Tiny, 34M params, LibriSpeech-clean WER 4.49) and 527 ms (Small, WER 2.49). Same source puts Whisper Tiny at 5.9 s (M, Moonshine's table relayed via W21; I did not see the primary table) | MIT (English) |
| STT, existing path | whisper.cpp tiny.en / base.en (already in `pilot-voice`; Alpine `whisper.cpp` 1.9.4) | Pi 4: tiny.en RTF 0.39 int8 (sherpa-onnx, W22). Pilot's own x86 run: 7.5 s of audio in 1.7 s (P). A53: no measurement | MIT |
| STT, A53 phones | Vosk small-en-us (40 MB, ~300 MB RAM) or whisper tiny.en; measure | LibriSpeech clean WER 9.85 (W24); streams on a Pi 3/4 (claim, unmeasured); Alpine `vosk-api` | Apache-2.0 |
| TTS | **Piper** (`pilot-tts` already drives it as a subprocess) | Pi 5 RTF 0.12–0.14 (W23); Pi 4 RTF 0.36 at 4 threads (W22). Alpine `piper-tts` 1.7.0 in **testing** | MIT rhasspy/piper is archived; Alpine 1.7.0 is likely the GPL-3.0 piper1 line. The subprocess boundary already isolates it (P). Each voice has its own licence |
| TTS, nicer voice | Kokoro-82M int8 | Pi 5 RTF 0.51–0.65, first audio 0.7–1.6 s (W23). A76 only | Apache-2.0 weights |

Speech is already on-device in Pilot's design (S §7). On Marathon it just has not been built (D). Building it is the cheapest privacy win available.

### 3.5 What others do

- **Apple**: a ~3B model runs on the device, and harder requests go to attested Private Cloud Compute (W27).
- **Google**: Gemini Nano in AICore keeps no data and has no network. Firebase's "hybrid" API falls back to cloud Gemini (W28).
- **Samsung**: a "process data only on device" switch turns off the generative features and keeps translation and transcription.
- **Linux world**:
  - Home Assistant's "prefer handling commands locally" runs its template intents first and the LLM only when no intent matches (W29).
  - OpenVoiceOS runs local intent engines first, then an optional LLM persona, which can be local (W30).
  - Jolla's Venho/Mind2 puts the "local" model in a separate home box, not on the phone (W30).
  - FuriOS, Ubuntu Touch and Plasma Mobile have no assistant.
- The consistent pattern is **deterministic local intents → small local model → optional, consented cloud**. Pilot today does the opposite (cloud decision first, local only when offline).

### 3.6 Cost, privacy, regulation

**Cost is not the argument.** At the verified Groq price, a typical user costs ≈$1.20/month on Qwen plus ≈$0.06 on Jev; a user at the relay caps costs ≈$6.13/month (W1, W4; arithmetic from S §12 and R's quotas). Local inference moves the cost to the phone's battery: ≈0.2–0.3 J per generated token on a Pi 5 at 0.5B (M W13).

**Transfers.**

- Both hosted steps are transfers to US processors.
- The EU-US Data Privacy Framework stands after *Latombe* (General Court, 3 Sep 2025), but the appeal C-703/25 P is pending (W31).
- Redacted text can still be personal data. Groq's DPA uses SCCs and offers Zero Data Retention (W3).
- Jev's terms are not public (W4).
- Local decisions remove the transfer question for the decision, triage and speech traffic altogether. Triage is the most sensitive of these, since it carries other people's message titles.

**AI Act.** Shipping an unmodified open-weight model, or calling a hosted one, makes Marathon an AI-system provider or deployer, not a GPAI provider. Fine-tuning a scorer head is far below the substantial-modification line (W32). The transparency duties apply either way. Legal should confirm this reading.

**Licence fit.** pilotd itself is `LicenseRef-Shipwright-Proprietary` (P). Local components (llama.cpp MIT, Apache-2.0 models, whisper.cpp MIT, Moonshine MIT, Vosk Apache-2.0) are *more* compatible with an open-source OS than either hosted API. They do not change pilotd's own licence.

## 4. Per-device verdict

CM5 RAM comes in 2/4/8/16 GB (W33); the HackberryPi unit is assumed 8 GB.

| Device | CPU (dotprod?) | RAM | Local decide (embedding) | Local decide (LLM scorer) | Local generation / tools | STT | TTS | Must stay remote |
|---|---|---|---|---|---|---|---|---|
| HackberryPi CM5 8 GB (4/16 GB similar; 2 GB: embedding only) | 4× A76 2.4 GHz (yes) | 8 GB | **Yes**, ~20–35 ms | Yes, 0.5–1.7B, ~1–2.5 s/turn (E) | **Possible**: Qwen3.5-2B / Qwen3-4B-2507 for single-tool turns with a cached prefix; ~0.6–1.5 s TTFT after cache, 5–14 t/s (E). Quality below 27B | Moonshine Small/Tiny | Piper (Kokoro optional) | Plans, multi-round tools, vision, long answers, web search |
| Zinwa Q25 (Helio G99) | 2× A76 + 6× A55 (yes) | 12 GB | **Yes** | Yes, on the A76 pair | Possible, as CM5 but ~½ the prompt speed with only two big cores (E, W15). Port immature (display/GPU bring-up) | Moonshine | Piper | Same as CM5. MediaTek APU unusable under mainline |
| OnePlus 6 (SD845) | 4× A75 + 4× A55 (yes) | 6/8 GB | **Yes** | Yes, 0.5–1.7B | Marginal: ≤2B single-tool turns (E; no measurement found) | Moonshine / whisper base | Piper | Same as CM5 |
| Librem 5 | 4× A53 1.5 GHz (no) | 3 GB | **Yes**, est. ≤150 ms | No: several s/question (E) and RAM pressure next to the shell and WebKit | **No** | whisper tiny.en or Vosk small (measure) | Piper (low-quality voice) | All generation and tools beyond `local_intent` and handlers |
| PinePhone | 4× A53 1.15 GHz (no) | 2/3 GB | **Yes**, est. ≤250 ms | No | **No** | Vosk small (measure) | Piper low | Same as Librem 5 |
| QEMU simulator | Host-dependent (KVM on aarch64 ≈ native; TCG far slower) | as configured | Yes (functional tests) | Yes on KVM | Functional tests only, not latency | Yes | Yes | n/a: use it to test the plumbing, not the numbers |

## 5. Recommendation

1. **Make Pilot local-first on Marathon.**
   - Order: redact → `local_intent` → local embedding scorer → deterministic handler.
   - Remote Qwen runs only when the local scorer says generation is needed or confidence is low, and only with the existing `text_qa` consent.
   - On the A53 phones that is the whole local story. On A76 devices an optional local LLM handles single-tool and short-answer turns before escalating.
2. **Replace Jev on the device first.** It is on every turn and every notification, it is waitlist-only with unpublished terms, and a 23M-parameter classifier can do its job. Keep `HttpJev` behind config as a comparison backend during calibration, not as the default.
3. **Build speech for Marathon**: `pilot-voice` (whisper.cpp now; evaluate Moonshine on A76) and `pilot-tts` (Piper). Pilot's design already has both; Marathon's packaging omits them.
4. **Keep Groq/Qwen 27B (or the EU Lighthouse tier) as the consented escalation** for plans, vision, long answers and web search. Do not plan around the Preview model's per-org limits; capacity is a procurement question for IT and legal.
5. **Do not ship a local LLM in the base image.** Offer it as an optional download on devices with ≥6 GB and dotprod cores (the pattern `pilot-voice --download` already uses, with a SHA-256 check). Weights: Apache-2.0 only.

### How it slots into pilotd

What exists (J):

- `trait JevClient { decide(&DecideRequest, purpose) -> Answers }` with `JevConfig::{Jev, Score}`.
- `trait LlmClient` (OpenAI chat).
- `[backends.standard|lighthouse]`, switched by `SetBackend`.
- `is_local()` already allows plain `http://127.0.0.1` / `localhost`.

What blocks it today:

- Config parsing rejects any backend name other than `standard` and `lighthouse`.
- `OpenAiClient` drops any reply without `x-pilot-processing-region`, which `llama-server` will never send.
- `local_intent` runs only when offline.

Changes, as a Marathon patch series on `packaging/packages/shoal-pilotd/` (0003+, the way 0001/0002 are carried), each also filed as an upstream request in `docs/upstream/`:

| Patch | Change |
|---|---|
| 0003 `JevConfig::Local` | `kind = "local"` with `model_dir` (embedding GGUF + head file). In-process, through llama.cpp's C API or `llama-server --embedding` on loopback. Answers Choice/Noul/Score from the classifier; dynamic Keel domains by cosine similarity to tool descriptions. Logged as provider `device`, with no egress row |
| 0004 `JevConfig::LlamaScore` (optional, A76) | `ScoreJev`'s prompts over `llama-server /completion` with `n_probs` and `max_tokens: 1`, renormalised over the label tokens. Label token ids come from the server's `/tokenize` at start-up instead of hand-written config |
| 0005 device region | Loopback LLM URLs are stamped `device` by pilotd itself, as 0002's direct mode stamps `us`, and `allowed_regions` accepts `device`. The fail-closed rule is kept for every non-loopback URL |
| 0006 a `local` backend name and routing order | `[backends.local]` accepted next to `standard`/`lighthouse`. `route.rs` tries `local_intent`, then the local scorer, before any remote call (Home Assistant's "prefer local"), and escalates to the remote LLM by the existing §5.2 thresholds |
| 0007 cache-friendly prompt | Stable system prompt and tool block first; hints, memory and time after, so `llama-server` prefix caching (and Groq's, if it has one) hits |
| Packaging | `shoal-pilot-voice` and `shoal-pilot-tts` APKs. Depend on Alpine `whisper.cpp` / `llama.cpp-libs` / `libggml` and `piper-tts`, so nothing is vendored. Check with IT before adding the dependencies; `piper-tts` is in testing |

## 6. Phased plan

| Phase | Scope | Exit criterion |
|---|---|---|
| 0. Measure | Run §7 on the HackberryPi, then Librem 5 and PinePhone (embedding + STT only) | Numbers in this doc moved from E to M |
| 1. Speech | Package `pilot-voice` (whisper.cpp tiny/base) and `pilot-tts` (Piper) for Marathon | Spoken timer turn under 1.1 s end of speech → action (S §13) on CM5; measured on A53 |
| 2. Local decide | 0003 + 0006: embedding scorer for intent, domain, needs_web, needs_generation, ambiguity, triage; `local_intent` first | Agreement with Jev ≥ 95% on intent top-1 and ≥ 90% routing on a synthetic eval set (B5); `--calibrate` correction rate ≤ 5% |
| 3. Local triage on by default | Triage never leaves the device | No Jev egress rows for purpose `triage` |
| 4. Optional local LLM (A76, ≥6 GB) | 0004, 0005, 0007; downloadable Qwen3.5-2B or Qwen3-4B-2507 Q4_0 via `llama-server` user unit | Single-tool turns: valid tool call ≥ 90% on the Pilot tool set; TTFT after cache ≤ 1.5 s on CM5 |
| 5. Remote as escalation only | Groq/Lighthouse used only for plans, vision, long answers, web | Egress log shows remote LLM on a minority of turns |

## 7. Benchmark plan for the HackberryPi CM5

Run on the CM5 with its normal cooling. Record `vcgencmd measure_temp` and `vcgencmd get_throttled` before and after each run, and note the RAM variant. Use the Alpine packages (`apk add llama.cpp llama.cpp-tools whisper.cpp`; subpackage names per W20). Check with IT before installing. Fetch models with `curl -L` from the Hugging Face repos below and check their published SHA-256. Run as the user, without killing the shell. Keep results in `/tmp`.

| ID | What | Files |
|---|---|---|
| B1 | Raw LLM speed | `Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_0.gguf` (reproduces W12), `unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_0.gguf`, `unsloth/Qwen3.5-2B-GGUF/Qwen3.5-2B-Q4_0.gguf`, `unsloth/Qwen3-4B-Instruct-2507-GGUF/Qwen3-4B-Instruct-2507-Q4_0.gguf`, `ibm-granite/granite-4.0-1b-GGUF/granite-4.0-1b-Q4_0.gguf` (all Apache-2.0; filenames checked 2026-10-16) |
| B2 | Long-prompt cost | same models |
| B3 | Prefix-cache TTFT | Qwen3.5-2B and Qwen3-4B-2507 |
| B4 | Scorer latency | Qwen2.5-0.5B, Qwen3.5-0.8B |
| B5 | Embedding classifier | `second-state/All-MiniLM-L6-v2-Embedding-GGUF/all-MiniLM-L6-v2-Q8_0.gguf` (Apache-2.0) |
| B6 | STT | whisper.cpp `ggml-tiny.en.bin`, `ggml-base.en.bin` (from `ggerganov/whisper.cpp`); Moonshine v2 tiny/small streaming (MIT; repo per W21, verify) |
| B7 | TTS | Piper `en_US-lessac-medium.onnx` (`rhasspy/piper-voices`; check the voice's MODEL_CARD licence) |

Commands:

```sh
# B1: pp512/tg128 at 1-4 threads, 3 reps; Q4_0 gets the aarch64 repack
llama-bench -m MODEL.gguf -p 512 -n 128 -t 1,2,3,4 -r 3 -o md

# B2: prompt cost at Pilot's real sizes (pp at depth, not just pp512)
llama-bench -m MODEL.gguf -p 1500,3000 -n 0 -t 4 -r 2 -o md

# B3: server with a persistent prefix
llama-server -m MODEL.gguf -t 4 -c 8192 --host 127.0.0.1 --port 8080 \
  --jinja --slot-save-path /tmp/slots
#  a) POST /v1/chat/completions with Pilot's system prompt + 6 tool schemas
#     + a 50-token user turn; read timings.prompt_ms (cold)
#  b) same request with a different user turn; timings.prompt_ms (warm)
#  c) POST /slots/0?action=save {"filename":"pilot.bin"}, restart, restore, repeat b
#  metrics: cold/warm TTFT, tg t/s, valid-tool-call rate over 50 scripted turns

# B4: one Jev question as a restricted softmax
curl -s 127.0.0.1:8080/completion -d '{"prompt":"You answer with a single label.\nState: {...}\nQuestion: The single action...\nOptions:\nA. alarm\n...\nM. cancel\nAnswer:","n_predict":1,"n_probs":64,"temperature":0,"cache_prompt":true}'
#  metrics: ms per question warm/cold; label mass inside top-64 (should be ~1)

# B5: embeddings
llama-server -m all-MiniLM-L6-v2-Q8_0.gguf --embedding --pooling mean -t 4 --port 8081
#  POST /v1/embeddings for 500 synthetic Pilot utterances: ms/sentence p50/p95;
#  train a logistic head off-device; top-1 agreement vs Jev on the same set

# B6: STT on a 5 s utterance (and Pilot's jfk-ask-not.wav fixture)
whisper-cli -m ggml-tiny.en.bin -f utt.wav -t 4    # also base.en; metric: decode ms, RTF
#  Moonshine: end-of-speech -> final text ms with its streaming example

# B7: TTS first audio and RTF
echo "Timer set for ten minutes." | piper -m en_US-lessac-medium.onnx --output_raw > /dev/null
#  metric: wall time to first byte and total vs audio length

# throughout: peak RSS and power
/usr/bin/time -v <cmd>          # Maximum resident set size
vcgencmd measure_temp; vcgencmd get_throttled
```

Report per model: pp512, tg128 (best thread count), pp at 1,500/3,000, cold and warm TTFT, peak RSS, temperature, throttled flag. Repeat B5 and B6 on the Librem 5 and the PinePhone. Those numbers decide the A53 verdicts, which are estimates today.

## 8. Uncertainties

- **No A53, SD845 or G99 LLM or speech measurements were found.** Every number for those devices is an estimate.
- Most small-model function-calling scores are vendor-reported and mix BFCL v3/v4. Only the W6 rows are comparable with each other.
- The W12 model label is inconsistent (0.5B in the text, "1B / 630M" in the table).
- The Moonshine-vs-Whisper Pi 5 latencies are relayed second-hand (W21). The Whisper Tiny figure there looks long and should be re-measured (B6).
- Groq's limits may differ by plan, and Groq/TypeSafe DPF certification was not checked.
- Jev's retention and region are unknown.
- The Alpine `piper-tts` licence line (MIT archive vs GPL piper1) needs confirming before packaging.
- The local scorer's accuracy on Pilot's own question set is unmeasured. Phase 2's exit criterion exists for that reason.

## 9. Results on the HackberryPi CM5 (2026-10-16)

§7 run on the HackberryPi from 2026-10-16 23:00 to 2026-10-17 03:20 (IST). Every number in this section is **M**, measured in this run, unless tagged otherwise. The Python drivers for B3–B7 are in `scripts/bench/`; B3's prompt file is not, because the prompt and tool specs are Shipwright's (proprietary).

### Setup

| Item | Value |
|---|---|
| Board | Raspberry Pi Compute Module 5 Lite Rev 1.0 (device tree), **16 GB** RAM, not the 8 GB §4 assumed. 4× Cortex-A76, cpufreq 1.5–2.4 GHz, `schedutil`. CPU flags include `asimddp` and `fphp`; no i8mm, no SVE. 4 KiB pages |
| OS | Nura edge, image 26101301, kernel 6.12.85-0-rpi, musl. No `apk` and no package repos, so §7's Alpine packages could not be used |
| Cooling | Passive, in the HackberryPi case. sysfs lists no cooling device (no fan). Screen on, `marathon-shell` running, UI left alone |
| Power | On a charger throughout (battery 15% → 85%), so no energy figure. The under-voltage flag never set |
| llama.cpp | **v0.7.0** (620d222, 2026-10-15). Built in an Alpine edge aarch64 container, gcc 15.2, Release, `GGML_NATIVE=OFF`, `GGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16`, OpenMP, static ggml/llama, KleidiAI off (as Alpine's build). Native musl binaries; `libgomp`, `libstdc++`, `libgcc_s` from the container shipped beside them on `LD_LIBRARY_PATH` |
| whisper.cpp | **v1.9.5** (d1be6fd), same container and flags |
| sherpa-onnx | **v1.13.8** prebuilt `linux-aarch64-shared-cpu` (onnxruntime 1.28.2), glibc. Run through a shipped Fedora glibc 2.43 loader: `glibc/ld-linux-aarch64.so.1 --library-path glibc:lib bin/...` |
| Piper | rhasspy/piper **2023.11.14-2** `piper_linux_aarch64` (the archived MIT line, onnxruntime 1.14.1), same glibc loader. Not Alpine's `piper-tts` 1.7.0 |
| Models | Every file §7 lists exists under that name; SHA-256 matched the Hugging Face LFS oid for all eight GGUF/ggml files and the Piper voice. The GitHub release archives (sherpa-onnx, Moonshine, Piper) publish no checksums and were not verified. Moonshine: sherpa-onnx `moonshine-{tiny,base}-en-quantized-2026-02-27` (Moonshine v2 encoder + merged decoder, int8, MIT). sherpa-onnx publishes no Moonshine "small"; base was used |
| Pilot inputs | Shipwright HEAD 43810f3a: `pipeline.rs::system_prompt` + `capabilities_line`, `system_tools.rs` specs, `jev.rs::ScoreJev::prompt`, pilot.md §5.1 intents |
| Measured with | Temperature: `thermal_zone0` at 1 Hz. Throttling: no `vcgencmd`; cpufreq never shows it (it reported 2.4 GHz at 88 °C), so the firmware's `get_throttled` was read through the `/dev/vcio` mailbox (tag 0x30046), from the Qwen3-4B B2 run onwards. Peak RSS: busybox `time -v`, or `VmHWM` for `llama-server` |

### Thermals

The case cannot hold 4 threads at full speed. A sustained run reaches 80 °C in 2–3 minutes and sits at 85–88 °C; idle after the first hour never fell below 48 °C within the 5-minute cool-down cap, so later runs started at 56–63 °C.

| Run | Length | Peak | Time ≥ 80 °C |
|---|---|---|---|
| B1 Qwen2.5-0.5B | 96 s | 66.1 °C | 0 s |
| B1 Qwen3.5-0.8B | 216 s | 77.7 °C | 0 s |
| B1 Granite 4.0 1B | 328 s | 85.9 °C | 97 s |
| B1 Qwen3.5-2B | 447 s | 87.0 °C | 215 s |
| B1 Qwen3-4B-2507 | 923 s | 88.1 °C | 576 s |
| B2 Qwen3-4B-2507 | 803 s | 88.1 °C | 759 s |

`get_throttled` read 0xe0006 / 0xe0008 at 83–88 °C: ARM frequency capped, throttled, and the soft temperature limit active, now and since boot. No under-voltage bit. So the 3- and 4-thread B1 rows of the three larger models (run last in each sweep), all their B2 rows and both B3 runs are **throttled** numbers. B1's 1- and 2-thread rows ran cooler.

### B1: raw speed (`llama-bench -p 512 -n 128 -t 1,2,3,4 -r 3`)

| Model (Q4_0) | File | pp512 t/s at 1 / 2 / 3 / 4 threads | tg128 t/s at 1 / 2 / 3 / 4 threads | Peak RSS |
|---|---|---|---|---|
| Qwen2.5-0.5B | 403 MiB | 94.5 / 179.6 / 245.8 / **313.5** | 32.7 / **35.6** / 33.3 / 31.5 | 0.78 GiB |
| Qwen3.5-0.8B | 473 MiB | 44.9 / 76.2 / 95.6 / **111.6** | 13.4 / **16.4** / 16.3 / 14.8 | 1.07 GiB |
| Granite 4.0 1B | 926 MiB | 24.6 / 47.5 / 66.2 / **72.1** | 9.8 / **12.2** / 11.7 / 10.4 | 1.92 GiB |
| Qwen3.5-2B | 1.12 GiB | 21.4 / 39.5 / 48.3 / **50.6** | 6.3 / **8.5** / 7.5 / 6.7 | 2.39 GiB |
| Qwen3-4B-Instruct-2507 | 2.21 GiB | 9.3 / 17.1 / 19.3 / **22.2** | 4.0 / **4.4** / 4.0 / 3.8 | 4.54 GiB |

- The 0.5B row reproduces W12 (289.9 pp / 27.3 tg at 4 threads, 33.8 tg at 2) a little faster. `llama-bench` labels the file "qwen2 1B, 630.17 M params" because it counts the embeddings, which explains §8's W12 label inconsistency. Granite 4.0 1B is likewise labelled "2B, 1.63 B".
- Generation is fastest at **2 threads** for every model, so it is bandwidth-bound; 4 threads lose 5–15%.
- **Qwen3.5's hybrid layers are slow on this CPU.** Qwen3.5-0.8B is 2.8× slower at prompts and 2.2× slower at generation than Qwen2.5-0.5B, far more than the size ratio. Qwen3.5-2B runs at about Granite 1B speed.
- Peak RSS is about **2× the file size**. Likely cause: the mmapped GGUF pages stay resident beside the repacked Q4_0 copy (E; `--no-mmap` should avoid it, not tested).
- Against §3.2's estimates: ~4B was put at ~25–30 pp / ~4–5 tg, measured 22.2 (throttled) / 4.4; that holds. The ~1.5B estimate (~80 / ~12–14) is close to Granite 1B's 72 / 12.

### B2: long prompts (`-p 1500,3000 -n 0 -t 4 -r 2`)

| Model | pp1500 t/s | pp3000 t/s | Time to read 1,500 / 3,000 tokens | Peak RSS |
|---|---|---|---|---|
| Qwen2.5-0.5B | 248.3 | 190.9 | 6.0 s / 15.7 s | 0.78 GiB |
| Qwen3.5-0.8B | 107.4 | 98.4 | 14.0 s / 30.5 s | 1.11 GiB |
| Granite 4.0 1B | 66.7 | 39.7 | 22.5 s / 75.6 s (throttled) | 2.12 GiB |
| Qwen3.5-2B | 61.4 | 47.1 | 24.4 s / 63.7 s (throttled) | 2.43 GiB |
| Qwen3-4B-2507 | 20.1 | 15.2 | 74.6 s / 197 s (throttled) | 4.90 GiB |

§3.2's 1,500-token estimates hold or are pessimistic: 0.5B ~5 s → 6.0 s; 2B ~39 s → 24.4 s. Qwen3.5's linear-attention layers lose less speed with depth (0.8B keeps 92% from 1,500 to 3,000 tokens; the dense 0.5B keeps 77%). Reading a Pilot-sized prompt uncached takes 22 s to over 3 minutes on every model above 1B.

### B3: Pilot's prompt, prefix cache, tool calls

`llama-server -t 4 -c 8192 --jinja --slot-save-path` (4 slots, unified KV). System message: `system_prompt` + `capabilities_line` verbatim with the clock frozen, English, no hints. Tools: six `system_tools.rs` specs in pilotd's OpenAI shape (`timer_set`, `alarm_set`, `reminder_create`, `media_control`, `device_toggle`, `device_status`). User message: a context line plus the utterance (≈40–55 tokens). Sampling as pilotd's non-thinking path: temperature 0.7, top_p 0.8, presence_penalty 1.5, `tool_choice: auto`, `enable_thinking: false`, `max_tokens: 100`. The 50 scripted turns each expect one of the six tools; 38 of them have an unambiguous argument value to check. "Valid" means a call to the expected tool whose arguments pass its JSON schema.

| | Qwen3.5-2B | Qwen3-4B-2507 |
|---|---|---|
| Server start to healthy | 3.9 s | 5.1 s |
| Cold turn: prompt tokens, prompt_ms | 1,983, **32.1 s** | 1,839, **78.9 s** |
| Warm, new turn: new tokens, prompt_ms | 54, **1.26 s** | 24, **5.8 s** |
| Slot file; save / restore | 106 MB; 75 / 64 ms | 279 MB; 233 / 131 ms |
| Restart + restore, new turn | 56 tokens, 1.28 s | 26 tokens, 6.4 s |
| 50 turns: new tokens (median), prompt_ms p50 / p95 | 41; 1.27 / 1.49 s | 11; 3.25 / 4.75 s |
| Generation, median | 5.7 t/s | 1.9 t/s (throttled; 4.4 cool in B1) |
| Wall per turn p50 / p95 | 7.8 / 18.6 s | 24.0 / 35.9 s |
| **Valid expected call** | **38/50 (76%)** | **15/50 (30%)** |
| Exactly one call, valid and expected | 34/50 | 14/50 |
| No call at all | 3 | 35 |
| Invalid extra calls | 23 | 0 |
| Right argument values | 26/38 | 12/38 |
| Greedy (temperature 0, no presence penalty): valid / right values | 38/50 / 27/38 | 22/50 / 18/38 |
| Peak RSS (`VmHWM`) | 2.65 GiB | 5.61 GiB |

- **The prefix cache works, including for the hybrid Qwen3.5.** `llama-server` keeps context checkpoints for it and restored three from the slot file, but resumes from the last checkpoint, so each Qwen3.5 turn re-reads ≈41 tokens against ≈11 for dense Qwen3. This settles §3.2's uncertainty.
- Even a 11–24-token warm prompt takes 3–6 s on the 4B: small batches run near generation speed.
- **Pilot's real prompt would never hit the cache.** Line 2 of `system_prompt` is "Today is …, local time HH:MM", so the prefix changes every minute. B3 froze the clock; 0007 has to move the time after the tool block.
- Qwen3.5-2B's errors: every `reminder_create` call came back as `{}`. With the schema's `oneOf` removed, all 8 reminder turns produced arguments (8/8 against the flattened schema, 5/8 against the real one, 2/8 with the right values: "in 20 minutes" became 120 s, "in 45 minutes" 45 s). So the `{}` is llama.cpp's schema-to-grammar handling of `oneOf`, not the model; a local backend needs flattened schemas with the check kept in pilotd. It also tends to repeat calls until `max_tokens` (23 invalid extras), and misses one-word media turns ("play", "pause").
- Qwen3-4B-2507's error is the one the prompt forbids: it answers "Alarm set for 07:00." with no call (35/50). With the flattened reminder schema it still called the tool 1/8 times.
- First attempt used `max_tokens: 200` and was discarded: Qwen3.5-2B filled it with repeated empty calls (≈30 s a turn).

### B4: one Jev question as a restricted softmax

ScoreJev's prompt ("You answer with a single label. State: … Question: … Options: A. alarm … M. cancel" + "Answer:"), `/completion` with `n_predict: 1`, `n_probs: 64`, temperature 0; label mass summed over tokens that strip to A–M. "Pilot order" is ScoreJev's, state first; "reordered" puts the question and options first and the state last, so they form a cacheable prefix. 39 synthetic utterances (3 per intent), then a fresh 39 for the warm rows.

| | Qwen2.5-0.5B | Qwen3.5-0.8B |
|---|---|---|
| Uncached question (≈120 tokens), p50 / p95 | 368 / 394 ms | 888 / 925 ms |
| Warm, Pilot order, new utterance | 331 ms (104 new tokens: only the preamble is shared) | 879 ms (121 new tokens) |
| Warm, reordered, new utterance | **117 ms** (31 new tokens) | 879 ms (121 new tokens: no reuse) |
| Label mass in top 64, median (min), Pilot order | 0.97 (0.88) | 0.71 (0.38) |
| Label mass, reordered | 0.97 (0.82) | 0.05 (0.01) |
| Zero-shot top-1, Pilot order, first / second set of 39 | **18% / 21%** | **44% / 49%** |
| Server peak RSS | 0.80 GiB | 2.76 GiB |

Speed is inside §3.3's estimate (≈0.2–0.5 s a question at 0.5B). In ScoreJev's order the utterance comes second, so almost nothing is reused; the reordered prompt cuts a 0.5B question to 0.12 s. Qwen3.5 reuses nothing either way: its checkpoints do not land inside a 120-token prompt. Zero-shot accuracy is unusable at this size, which §3.1 (W11) predicted. Qwen3.5-0.8B puts little probability on the labels at all once the state comes last. A first cached pass hit the exact prompts the uncached pass had just stored (1 new token each, 33–93 ms), which is why the warm rows were re-run on new utterances.

### B5: embedding classifier

`llama-server --embedding --pooling mean -t 4` with `all-MiniLM-L6-v2-Q8_0.gguf` (25 MB). 507 utterances over the 13 intents, generated from 6 templates per intent with slot fillers and filler prefixes (`scripts/bench/pilot_intents.py`). Logistic regression (384 → 13, plain numpy) trained on the host.

| Metric | Value |
|---|---|
| Server start to healthy | 0.21 s |
| Per sentence, client wall, one request each: p50 / p95 / max | **5.8 / 6.9 / 30.4 ms** (the max is the first request) |
| Peak RSS | 57 MiB |
| Top-1, random 70/30 split (n = 156) | 98.1% |
| Top-1, one template per intent held out (n = 80) | **96.3%** |
| Held-out answers with p ≥ 0.85, and their accuracy | 85%, 100% (unregularised head); 3% with L2 = 1e-3 |

The labels are **synthetic, not Jev's**: Jev is waitlist-only, so "agreement with Jev" could not be measured. Template text is cleaner than real speech, so read 96% as an upper bound. The confidence share depends on how the head is trained, so pilotd's 0.85 threshold has to be recalibrated against each head (`pilotd --calibrate`), not reused.

### B6: speech to text

Utterance: Piper lessac reading "Set a timer for ten minutes, and remind me to call the dentist tomorrow at nine." (4.3 s, 22.05 kHz; both tools resample), plus whisper.cpp's `samples/jfk.wav` (11.0 s). 4 threads, 3 runs each; ranges shown.

| Engine | 4.3 s utterance | RTF | 11 s JFK | RTF | Peak RSS | Text |
|---|---|---|---|---|---|---|
| whisper tiny.en | 1,103–1,127 ms | 0.26 | 1,211–1,212 ms | 0.11 | 175 MiB | Both exact |
| whisper base.en | 2,314–2,354 ms | 0.54 | 2,633–2,712 ms | 0.24 | 283 MiB | "**at** a timer…" on the utterance; JFK exact |
| Moonshine v2 tiny (sherpa-onnx offline) | **188–207 ms** decode; 0.87 s process incl. load | 0.04 | **empty text** | — | 142 MiB | Utterance exact |
| Moonshine v2 base | 362–382 ms decode; 1.5 s process | 0.08 | **empty text** | — | 357–372 MiB | Utterance exact |

- whisper times are `whisper_print_timings` totals, model load (≈90/130 ms) included. Its encoder always processes a 30 s window (≈0.65 s tiny, 1.48 s base), so a short command costs about as much as a long one.
- Moonshine's end-of-speech → final text is the offline decode after the clip ends: **≈0.2 s tiny, ≈0.37 s base**, close to W21's 237 / 527 ms. W21's "Whisper Tiny 5.9 s" is not reproduced: 1.1 s here.
- sherpa-onnx 1.13.8 runs Moonshine v2 only as an offline recogniser, so this is not a streaming measurement. On the 11 s clip both sizes returned empty text (re-encoding the WAV did not help); the first 5.5 s decoded correctly. Use it behind VAD segmentation (sherpa-onnx's `vad-with-offline-asr` path), which commands need anyway.

### B7: text to speech

Piper `en_US-lessac-medium`, a fresh process per sentence (as a `pilot-tts` subprocess would be), `--output_raw` to a pipe, 5 runs each.

| Sentence | Voice load | First byte | Total | Audio (Piper's log) | RTF, synthesis | RTF, wall |
|---|---|---|---|---|---|---|
| "Timer set for ten minutes." | 0.37–0.39 s | 618–637 ms | 646–667 ms | 1.51–1.65 s | 0.14 | 0.36–0.39 (vs bytes received) |
| 90-character calendar answer | 0.37–0.39 s | 1,069–1,110 ms | 1.10–1.14 s | 4.73–4.96 s | 0.14 | 0.22 |

Peak RSS 134 MiB. Piper writes a sentence's audio in one go, so first byte ≈ voice load + the whole first sentence. A resident process would start a short reply in ≈0.22 s (E: synthesis time alone). Synthesis RTF matches W23's 0.12–0.14.

**Voice licence.** The voice's MODEL_CARD names the Blizzard 2013 Lessac dataset. Its licence is a research licence: use "for Research Purposes only", which "excludes … any commercial purpose", non-transferable, no sub-licensing. That probably rules lessac out of a shipped image; legal should confirm and pick a voice whose dataset licence allows redistribution.

### Deviations from §7

- No `apk` on the device: binaries were built (llama.cpp, whisper.cpp) or taken from upstream releases (sherpa-onnx, Piper) instead of Alpine packages, so the versions differ from W20's.
- No `vcgencmd`. Temperature came from sysfs; throttle flags from the firmware mailbox, and only from the Qwen3-4B B2 run onwards. "Near idle" between runs was not reachable; each cool-down waited for < 48 °C or 5 minutes.
- Power not measured: the device charged throughout and no meter was attached.
- B3: (c) restored the slot and then sent a *new* turn, not a repeat of (b). Added a greedy re-run and a flattened-reminder-schema re-run. `max_tokens` 100 (the 200 run was discarded, above).
- B4: "cold" is `cache_prompt: false`; warm rows re-run on unseen utterances; added the reordered prompt. Accuracy is against synthetic labels.
- B5: no Jev agreement (no access); synthetic template set, labels by construction.
- B6: 4.3 s utterance instead of 5 s; Moonshine base instead of "small"; offline, not streaming.
- B7: Piper's own release, not Alpine's; nothing was played.
- Not done: the Librem 5 and PinePhone repeats of B5/B6.

### What this changes

- **Local decide by embedding (§4 "Yes, ~20–35 ms"): confirmed and cheaper.** 6 ms a sentence, 57 MiB, 96% top-1 on held-out phrasings of the 13 intents. Phase 2 stands. It is still synthetic data; the exit criterion against Jev cannot be run while Jev is unavailable, so it has to become a criterion against labelled real utterances from `--calibrate`.
- **Local decide by LLM scorer (§4 "Yes, 0.5–1.7B"): should change to "fast enough, not accurate".** 0.33–0.37 s a question uncached, but 18–23% / 44–49% zero-shot top-1 over two sets of 39. Drop 0004 from the hot path; the embedding head is the local scorer. If 0004 stays as an option, ScoreJev's prompt needs the state moved after the options to cache at all.
- **Local generation and tools (§4 "Possible" on the CM5): should change to "not yet".** Qwen3.5-2B meets Phase 4's TTFT (1.27 s p50 after the cached prefix, ≤ 1.5 s) but reaches 76% valid calls and 26–27/38 right values, against Phase 4's ≥ 90%; Qwen3-4B-2507 reaches 30% (44% greedy) and takes 20–24 s a turn once the case throttles. An uncached turn costs 32 s (2B) or 79 s (4B), so a local backend must restore its slot file at start-up (save/restore costs ≤ 0.25 s) and 0007 is a precondition, not an optimisation. Phase 4 stays optional and should not start before a better small tool model or a fine-tune; any local backend needs flattened tool schemas.
- **STT: Moonshine confirmed for the A76 devices.** Tiny decodes a 4.3 s command in 0.2 s, which leaves almost all of S §13's 1.1 s end-of-speech → action budget; whisper tiny.en at 1.1 s uses the whole budget by itself. Needs VAD segmentation.
- **TTS: Piper confirmed on speed (RTF 0.14); keep it resident** to save the 0.37 s voice load per reply. The default voice choice changes: lessac's dataset licence is research-only.
- **RAM.** This unit has 16 GB. Peak RSS: embedding 57 MiB, Moonshine tiny 142 MiB, Piper 134 MiB, Qwen3.5-2B server 2.65 GiB, Qwen3-4B server 5.61 GiB. §5's "≥ 6 GB" floor for the optional LLM fits a 2B; a 4B on an 8 GB unit next to the shell is tight.
- **Thermals** are now a constraint for any sustained local generation on this case: 85–88 °C and firmware throttling within minutes. The embedding, STT and TTS runs peaked at 64–73 °C.

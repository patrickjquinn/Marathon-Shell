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

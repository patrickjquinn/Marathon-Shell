# VoLTE on Marathon: evaluation and plan

Research of 2026-10-17 for tracker item R23 (review finding 14,
recommendation 14). The question is what Marathon should do about voice
calls on networks that only carry voice over LTE (VoLTE/IMS), now that
2G and 3G are being switched off. The GSMA counts 313 completed, planned
or ongoing 2G/3G switch-offs in 89 countries as of June 2026 [W1].

**Short answer: start with modem-side IMS. Do not adopt imsd yet.**

- On the two Marathon phones with standalone modems (Librem 5 with the
  BroadMobi BM818, PinePhone with the Quectel EG25-G), the modem
  firmware runs the IMS client itself. A VoLTE call reaches the host as
  an ordinary ModemManager `Call` object, and its audio uses the same
  PCM link to the codec as a 2G/3G call. Marathon's
  `TelephonyService` already handles this. What is missing is
  provisioning (IMS on, the right carrier profile), a way to see whether
  IMS is registered, and a clear error when a call fails because it is
  not.
- On the OnePlus 6 (SDM845), the modem also runs IMS, but it needs a
  host-side helper, the IMS Data service, to bring up the IMS PDN.
  `81voltd` (GPL-2.0-or-later, packaged in Debian and Alpine) does
  this. Call audio still goes through the out-of-tree q6voice path.
- imsd (Catcrafts, GPL-3.0-only, vendored by Luma as `src/imsd`) is a
  full IMS client on the host: SIP over IPsec, AMR-WB RTP, PipeWire
  audio. It works for real on one phone, the Fairphone (Gen. 6), on five
  European carriers. It is Qualcomm-only (QMI over QRTR), so it cannot
  help the Librem 5 or the PinePhone. It is unproven on SDM845. It would
  matter for a future Qualcomm device whose modem cannot carry call
  audio. It can also be a fallback on the OnePlus 6 if 81voltd fails
  with a given carrier.
- The HackberryPi has no modem. Nothing changes there.

The smallest first step needs no new code in the shell. It is a
read-only VoLTE check, run on each modem device on a VoLTE-only carrier,
whose results go into `docs/MODEM_TESTING.md` (section 7, Phase 0).

Tags used below: **V** means verified here (read from source, a
package, an API listing or an upstream README); **R** means a community
report not checked here; **E** means an estimate or inference, with the
reasoning given.

## 1. Sources

### Local (read-only, upstream checkout at 0f8b3faf)

| Key | Source | Used for |
|---|---|---|
| L1 | `marathon-services/src/telephonyservice.{h,cpp}` | Call path: ModemManager `Modem.Voice` `CreateCall`/`Start`, `Call.Accept`/`Hangup`/`SendDtmf`, `CallAdded`/`CallDeleted`; `StateReason` is not read |
| L2 | `shell/src/controllers/audioroutingmanager.{h,cpp}` | Call audio: callaudiod `SelectMode` (PinePhone), UCM `VoiceCall` profile switch (Librem 5), libpipewire subscription |
| L3 | `shell/src/managers/modemmanagercpp.cpp` | `AccessTechnologies`, `Voice.EmergencyOnly` already read |
| L4 | `packaging/packages/device-*-marathon/` (APKBUILDs, `device-profile.conf`) | L5: `CALL_AUDIO=ucm-profiles`, MM `broadmobi` plugin, no eg25-manager; PinePhone: `CALL_AUDIO=callaudiod`, eg25-manager via `device-pine64-pinephone`; OnePlus 6: `modemmanager` + pmaports device package |
| L5 | `docs/MODEM_TESTING.md`, `docs/roadmap/TRACKER.md` | Existing field-test plan; R09 (PipeWire), R17 (modem quiesce around suspend) |

### Web

| Key | Source | Date | Licence | Used for |
|---|---|---|---|---|
| W1 | [LINK Mobility: global 2G/3G shutdown](https://www.linkmobility.com/news/the-global-2g-and-3g-shutdown-is-accelerating), [TeleGeography](https://blog.telegeography.com/2g-and-3g-shutdowns-continue) | 2025–2026 | — | Scale of switch-offs |
| W2 | [Catcrafts imsd](https://forgejo.catcrafts.net/Catcrafts/imsd) (README, AGENTS.md, tags) | v1.1.0; last commit 2026-10-16 | GPL-3.0-only | Architecture, D-Bus ABI, verified devices/carriers, limits |
| W3 | [SimplyLuma/luma `src/imsd`](https://github.com/SimplyLuma/luma/tree/main/src/imsd) (README, `LUMA-PROVENANCE.md`) | imported 2026-10-08 | GPL-3.0-only (imsd); repo licence not asserted | Luma copy is Catcrafts 0.3.0 plus FP6 downstream changes |
| W4 | [Lemmy: imsd announcement (TheMightyCat)](https://lemmy.world/comment/24901879) | ~2026-07 | — | First field report; plan to replace 81voltd |
| W5 | [Dylan Van Assche, imsd (reverse-engineering notes)](https://codeberg.org/DylanVanAssche/imsd) | 2024-04 | GPL-3.0 | Earlier, unrelated project of the same name; documentation only |
| W6 | 81voltd: [Debian package](https://packages.debian.org/sid/81voltd), [copyright](https://metadata.ftp-master.debian.org/changelogs//main/8/81voltd/81voltd_1.2.0-2_copyright), [man page](https://dokk.org/manpages/debian/13/81voltd/81voltd.1.en), [pmaports MR 5387 (mirror)](https://ayakael.net/forge/pmaports/commit/5f68d244520c942f35cc780f61cee970ac80e60d) | 1.2.0, 2023–2026 | GPL-2.0-or-later | IMS Data service over QMI/QRTR for SDM845-class |
| W7 | [OnePlus 6T VoLTE with 81voltd (Reddit)](https://redlib.hackliberty.org/r/linux/comments/1e05mlr/oneplus_6_daily_driver/lckfq6z/?context=3) | 2024 | — | **R**: works ~90%, no mute/speaker/BT in calls then |
| W8 | [NLnet: OpenIMSd](https://nlnet.nl/project/VoLTE-Qualcom/), [OpenIMSd blog](https://gitlab.postmarketos.org/modem/openimsd/blog/-/commit/c7b6fbb18a659253d5cd6da1795be6ad8fe0558a) | grant 2024-06 | — | Android-style baseband use; libqmi documentation |
| W9 | ModemManager [NEWS](https://github.com/linux-mobile-broadband/ModemManager/blob/main/NEWS), [introspection](https://github.com/linux-mobile-broadband/ModemManager/tree/main/introspection), [`ModemManager-enums.h`](https://github.com/linux-mobile-broadband/ModemManager/blob/main/include/ModemManager-enums.h), [issue 378 "VoLTE support"](https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/issues/378) | 1.24.2 stable, 1.25.x dev | GPL-2.0+/LGPL | No IMS interface; `apn-type ims` since 1.18 |
| W10 | libqmi [NEWS](https://github.com/linux-mobile-broadband/libqmi/blob/main/NEWS), libmbim [NEWS](https://github.com/linux-mobile-broadband/libmbim/blob/main/NEWS) | libqmi 1.38.0 | LGPL-2.1+ | IMS/IMSA/IMSP services; IMSDCM new in 1.38 |
| W11 | oFono [`doc/ims-api.txt`](https://git.sysmocom.de/sysmocom/ofono/src/branch/master/doc/ims-api.txt) | 2017– | GPL-2.0 | `org.ofono.IpMultimediaSystem` |
| W12 | [Droidian forum: VoLTE and 5G testing](https://forum.droidian.org/t/volte-and-5g-testing/64), [UBports: Qualcomm VoLTE call for testing](https://forums.ubports.com/post/82626) | 2026-01 to 2026-04 | — | ofono-binder ext plugins over the vendor IMS HAL |
| W13 | [Jolla: Beta VoLTE on Xperia 10 III](https://forum.sailfishos.org/t/beta-volte-on-the-xperia-10-iii-disabled-by-default/11492), [Xperia 10 II VoLTE bug](https://forum.sailfishos.org/t/volte-call-is-not-working-on-sony-xperia-10-ii-caller-specific-reproducible/28984) | 2022-05-18; 2025 | proprietary QTI plugin | Sailfish approach |
| W14 | [PINE64: PinePhone modem](https://pine64.org/documentation/PinePhone/Modem/), [eg25-manager PinePhone config](https://gitlab.com/mobian1/eg25-manager/-/blob/master/data/pine64,pinephone-1.2.toml) | current | GPL-3.0 (eg25-manager) | `AT+QCFG="ims",1`, `AT+QMBNCFG`, `QDAI` |
| W15 | [Pine64 forum: Public Mobile VoLTE failure](https://forum.pine64.org/showthread.php?tid=19897), [Quectel forum: EG25-G VoLTE on Australian carriers](https://forums.quectel.com/t/eg25-g-firmware-request-volte-not-registering-on-australian-carriers/56633) | 2024–2026 | — | **R**: firmware and profile dependencies |
| W16 | [Purism: Enable VoLTE](https://docs.puri.sm/Hardware/Librem_5/tips/volte.html), [Reflashing modem firmware](https://docs.puri.sm/Hardware/Librem_5/Maintenance/Modem.html) | current | — | bm818-tools; firmware not public |
| W17 | [pmaports #1905: L5 VoLTE enable/disable](https://gitlab.com/postmarketOS/pmaports/-/work_items/1905) | archived | — | `AT$QCPDPIMSCFGE` sequence |
| W18 | Purism forum: [VoLTE support progress (p.10)](https://forums.puri.sm/t/volte-support-progress/11664?page=10), [(p.20)](https://forums.puri.sm/t/volte-support-progress/11664?page=20), [Sweden 3G shutdown](https://forums.puri.sm/t/phone-calls-stopped-working-when-3g-was-shut-down-in-sweden-need-volte/30030), [IMS status?](https://forums.puri.sm/t/volte-what-is-the-proper-way-to-find-out-the-ims-registration-status-with-the-provider/28584) | 2022–2025-12 | — | **R**: per-carrier, per-firmware results; IMEI allow-lists |
| W19 | [Purism forum: PLS8 availability](https://forums.puri.sm/t/availability-and-price-of-gemalto-pls8-modem/10874), [Tuxphones on the PLS8](https://tuxphones.com/purism-librem5-smartphone-gemalto-pls8-4g-lte-modem-bands-regions-speeds-gps/) | 2020–2021 | — | PLS8 never offered |
| W20 | [Nura (formerly postmarketOS): q6voice project](https://nura.eco/blog/2026/05/08/q6voice-project/), [postmarketOS v22.12](https://postmarketos.org/blog/2022/12/18/v22.12-release/) | 2026-05-08 | — | Qualcomm call audio is still out of tree |
| W21 | [FSF GPL FAQ: mere aggregation](https://www.gnu.org/licenses/gpl-faq.html#MereAggregation), [GPLv3 §6](https://www.gnu.org/licenses/gpl-3.0.html) | — | — | Separate-process boundary; User Product installation information |
| W22 | crates.io API (rows in §6) | read 2026-10-17 | as listed | Rust building blocks |

A naming note: postmarketOS now goes by **Nura** (postmarketos.org
redirects to nura.eco [W20]). imsd's README lists "Nura" as the OS. The
older sources below still say postmarketOS.

## 2. What Marathon does today, and why it fails

**V** (L1–L4):

- `TelephonyService` finds the first ModemManager modem with
  `org.freedesktop.ModemManager1.Modem.Voice`. It then dials with
  `CreateCall` + `Call.Start` and follows `CallAdded`/`CallDeleted` and
  `Call.StateChanged`. It never reads `Call.StateReason`, so a call the
  network refuses looks the same as one the user hung up.
- Call audio is per device (`CALL_AUDIO` in `device-profile.conf`):
  callaudiod `SelectMode(1)` on the PinePhone, a direct UCM `VoiceCall`
  profile switch on the Librem 5 (BM818 PCM through the SAI to the
  WM8962). Both assume the voice samples come from the modem over a
  PCM/I2S link.
- ModemManager has no IMS interface (**V**, W9). The Voice and Call
  D-Bus APIs say nothing about whether a call is VoLTE or circuit
  switched. The only IMS item is the bearer `apn-type` value `ims`,
  added in 1.18 (`MM_BEARER_APN_TYPE_IMS`). Upstream issue 378 ("VoLTE
  support") is still the place where this is discussed. Its page is
  behind a bot wall and was not readable here, so its latest state is
  not confirmed.

So the finding ("ModemManager voice only fails on VoLTE-only carriers")
is half right. ModemManager voice is not the problem on modems that run
IMS internally: their VoLTE calls come through `Modem.Voice` unchanged.
It fails when:

1. IMS is off in the modem, or the wrong carrier profile (MBN) is
   active, so the modem tries circuit-switched fallback (CSFB) to a 3G
   or 2G network that no longer exists. The user sees `dialing ->
   terminated (unknown)`. Librem 5 users on Swedish and French networks
   report exactly this after 3G shutdown (**R**, W18).
2. The carrier refuses IMS registration for the device, for example
   through an IMEI or TAC allow-list. This is outside our control (**R**,
   W18: Canada, US MVNOs).
3. The modem's IMS needs a host-side helper that we do not ship
   (Qualcomm SoC modems: the IMS Data service, §3.2).
4. The modem cannot carry IMS call audio at all, so the IMS client has
   to run on the host (imsd's case, §3.1).

Marathon's current code handles neither 1 nor 3, and it does not tell
the user which of these happened.

## 3. Two architectures

```
(a) Modem-side IMS                         (b) Host-side IMS (imsd)

 Marathon TelephonyService                  Marathon TelephonyService
        | MM Voice (AT/QMI)                        | net.catcrafts.IMS1 (system bus)
 ModemManager                               imsd ── qmicli/QRTR (USIM AKA, P-CSCF)
        |                                    |  └── mmcli: IMS PDN (apn-type ims)
 modem firmware: IMS client, SIP,            |  └── ip xfrm: IPsec SAs to P-CSCF
 AKA, IPsec, RTP, AMR-WB codec               imsd-media (per call): RTP AMR-WB
        | PCM/I2S                                   | PipeWire streams
 SoC audio codec (UCM VoiceCall)            PipeWire/WirePlumber -> earpiece/mic
```

| | (a) Modem-side | (b) Host-side |
|---|---|---|
| Who does SIP/IMS | Modem firmware | Host daemon |
| Host sees | A normal voice call (`+CLCC`, QMI VOICE, MM `Call`) | A D-Bus call object from the IMS daemon |
| Host needs | IMS enabled, carrier profile/MBN, sometimes an IMS PDN helper (Qualcomm SoC: IMSDCM), PCM audio routing | IMS PDN from MM, USIM AKA via the modem, kernel ESP (`ip xfrm`), firewall rules, codec, PipeWire, echo cancellation, wake on IMS traffic |
| Audio | Modem DSP → PCM → codec; modem does echo cancellation | Host RTP → PipeWire; host must add echo cancellation |
| Emergency calls | Firmware's own IMS emergency or CS path | Client must do it; imsd only does `urn:service:sos` over the normal registration (§3.1) |
| Suspend | Modem stays registered and wakes the host with RI/URC | Host must keep re-REGISTER timers and wake on IMS PDN traffic |
| Handover to 2G/3G mid-call (SRVCC) | Firmware | Not available (E) |
| Carrier acceptance | Firmware's IMS client (often carrier-certified) | A new User-Agent the network has not seen; imsd lets you copy the stock string [W2] |
| Code Marathon owns | Small: provisioning + status + error mapping | Large: a second call backend and a host call-audio graph |

### 3.1 imsd (Catcrafts; Luma's `src/imsd`)

**V** (W2, W3):

- Upstream is [forgejo.catcrafts.net/Catcrafts/imsd](https://forgejo.catcrafts.net/Catcrafts/imsd).
  It was created 2026-07-22; the latest tag is v1.1.0 and the latest
  commit 2026-10-16. It is C++26 modules (built with Crafter Build or
  GNU make + clang/libc++), GPL-3.0-only, © Catcrafts. It is
  systemd-only ("There is no OpenRC service") and needs polkit.
- Luma's `src/imsd` is a vendored copy: "Imported commit `9267c02c…`,
  upstream version 0.3.0". Luma added carrier-interop behaviour,
  registration/call recovery, audio-routing hooks and RFC 3840/GSMA
  IR.92 voice-capability tags for the FP6. Most of that looks to have
  gone upstream since: Catcrafts' README now documents the IR.92 Contact
  tags and the resume/handover logic. Luma's repository does not assert
  a top-level licence (GitHub reports `NOASSERTION`). Track
  **Catcrafts upstream**, not the Luma copy.
- Parts: `imsd-core` (pure C++, no I/O, unit-tested against recorded
  traffic), `imsd` (GLib daemon; drives `qmicli`, `mmcli`, `ip`),
  `imsd-media` (a separate process per call: RTP + AMR-WB/AMR/PCMA/PCMU
  codecs loaded with dlopen, PipeWire capture/playout), plus translation
  daemons: `imsd-dialerd` (Plasma's `org.kde.telephony.*`) and
  `imsd-ofonod` (presents an `org.ofono` modem for GNOME Calls).
- D-Bus ABI, declared frozen: `net.catcrafts.IMS1` at
  `/net/catcrafts/IMS1`. Methods `Dial(s)→s`, `HangUp(s)`, `Accept(s)`,
  `SendDtmf(ss)`, `GetCalls()→aa{sv}`, `GetStatus()→a{sv}`. Signals
  `CallAdded(s a{sv})`, `CallStateChanged(s s s)`, `CallDeleted(s)`,
  `RegistrationChanged(b)`. Call control is gated by polkit action
  `net.catcrafts.IMS1.Voice`: the active local session may use it, an
  ssh login may not.
- Requirements: "a Qualcomm modem on a mainline kernel with working
  WWAN/ModemManager integration, kernel ESP, PipeWire, systemd and
  polkit". USIM AKA goes through a UIM logical channel over QMI/QRTR.
  P-CSCF discovery reads the PDN's PCO via QMI WDS. IPv6 IMS PDN only
  (`IMS_IP_TYPE=ipv4` is not supported).
- Verified: Fairphone (Gen. 6) on KPN NL, Telekom Deutschland, Phonero,
  Telia Norge (Linux 7.1.2) and O2 UK (7.2.0), "verified by community
  members". No other device is listed.
- Gaps it states itself: SIM `EF_ECC` is not read (emergency numbers are
  112/911 plus a configured list). Emergency calls are tried as
  `urn:service:sos` on the normal registration, with one fallback to a
  plain INVITE. There is no IMS emergency registration or emergency PDN
  (E, from the description). There are no SIP retransmission timers
  over UDP yet. Incoming calls work only if the network's T-ADS routes
  them to IMS. SMS over IMS, video and VoWiFi are not mentioned (E: not
  implemented).
- The first announcement says imsd "conflicts with 81voltd" and replaces
  it (W4). On a given phone you run one or the other.

Assessment: this is the most complete free host-side IMS client there
is, and it is moving fast (v0.3 to v1.1 in about three months). It is
also one person's project (0 stars, 0 forks on its forge), verified on a
single SoC, and it reaches into the system with root subprocesses and
xfrm/firewall changes. It suits a Qualcomm phone whose modem cannot
carry audio. None of Marathon's current phones is in that position.

### 3.2 81voltd and OpenIMSd (Qualcomm SoC modems)

**V** (W6, W8, W10):

- 81voltd (Richard Acayan; GPL-2.0-or-later; 1.2.0 in Debian sid and
  Alpine testing) is "a server-side implementation of the QMI IMS Data
  service". The modem's own IMS stack asks the host to bring up the IMS
  PDN, and 81voltd forwards those start/stop requests to ModemManager.
  The modem then does SIP/IMS itself, and calls show up through MM Voice
  (that is architecture (a)). Known bugs: stopping the service does not
  release bearers, and MM errors are not passed back to the modem.
- The pmaports MR that added it says it "gets VoLTE working on some
  SDM845 based devices". The author's Pixel 3a worked on Optus but not
  on Telstra (W6). One OnePlus 6T user reports it works about 90% of the
  time (**R**, W7).
- libqmi 1.38.0 added the `IMSDCM` service ("baseband requests for
  packet data connections initiated by the host"), which is the same
  protocol. It also added IMS "Set IMS Services Enabled Setting", and
  earlier `IMS`/`IMSA`/`IMSP` services, with `qmicli
  --imsa-get-ims-registration-status`. So the pieces are going into the
  standard libraries, but not yet into ModemManager.
- OpenIMSd (NLnet NGI Zero Core, from 2024-06) plans the same
  modem-side approach, a "daemon running in parallel to ModemManager"
  that configures the baseband over QMI, so that 2G↔VoLTE handover
  works as it does on Android. No release was found.

### 3.3 oFono, Droidian, Ubuntu Touch, Sailfish (Android RIL/HAL)

**V/R** (W11–W13):

- oFono has had an `org.ofono.IpMultimediaSystem` interface since 2017
  (`Registered`, `VoiceCapable`, `SmsCapable`, `Register()`). It is only
  as good as the modem driver behind it.
- Droidian and Ubuntu Touch run the Android vendor IMS stack (the
  vendor's `imsdaemon`, `ims_rtp_daemon`) inside the Halium container,
  and oFono talks to it through `ofono-binder-plugin` plus a chipset
  extension: `ofono-binder-plugin-ext-qti` (HIDL), `-ext-qti-aidl`,
  `-ext-mtk`. Status on Droidian 102 (2026): works on the ThinkPhone and
  for one Vodafone Romania user. It does not register on the POCO F5. It
  does not re-register after coverage loss until a reboot (**R**).
- Sailfish OS uses the same oFono + binder design. Jolla shipped beta
  VoLTE in 4.4.0.64 (2022-05-18) for the Xperia 10 III only, enabled
  through `IpMultimediaSystem.SetProperty Registration auto`. The
  Qualcomm parts (`ofono-vendor-qti-radio-plugin`, `modem_auto_config`)
  are proprietary.
- Relevance: this route only exists on Halium/Android-vendor devices.
  Marathon is mainline-first. The one Halium candidate is the Zinwa Q25
  (MediaTek; memory notes a Halium/GKI path), where
  `ofono-binder-plugin-ext-mtk` would be the route. That would also mean
  oFono, not ModemManager, on that device. It is out of scope here.

## 4. Per-device assessment

| Device | Modem | Architecture | What is needed | Confidence |
|---|---|---|---|---|
| **PinePhone** | Quectel EG25-G (MDM9607, USB, AT+QMI) | (a) modem-side | Already mostly configured: eg25-manager sets `AT+QCFG="ims",1` and `AT+QDAI="1,1,0,1,0,0,1,1"` at every boot (**V**, W14). Right MBN profile (`AT+QMBNCFG="list"/"select"`; ROW_Generic_3GPP or carrier-specific), current Quectel firmware (Telus fix in R07A08_30.003.30.003, **R** W15). Audio path unchanged (callaudiod). | High that it works on carriers that accept the EG25-G; carrier-dependent |
| **Librem 5** | BroadMobi BM818 (MDM9607-class, USB, AT+QMI) | (a) modem-side | IMS PDP provisioning: `AT+CGDCONT=2,"IPV4V6","ims"`, `AT$QCPDPIMSCFGE=2,1,0,0`, then a modem power-cycle; the setting persists (**V** as documented, W17). Purism ships it on by default on new phones; older or reflashed modems need it (W16). Firmware versions behave differently and are not public (W16, W18). Audio path unchanged (UCM `VoiceCall`). | Medium: many **R** failures on EU networks after 3G shutdown, some from carrier allow-lists |
| Librem 5 (PLS8) | Gemalto/Thales PLS8 | — | Never offered as an option ("not sourced, available, and priced", 2021, W19). Ignore. | — |
| **OnePlus 6** | SDM845 integrated modem (QRTR/rmnet) | (a) modem-side + IMS Data helper; (b) possible | 81voltd as a separate system service after ModemManager. Call audio still needs q6voice (out-of-tree patches + q6voiced) and UCM tweaks (W20). The fallback is imsd, if 81voltd fails with a carrier: it needs IPv6 IMS PDN, ESP in the kernel config, and PipeWire call audio, which would avoid q6voice altogether (E). | Medium for 81voltd (SDM845 reports); low/unknown for imsd (no SDM845 report) |
| **HackberryPi CM5** | none | — | `hasModem=false` already. No work. A USB LTE modem on a future build would fall under (a). | — |
| Zinwa Q25 (note) | MT6789 integrated | Halium only | Not mainline-reachable; see §3.3. | — |

## 5. Licensing and integration boundaries

- **imsd is GPL-3.0-only; Marathon is Apache-2.0.** Running imsd as its
  own process and talking to it over D-Bus keeps the two separate
  programs. The FSF treats "pipes, sockets and command-line arguments"
  as communication between separate programs, unless the exchange is
  intimate enough to make one combined program [W21]. Rules for Marathon:
  never link, vendor or copy imsd source into this repository. Package
  it as its own apk from upstream source (`license="GPL-3.0-only"`). Talk
  only to its D-Bus ABI, from our own code. Do not use its translation
  daemons; Marathon owns its dialer, so it calls `net.catcrafts.IMS1`
  directly.
- **GPLv3 §6 "User Products".** A phone image that includes imsd
  conveys GPLv3 object code in a consumer device. We must then give
  Installation Information: users must be able to install a modified
  imsd that runs. That interacts with R10 (signed app packages) and R11
  (signed OTA). Root access and the ability to install an unsigned apk
  satisfy it today. If Marathon ever locks the OS image, imsd (and any
  other GPLv3 component) needs an explicit exception path. **This needs
  legal review before imsd ships in an image.**
- **81voltd is GPL-2.0-or-later.** It is a separate daemon talking to
  ModemManager. Marathon code never touches it, so there is no
  integration concern.
- **Codecs.** imsd-media dlopens AMR-WB/AMR codecs. The usual free
  implementations are opencore-amr and vo-amrwbenc (both Apache-2.0,
  E: check the exact libraries imsd's APKBUILD pulls). Patent status of
  AMR-NB/AMR-WB is a legal question, not answered here. Modem-side IMS
  avoids it: the codec lives in the modem firmware.
- **polkit / sessions.** imsd lets "the active local session" control
  calls. Marathon's `TelephonyService` runs in the shell process, inside
  the greetd autologin session, so it should pass. Must verify on the
  device that logind marks the Marathon session active on seat0.

## 6. Rust crates worth noting

Patrick's direction is Rust for new core services and established
crates over hand-rolled code. No maintained Rust IMS client exists. The
building blocks below do exist (crates.io, read 2026-10-17, W22):

| Crate | Version | Updated | Licence | Role |
|---|---|---|---|---|
| `ezk-sip-core` / `ezk-sip-ua` | 0.9.2 / 0.9.1 | 2026-07 / 2026-04 | MIT | SIP transaction layer and UA |
| `rsipstack` | 0.7.4 | 2026-10-16 | MIT | SIP stack (RFC 3261) |
| `rvoip` | 0.4.0 | 2026-10-12 | MIT | VoIP stack, young (9k downloads) |
| `rsip` | 0.4.0 | 2022-04 | non-standard | Stale; avoid |
| `sdp-types` | 0.2.0 | 2026-07 | MIT | SDP |
| `rtp` (webrtc-rs) / `ezk-rtp` | 0.17.2 / 0.2.1 | 2026-07 | MIT/Apache-2.0 / MIT | RTP |
| `milenage` | 0.3.1 | 2026-06 | MIT | Milenage (not needed: AKA runs on the USIM) |
| `netlink-packet-xfrm`, `rtnetlink` | 0.5.0, 0.23.0 | 2026-08 | MIT | IPsec SAs/policies, routes without shelling out to `ip` |
| `pipewire` (pipewire-rs) | 0.10.1 | 2026-08 | MIT | Call audio streams |
| `zbus` | 6.0.0 | 2026-10-16 | MIT | D-Bus (MM, imsd) |

Recommendation: **do not write a Rust IMS client.** imsd's AGENTS.md
alone is 1,700 lines of carrier-interop detail (Security-Server
selection, resume across restarts, T-ADS, PCO parsing) learned on live
networks. Re-deriving that would contradict "keep our codebase small",
and we would have no carrier test network. Where Marathon needs new
code (the provisioning/status helper in Phase 1, if it becomes a
service), use `zbus`, plus QMI through `qmicli` or libqmi. That
dependency is already on every device, because ModemManager depends on
it.

## 7. Recommendation and phased plan

**Decision:** modem-side IMS is Marathon's VoLTE architecture for the
current devices. Marathon owns provisioning, status and error reporting
for it. 81voltd is the OnePlus 6 helper. imsd stays an optional
host-side backend: evaluate it on Qualcomm hardware only, and adopt it
only where modem-side IMS cannot carry calls. It is never vendored, and
it is never the only emergency path.

### Phase 0: measure (smallest first step, no shell code)

Write a read-only `scripts/volte-check.sh` (run on the device over ssh)
that prints, per modem:

- `mmcli -m any` state, operator and `access tech`, plus the bearer
  list. Look for an `apn-type ims` bearer on Qualcomm SoC devices.
- With `qmicli -p` (proxy mode, coexists with ModemManager), on the QMI
  port: `--nas-get-system-info` (LTE "IMS voice support" from the
  network), `--imsa-get-ims-registration-status` and
  `--imsa-get-ims-services-status` (if the firmware exposes IMSA; record
  "unsupported" otherwise).
- PinePhone: `AT+QCFG="ims"` (`1,1` means IMS on and VoLTE ready, `1,0`
  means on but not ready, **R** W15), `AT+QMBNCFG="list"`, `AT+QGMR`.
  Librem 5: `AT$QCPDPIMSCFGE?`, `AT+CGDCONT?`, `AT+BMSWVER`. AT commands
  go to the AT port directly (`/dev/ttyUSB2` on the PinePhone,
  `/dev/ttyUSB3` on the L5) only while no call is active. ModemManager's
  `--command` needs MM in debug mode. The script must not change any
  setting.

Run it on each modem device with one SIM from a carrier with no 3G
(and, where available, no 2G), and one from a carrier that still has
2G/3G as a control. Record the results in `docs/MODEM_TESTING.md`.
Success means each device/carrier pair has a known IMS state, so we
know whether we are dealing with failure 1, 2 or 3 from §2.

### Phase 1: provision and report (small, per device + `TelephonyService`)

1. **Provisioning in device packages**, idempotent and reversible:
   - PinePhone: nothing new if Phase 0 shows `1,1`. If the MBN choice is
     wrong, document `AT+QMBNCFG="select",…`. Fix it with an
     eg25-manager config override in `device-pine64-pinephone-marathon`,
     not a new daemon.
   - Librem 5: a one-shot systemd unit in
     `device-purism-librem5-marathon`, conditioned on a stamp file. It
     checks `AT$QCPDPIMSCFGE?`, applies the documented sequence only if
     IMS is off, and asks for one modem restart. Base it on Purism's
     bm818-tools sequence (W16, W17), not on our own guesses.
2. **`TelephonyService` error mapping**: read `Call.StateReason` and the
   modem's `AccessTechnologies` at call start. On a failed outgoing call
   with no LTE IMS (from Phase 0's signals), emit `callFailed` with a
   reason the Phone app can show ("This network needs VoLTE, which isn't
   available on this SIM/modem"). Do not end silently. Tests first: a
   unit test feeding MM-shaped `StateChanged` with each `StateReason`.
3. **Status**: show a `voiceOverLte` state (unknown / registered / not
   registered) in Settings → Mobile network, not in the status bar.
   Source it from IMSA through libqmi in proxy mode where the firmware
   supports it, and leave it "unknown" otherwise. Make it a status
   property, not a new D-Bus service.

Audio: no change. VoLTE calls use the same modem PCM path, so
callaudiod and the UCM `VoiceCall` switch keep working. **R09 hand-off
note:** whatever replaces those in the PipeWire/WirePlumber move must
still support a "modem PCM route" call mode, meaning a hardware
loopback that does not pass through a PipeWire stream. AMR-WB VoLTE
calls may run the PCM link at 16 kHz, which UCM `VoiceCall` must allow
(E: check `QDAI` and the UCM rate on each device in Phase 0).

### Phase 2: OnePlus 6 (81voltd)

- Package `81voltd` (from Alpine testing or Debian 1.2.0) in
  `device-oneplus-enchilada-marathon` as a systemd service ordered after
  `ModemManager.service`.
- Validate call audio first, without VoLTE (q6voice/q6voiced + UCM,
  W20). If circuit-switched call audio does not work on the OnePlus 6,
  VoLTE is the smaller problem.
- Phase 0 check on the device: is an IMS bearer up after attach, and do
  calls show `access tech: lte` throughout?

### Phase 3 (conditional): imsd as a host-side backend

Do this only if a Marathon device needs it: the OnePlus 6 on a carrier
where 81voltd fails, or a new Qualcomm device like the FP6.

- Package Catcrafts imsd from upstream source as its own apk
  (`GPL-3.0-only`, systemd + polkit), after the legal review in §5.
  Make it mutually exclusive with 81voltd (`replaces`/conflict).
- In `TelephonyService`, add a second call path that talks to
  `net.catcrafts.IMS1`. It is used while `RegistrationChanged(true)` /
  `GetStatus` says registered, and MM Voice is used otherwise. Map
  `CallStateChanged` states to the existing `callState` strings, so the
  Phone app, call history, the incoming-call overlay and the sleep
  inhibitor stay unchanged. Emergency dialling stays on MM Voice, which
  reaches the modem's own emergency handling, until a test proves imsd's
  `urn:service:sos` path on that network.
- Audio (coordinate with R09): with imsd there is no modem PCM. Call
  audio is imsd-media's PipeWire capture and playback streams in the
  seat0 user's session. `AudioRoutingManager` must not switch the UCM
  `VoiceCall` profile for these calls. It routes the streams to the
  earpiece/speaker and the handset mic through WirePlumber, and it needs
  echo cancellation (PipeWire `module-echo-cancel`), because the modem's
  DSP canceller is no longer in the path. This needs a new
  `CALL_AUDIO` mode in `device-profile.conf` (for example `host-rtp`).
- Suspend (coordinate with R17): the host must wake for an incoming
  INVITE on the IMS PDN and keep re-REGISTER timers across Doze. imsd
  measures suspend on `CLOCK_BOOTTIME` [W2], but packet wake through
  rmnet/IPA on the target SoC has to be proven.

### Test matrix (who runs what)

The orchestrator owns all on-device runs. No agent here has a modem
device.

| Test | PinePhone | Librem 5 | OnePlus 6 (81voltd) | OnePlus 6 (imsd, Phase 3) |
|---|---|---|---|---|
| Phase 0 check, IMS registered after boot | ✓ | ✓ | ✓ | ✓ |
| Outgoing call stays on LTE (`access tech: lte`; EG25 `+CLCC`, BM818 `AT+BMRAT` reports LTE) | ✓ | ✓ | ✓ | n/a (host SIP) |
| Incoming call while idle and while in Doze (wake path) | ✓ | ✓ | ✓ | ✓ (T-ADS-dependent) |
| Two-way audio, earpiece and speaker, mute, DTMF | ✓ | ✓ | ✓ (q6voice) | ✓ (PipeWire + AEC) |
| SMS send/receive while IMS-registered | ✓ | ✓ | ✓ | ✓ |
| Mobile data off, airplane on/off, SIM PIN, modem restart: re-registers | ✓ | ✓ | ✓ | ✓ |
| Leaving LTE coverage mid-call (SRVCC) on a carrier with 2G | ✓ | ✓ | ✓ | expect drop |
| Emergency: never call a real PSAP. Use the authorised drill process in `MODEM_TESTING.md` Phase 3, or only check `Voice.EmergencyOnly` and that dialling goes to MM | ✓ | ✓ | ✓ | ✓ |

Carriers: at least one network with no 3G and preferably no 2G, which is
the case VoLTE is for. Candidates from the sources: Telekom Deutschland,
KPN, Telia Norge and O2 UK (imsd-verified), US AT&T/T-Mobile (3G gone,
Purism has carrier work there), and Swedish/French networks where L5
users report failures. Pick the networks the testers actually have
SIMs for. Add one network that still has 2G/3G as a control. Record
device firmware (`AT+QGMR`, `AT+BMSWVER`) with every result: firmware
changes the outcome on both EG25-G and BM818 (W15, W18).

### Effort (E)

| Phase | Size | Blocked on |
|---|---|---|
| 0 | One script plus a doc section; ~1 day plus device time | A modem device and a VoLTE-only SIM |
| 1 | Two packaging changes, a `TelephonyService` change with tests, one Settings row; ~3–5 days | Phase 0 results |
| 2 | Packaging plus device validation; q6voice call audio is the unknown | A OnePlus 6 with working call audio |
| 3 | A second call backend, a new audio mode, an apk, legal review; ~2–3 weeks | A device that needs it; R09 call-audio API; legal |

## 8. Risks and open questions

- Carrier allow-lists (IMEI/TAC) can block VoLTE on the BM818 and EG25-G
  whatever the software does (**R**, W18). We cannot fix that in code.
  Users should be told it is a known limitation.
- BM818 firmware is not public; updates come only through Purism
  support (W16). EG25-G firmware is downloadable, but flashing can brick
  the modem (W14).
- ModemManager's lack of an IMS API means our status signal comes from
  vendor-specific AT or QMI. That is fragile, so keep it diagnostic
  only.
- imsd is young and one-maintainer, its emergency path is not a proper
  IMS emergency session, and it is Qualcomm-only. Treat Phase 3 as
  opt-in per device.
- ModemManager issue 378 and OpenIMSd were not readable in full (bot
  walls). Re-check them before Phase 3. If ModemManager gains an IMS
  interface, use it instead of the per-device checks.

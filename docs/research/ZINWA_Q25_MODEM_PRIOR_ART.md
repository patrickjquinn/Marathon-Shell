# Q25 modem prior art, 2026-10-30

The October 17 plan is historical. There is now concrete reusable native CCCI
work to investigate; no reviewed project establishes a drop-in, working native
Q25 modem stack.

## Exact target and current state

The pinned [MT6789 stock device tree](https://github.com/LineageOS/android_kernel_xelex_mt6789/blob/2a873a3511ee0eeead1442e60145093192a4535d/arch/arm64/boot/dts/mediatek/mt6789.dts)
describes MD6295, CCIF plus DPMAIF, and DPMAIF version 1. This is source identity,
not a live modem handshake. Native Q25 currently has no validated firmware
owner, AT/control port, SIM registration or data connection. Its LK modem tag
envelope is absent, and a bounded reserved-tag parser returned `not-validated`.
Neither result establishes empty modem RAM or permits clearing shared memory.

## Useful implementations

| Source and immutable revision | Concrete reuse | Boundary |
| --- | --- | --- |
| [MindOne MT6789 kernel](https://github.com/iasnezhkov/android_kernel_ikko_mindone/tree/9cd73c15f312cfd1e40a22d871de65a2fb2c5791/mindone/modules) | Same-SoC CCIF, ring buffer, DPMAIF-v1 and modem platform code; inspected files GPL-2.0 | Android GKI/vendor dependencies and board-specific secure/memory contracts; reference rather than shipping kernel |
| [Native CCCI owner](https://github.com/MT6895-Mainline/mtk-ccci-userspace/tree/f6147b10cf7ef95932674506fbdfb7f3d67a1067) | Owner lifetime, FS/RPC handling and service separation; GPL-2.0-or-later | Requires working kernel ports; qqcandy storage maps/RPC answers do not establish Q25 compatibility |
| [Native ModemManager fork](https://github.com/MT6895-Mainline/modemmanager-mtk-soc/tree/7b55aa04ad250dec7bd0d2fb5b458cd3df9d0763) | AT/MIPC/CCMNI integration above a ready modem; plugin GPL-2.0-or-later | Build with its matching daemon/private ABI; does not supply firmware boot |
| [Moto CCCI discovery patch](https://github.com/NikuzoKO/pmos-moto-g06-lagos/blob/0d678342004cfd29ae0e5b4113785e73da4a9113/pmaports/modemmanager/0100-support-mediatek-ccci-at-ports.patch) and [bearer/plugin patch](https://github.com/NikuzoKO/pmos-moto-g06-lagos/blob/0d678342004cfd29ae0e5b4113785e73da4a9113/pmaports/modemmanager/0101-plugins-new-mtk-ccci-plugin.patch) | Explicit CCCI AT discovery and PDN/CCMNI integration; retain GPL notices | Motorola startup uses Android-linked services; port identity and commands need Q25 verification |
| [Upstream t7xx core](https://github.com/torvalds/linux/commit/13e920d93e37fcaef4a9309515798a3cae9dcf19) | CCCI framing, handshake/FSM and Linux WWAN design; GPL-2.0-only | PCIe T700/MHCCIF is a different hardware/boot interface; no compatibility by renaming DT nodes |

The [older oFono MTK plugin](https://github.com/rilmodem/ofono/blob/efc9c0a85d32706bc088e449e847be41dcc73b3d/plugins/mtk.c)
is a GRil/RILD socket client, not a native integrated-modem loader. The current
[ModemManager MTK plugin](https://github.com/linux-mobile-broadband/ModemManager/blob/f7da87766cb20a917302961d4b325bad7b909275/src/plugins/mtk/mm-plugin-mtk.c)
also does not supply the missing kernel/bootstrap layer. A bounded mailing-list
search found PCIe t7xx/TMI series, without establishing an upstream integrated
MT6295 driver; this does not prove no other development work exists.

## Implementation order

1. Validate the existing private MD1 backup's container/check-header and memory
   requirements offline. Establish the installed secure-firmware load/auth/remap
   contract before starting the modem; do not infer it from a kernel SMC enum.
2. Compare MindOne's same-SoC CCIF/DPMAIF-v1 code against the pinned Q25 stock
   contracts. Implement ownership, bounded queues, handshake, timeouts and
   exception recovery before exporting control/data endpoints.
3. Adapt the native owner/FS/RPC design to verified Q25 protocol and storage
   contracts. Keep factory calibration private and protected; no guessed RPC
   replies or generic filesystem bridge.
4. Reuse the matching ModemManager integration after actual control transport
   works. Validate SIM, registration, SMS and data independently; voice/audio/IMS
   are further milestones.

No modem driver, firmware, owner or ModemManager replacement was deployed by
this research. Full source/download manifests and private hardware evidence are
retained on the USB build drive outside the repository.

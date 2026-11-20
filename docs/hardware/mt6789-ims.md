# MT6789 IMS: calls, VoLTE and Wi-Fi calling on the Zinwa Q25

## What the modem expects

The Q25's MD1 firmware (MOLY.LR13, "93" generation) runs IMS *over the AP*:
the modem keeps the LTE stack, the IMS PDN, the voice DSP and the codecs,
and expects MediaTek's IMS daemons on the application processor to run SIP,
IMS-AKA, IPsec and the call sessions. The stock vendor image sets
`ro.vendor.md_auto_setup_ims=1`: the modem brings IMS up by itself and talks
to those daemons over dedicated CCCI channels (`/dev/ccci_imsm`, `ccci_imsa`,
`ccci_imsc`, `ccci_imsdc`, `ccci_imsem`, `ccci_imsv`; `ccci_epdg1-4` and
`ccci_ikeraw` for Wi-Fi calling).

With nothing on those channels, plain circuit-switched calls fail too
(verified 2026-11-20 on eir/GoMo, LTE, 2G still on air):

- IMS left on (the default): `ATD<number>;` is never answered. The modem's
  voice-domain selection waits for the IMS side; ModemManager times out after
  90 s and the phone never rings at the other end.
- `AT+EIMS=0`: the same `ATD` is refused at once with `+CME ERROR: 100`,
  also after a radio cycle with the stock RIL's call setup.

The dial itself is not at fault: it is byte-for-byte what the stock RIL
(`libmtk-ril.so`, `RmcCallControlCommonRequestHandler::requestDial`) sends.
Incoming calls over CS fallback work (+EAIC approval, 68c6948f9).

## Prior art

- Ubuntu Touch, Sailfish OS and FuriLabs run MediaTek VoLTE by keeping
  MediaTek's RIL and IMS stack in an Android (Halium) container and driving
  them over binder from oFono (`ofono-binder-plugin-ext-mtk`). Proven on the
  Volla Phone X23, the same MT6789.
- Open IMS clients for mainline Linux phones (`imsd`, `ims-go`, `hyphae`,
  IMSroha) target Qualcomm modems, where the modem only provides an IMS PDN.
  None speaks MediaTek's AP-IMS protocol.

## Design

Marathon keeps ModemManager as its telephony stack and runs MediaTek's IMS
daemons, unmodified, in a minimal sandbox, not a whole Android userspace:

- **Runtime.** At boot `q25-ims-runtime` mounts the phone's own stock
  `system_a`, `vendor_a` and the ART runtime APEX read-only from `super`
  (the same way `q25-md1-firmware` takes the modem image from `md1img`, so
  no blobs are redistributed) and starts each daemon in bubblewrap with only
  the devices and sockets it needs. The daemons are 32-bit bionic binaries;
  the kernel has `COMPAT`, so they run as they are.
- **Properties.** A legacy single-area `/dev/__properties__` written from
  the stock `build.prop` files plus Marathon's IMS settings. Bionic reads it
  as it would the property service's; nothing is preloaded or patched.
- **Logs.** A `logdw` listener turns liblog's records into journal entries.
- **AT channel.** The IMS manager talks AT over a pty that the stock RIL
  serves (`/dev/radio/pttyims`). ModemManager's mtk-ccci plugin serves it
  instead: it forwards the manager's commands on `ttyC0` in its queue and
  routes the IMS URCs (`+EIMS*`, `+EIMSPDN`, `+EPDNHANDOVER`, `+EWFC`, ...)
  to it, so ttyC0 keeps a single owner and no multiplexer is needed.
- **The RIL's IMS duties** (enabling IMS, its configuration, registration
  state, IMS call control) move to the plugin, which exposes them through
  ModemManager's voice and 3GPP interfaces.

## Milestones

1. The IMS manager (`volte_imsm_93`) answers the modem: outgoing calls ring.
2. `volte_imcb`, `volte_ua` and `volte_stack`: IMS registers (`+CIREG: 1`)
   and calls run over VoLTE, media through the modem's DSP.
3. Wi-Fi calling: `wfca` and the ePDG tunnel (IKEv2, SIM authentication).

Every milestone is verified with real calls on the Q25, and data, SMS and
incoming calls keep working at each step.

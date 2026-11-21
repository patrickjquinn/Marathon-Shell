# MT6789 IMS: calls, VoLTE and Wi-Fi calling on the Zinwa Q25

## What the modem expects

The Q25's MD1 firmware (MOLY.LR13, "93" generation) runs IMS *over the AP*:
the modem keeps the LTE stack, the IMS PDN, the voice DSP and the codecs,
and expects MediaTek's IMS daemons on the application processor to run SIP,
IMS-AKA and IPsec. The stock vendor image sets
`ro.vendor.md_auto_setup_ims=1`: the modem's IMS controller (IMC) decides
when to register and brings the IMS PDN up itself, and talks to the daemons
over CCCI channels (`/dev/ccci_imsm`, `ccci_imsc`, ...).

Every voice call goes through the IMC, which picks IMS or circuit switched
(CS fallback to 2G on eir): with nothing on the IMS channels the modem never
answers `ATD`, and with IMS switched off it refuses it (`+CME ERROR: 100`).

## Prior art

- Ubuntu Touch, Sailfish OS and FuriLabs run MediaTek VoLTE by keeping
  MediaTek's RIL and IMS stack in an Android (Halium) container and driving
  them over binder (`ofono-binder-plugin-ext-mtk`), proven on the Volla
  Phone X23 (MT6789). The plugin's IMS turn-on is `setImsCfgFeatureValue`
  (VoLTE), `setWifiEnabled` and `setImsEnabled`; the RIL does the rest.
- Open IMS clients (`imsd`, `ims-go`, `hyphae`) target Qualcomm modems and
  don't speak MediaTek's AP-IMS protocol.
- MediaTek FAQ20977: on a 93 modem the AP side of IMS enablement is
  `AT+EIMSCFG=<volte>,<vilte>,<vowifi>,<viwifi>,<sms>,<ims>`.

## Design

ModemManager stays the telephony stack. MediaTek's IMS daemons run
unmodified, each in a bubblewrap sandbox, from the phone's own stock
partitions (no blobs redistributed).

- **Runtime** (`q25-ims-runtime`): mounts stock `system_a`, `vendor_a` and
  the ART runtime APEX payload read-only from `super` (`q25-lp-map` reads
  liblp's metadata). Units in stock order: `q25-ims-stack`, `-ua`, `-imcb`,
  `-imsm`, after `ccci_mdinit` and before `q25-modem-init` powers the radio,
  as `vendor.volte_md_status=ready` starts them on stock.
- **Sandbox**: only the daemon's own `ccci_ims*` devices; exactly the
  capabilities its stock init `.rc` grants (`volte_stack` NET_ADMIN,
  `volte_imsm_93` NET_RAW + NET_ADMIN, `volte_imcb` WAKE_ALARM) in the host
  user namespace; the host PID namespace, because the IPsec library binds
  its XFRM netlink socket to its pid.
- **Properties** (`q25-ims-props`): a pre-split bionic property area built
  from the stock `build.prop` files, and Android's property service on
  `/dev/socket/property_service` (protocol v2) for the properties the
  daemons set (`vendor.net.ims.volte.pid` before every IPsec SA).
- **Logs** (`q25-ims-logd`): liblog's datagrams into the journal.
- **Operator profile**: the stock RIL enables MediaTek's dynamic SBP at
  start (`AT+EDSBP=2`, from `persist.vendor.radio.mtk_dsbp_support`); the
  modem then selects the SIM's profile (`+ESBPID: 0,168` on eir) and with
  it the IMS settings that let the IMC register.
- **NetAgent** (ModemManager's mtk-ccci plugin, 0108): for a PDN the modem
  brings up itself (`+EIF: <id>, ifup, <type>, <address>`) it brings the
  ccmni up with the network's interface identifier (router advertisements
  for the prefix, no default route), confirms it
  (`AT+EIF=<id>, "ifst", "up"`), reports the global IPv6 address
  (`AT+EIF=<id>, "ipupdate", 2, ...`) and confirms the IMS manager's bearer
  requests (`+EIMSPDN: "notify"` -> `AT+EIMSPDN= "confirm", <aid>, 0`). The
  IMS manager installs the IMS network's policy routing itself.
- **IMS configuration**: `q25-modem-init` sets up the ims APN, reports and
  IMS PDN notifications before radio-on, then `AT+EIMSCFG` after it; the
  plugin sends `AT+EIMSCFG` after each of its radio power-ups. The value is
  the port's udev `ID_MM_MTK_CCCI_IMS_CFG`.
- **IPsec**: `volte_stack` installs the IMS-AKA SAs with XFRM netlink as a
  32-bit task; the kernel needs the upstream fix that drops the compat
  translator requirement where u64 alignment matches (linux-zinwa-q25 0137).
- **Firewall**: ESP on `ccmni*` and what it carries (`meta ipsec exists`)
  are accepted, for SIP from the P-CSCF.

## Status (2026-11-20)

- Outgoing and incoming CS calls work, repeatedly, with call audio.
- IMS: the IMC registers with SBP 168, the IMS PDN comes up, the REGISTER
  reaches eir's P-CSCF and IMS-AKA succeeds through the ISIM; the protected
  REGISTER needs the kernel fix (0137) to install its SAs.
- Wi-Fi calling (`wfca`, ePDG IKEv2) is not started yet.

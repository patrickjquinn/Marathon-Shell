# MP01 e-paper display: binding for the board DTS

The binding is `Documentation/devicetree/bindings/display/panel/minimal,z10-eink.yaml`
from `linux-minimal-mp01`'s
`mp01-0013-dt-bindings-display-panel-Add-the-Minimal-Z10-e-pape.patch`
(vendor prefix `minimal` from `mp01-0001`). The DSI lane order uses
`data-lanes` on the DSI output endpoint, from
`mp01-0009-dt-bindings-display-mediatek-dsi-Describe-the-data-la.patch`.
This note says what the board DTS has to write.

## The model

There is one display node, and it is the Pango CPLD's **I2C** node, at
`&i2c7` address `0x4b`. The CPLD is the DSI sink, so its `port` connects to
`&dsi0`'s output endpoint. There is no DSI child node under `&dsi0`: the
driver finds the DSI host through the graph and registers the DSI device
itself, as I2C-controlled DSI bridges do (`ti,sn65dsi83`, `lontium,lt9611`).
The CPLD and the e-paper are a single fixed unit, so the node is a panel and
not a bridge followed by a panel.

## Node

```dts
/ {
	eink_vdd12: regulator-eink-vdd12 {
		compatible = "regulator-fixed";
		regulator-name = "eink_vdd12";
		regulator-min-microvolt = <1200000>;
		regulator-max-microvolt = <1200000>;
		gpio = <&pio 158 GPIO_ACTIVE_HIGH>;
		enable-active-high;
		regulator-boot-on;
	};

	eink_vdd18: regulator-eink-vdd18 {
		compatible = "regulator-fixed";
		regulator-name = "eink_vdd18";
		regulator-min-microvolt = <1800000>;
		regulator-max-microvolt = <1800000>;
		gpio = <&pio 43 GPIO_ACTIVE_HIGH>;
		enable-active-high;
		regulator-boot-on;
	};

	eink_vdd33: regulator-eink-vdd33 {
		compatible = "regulator-fixed";
		regulator-name = "eink_vdd33";
		regulator-min-microvolt = <3300000>;
		regulator-max-microvolt = <3300000>;
		gpio = <&pio 159 GPIO_ACTIVE_HIGH>;
		enable-active-high;
		regulator-boot-on;
	};
};

&i2c7 {
	clock-frequency = <1000000>;	/* factory value */
	status = "okay";

	display@4b {
		compatible = "minimal,z10-eink";
		reg = <0x4b>;
		vdd12-supply = <&eink_vdd12>;
		vdd18-supply = <&eink_vdd18>;
		vdd33-supply = <&eink_vdd33>;
		reset-gpios = <&pio 85 GPIO_ACTIVE_LOW>;
		backlight = <&frontlight>;	/* optional, see below */
		rotation = <270>;

		port {
			eink_in: endpoint {
				remote-endpoint = <&dsi_out>;
			};
		};
	};
};

&dsi0 {
	status = "okay";
	/* port@1 with ports, or the single port of the old layout */
	...
		dsi_out: endpoint {
			remote-endpoint = <&eink_in>;
			data-lanes = <1 2 4 3>;
		};
};

&mipi_tx0 {
	status = "okay";
};
```

## Rules behind each line

- **Supplies.** The vendor driver switches three GPIOs that it names
  `v12_en` (GPIO158), `v33_en` (GPIO159) and `v18_en` (GPIO43). They are
  load switches, so describe them as `regulator-fixed`. The voltages are
  read from the names and are not measured. Use `regulator-boot-on` because
  LK leaves them on. Do not use `regulator-always-on`, or the panel can
  never power the CPLD down. The driver turns them on in the vendor's
  order: 1.2 V, then 3.3 V, then 1.8 V.
- **Reset.** GPIO85. The factory DT's flag says active high, but the
  vendor drives it low to reset, so write it as `GPIO_ACTIVE_LOW`.
- **No `pm-enable-gpios` / GPIO12.** The factory panel node lists
  GPIO12 as `pm-enable-gpios`, but the vendor panel driver never reads
  it. GPIO12 is also the mtkfb `lcm_led_en` pin state, the NFC
  `nxp,nxpnfc-ven`, and the base DT's `gate_ic@11` power line. Leave it out
  of this node. Whoever owns GPIO12 (most likely the frontlight enable, or
  the NFC VEN) has to be settled on hardware first.
- **No TE.** The link runs in video mode, so GPIO83 (DSI TE) is not used.
- **Lane order.** The vendor panel puts logical lanes 2 and 3 on the
  PHY's lanes 3 and 2: `lane_swap[2] = LANE_3, lane_swap[3] = LANE_2`.
  Following the video-interfaces numbering (the clock lane is 0, the
  data lanes are 1 to 4), that is `data-lanes = <1 2 4 3>` on
  **`&dsi0`'s** endpoint, not on the panel's. The link has four lanes.
  The count in `data-lanes` must match the four that the driver asks for,
  otherwise the DSI host refuses to attach.
- **Rotation.** The picture is scanned out as 800x600 landscape on a
  600x800 portrait panel. LK turns its text with the tops towards x = 0,
  and the chain-loaded U-Boot reads right on the phone with its console
  at rot 3 (270 degrees). `rotation = <270>` is left side up, which DRM
  turns into a 90-degree plane rotation and fbcon's `rotate:3`, the same
  direction.
- **Frontlight.** `mtk_leds` drives "lcd-backlight" through `disp_pwm`.
  A `pwm-backlight` on `&disp_pwm` with `backlight = <&frontlight>`
  makes DRM switch it off on blank. The warm-light PWM is a second LED
  and does not belong in this node.
- **Boot handoff.** LK's framebuffer is 800x600 a8r8g8b8 at `0xffa23000`
  with a stride of 3200. The simple-framebuffer node and its
  power-domain and clock list follow the Q25's patch 0040 pattern. If the
  three supplies are on at probe, the driver keeps the CPLD as LK left it
  and does not reset it.

## Register map the driver keeps (I2C 0x4b)

| Reg | Access | Meaning |
|---|---|---|
| 0x80 | R | CPLD firmware version (0x36 on current stock) |
| 0x84 | R | waveform table version |
| 0x88 | R | CPLD id |
| 0x89 | R | display switch |
| 0x8a | R | VCOM |
| 0x8b | R | clean state |
| 0x8c | RW | waveform 0-3 |
| 0x8d | R | refresh state |
| 0x8e | W | command: only 0x05 (clear) is ever written |
| 0x8f | R | NTC temperature |

The driver sends nothing else. The Pango configuration opcodes share the
address: 0x10/0x11/0x12 erase, 0x20/0x21 program, 0x30/0x31 read flash,
0x40 lock, 0x50 configure, 0x51/0x52 write enable and disable, 0x60
reset, 0x70/0x71 flash sleep and wake, 0xa1-0xa5 ID and status reads,
and 0xff NOP. The driver cannot address any of them.

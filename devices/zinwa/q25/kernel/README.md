The ADC patch targets `drivers/iio/adc/mt6359-auxadc.c` in the Q25 kernel source
based on `978b8b672d68e43b08c891132b974255489889aa`.

Its scale omitted the ADC resolution. On MT6358 BATADC, raw code 25383 was
reported with scale 5400 instead of 5400/32768 mV per count. The generic battery
driver's subsequent conversion overflowed. The patch also rejects an absent
channel descriptor's zero denominator. It changes no sampling, charger, voltage
limit, DT or GPU policy.

The rebuilt EFI was tested on the Q25: scale became `0.164794921`, reported
battery voltage was 4.182–4.183 V, and the full GPU session booted successfully.
Kernel configuration, release and all 12,440 exported-symbol CRC records matched
the prior working kernel. This does not supply state of charge or establish
physical calibration.

Tested EFI SHA256:
`e4c19e018b4f473e702af6eebc1aa57c40997ac1c960611ac5637cae92bca149`.
The prior `7d06cd6f…` kernel, `23e3f8d4…` carrier initrd and `f668fc23…` DT remain
available as the working fallback.

This patch records the tested bring-up change. It is not yet applied by the
canonical kernel APK recipe; the existing `7.0-r1000` package must not be assumed
to contain it.

# Camera pipeline: fast preview, then computational photography

Status: plan (2026-11-03), Zinwa Q25 first. Targets: 30 fps preview,
shutter lag under 150 ms, cold start under 1 s, in Marathon Camera and in
Android apps through Deckard.

## Where the time goes today (measured on the Q25)

- **Sensor mode.** For any preview the rear S5KJN1 runs its 4080x3072
  (12.5 MP, 2x2-binned) mode: libcamera's simple pipeline picks the
  smallest mode that covers the output, and our driver has only that one.
  MediaTek's own driver also streams 4080x3060 everywhere, but feeds it to
  the hardware ISP, which we do not have.
- **Debayer.** SoftISP's GPU debayer (libcamera 0.8 with eGL) takes 42 ms
  a frame at that size on the Mali-G57: about 24 fps at best, before the
  rest of the pipeline. Its input is not imported as a dmabuf: the CAMSV
  buffer's stride is not what Mesa wants ("WSI pitch not properly aligned",
  "Importing input DMABuf failed, falling back to upload"), so every raw
  frame is copied into a texture first.
- **Cold start.** The first frame comes 350-400 ms after streaming starts
  (rear), on top of libcamera enumeration and the EGL context.
- **Deckard.** Frames reach Android as dmabufs with one RGBA→I420 pass on
  the CPU (not yet measured on its own); Android-side preview was further throttled
  by composer faults, fixed in Marathon-Deckard image patch 0009.

## Preview path

1. **A preview sensor mode** (kernel, camera bring-up): add the S5KJN1's
   4x4-binned 2040x1536 mode (MediaTek's driver carries a 2000x1500 table,
   disabled) and keep 4080x3072 for stills. A quarter of the pixels cuts the
   debayer to about 10 ms and the upload with it. The front IMX111 already
   has a 1280x720 mode. Then libcamera needs no change: it picks the
   smaller mode for a 1080p-or-less viewfinder.
2. **Zero-copy raw input** (kernel): give CAMSV a stride Mesa accepts
   (64-byte aligned, which the driver ignores today) so the debayer imports
   the raw buffer instead of uploading it.
3. **Still capture at full resolution:** a second libcamera configuration
   (StillCapture role, 4080x3072) used only for the shot, switched without
   tearing the session down; the viewfinder keeps the binned mode. Shutter
   lag then is one mode switch plus one frame unless we keep a ring of
   full-resolution raw frames (see ZSL below). Today Marathon Camera
   restarts the stream at the photo size and waits 8 frames for the
   exposure to settle.
4. **GPU ISP, not CPU:** we already use libcamera's GPU path (eGL debayer);
   its upstream work (statistics and colour correction on the GPU) is
   still landing, so we follow upstream rather than fork. Black level, lens
   shading and a tuned CCM for both sensors (tuning files; today both use
   `uncalibrated.yaml`) are what make the picture good.
5. **dmabuf end to end:** Deckard passes libcamera's buffers to the HAL as
   dmabufs. Marathon Camera takes them through Qt's GStreamer backend;
   whether they stay dmabufs to the screen there needs measuring.
   Next for Deckard: let the HAL hand an RGBA preview to Android's PRIVATE
   stream directly (no I420 pass) and keep I420 only for YUV and JPEG
   streams.
6. **Cold start:** keep a libcamera CameraManager warm in the camera
   service (one process for Marathon Camera and Deckard, see
   2026-11-03-camera-broker.md) so opening skips enumeration; prepare the
   EGL context before the first frame.

## Computational photography, on this SoC

The G99 has no usable hardware ISP or NPU for us, so everything runs on the
Mali-G57 (GLES 3.1 compute through Panfrost) and the A76 cores.

- **Multi-frame denoise and HDR (feasible, first):** keep a ring of 4-8
  raw frames at the binned size, align on the GPU (tile-based, as in
  HDR+), merge in the raw domain, then tone-map. At 2040x1536 this fits in
  a second or two after the shutter; at full 4080x3072, a few seconds. This
  also gives zero-shutter-lag: the shot is taken from frames already in the
  ring.
- **Night mode (feasible, second):** the same merge with longer exposures
  and more frames (needs manual exposure control through libcamera, which
  SoftISP's AGC must allow), with a steadiness hint from the IMU.
- **Portrait/segmentation, super-resolution zoom (later):** need a small
  neural net; CPU inference at preview rate is not realistic; on stills,
  possible with a few hundred ms per shot.

## What can land when

- **Today:** nothing that changes speed. Deckard's camera fixes (composer,
  buffers) make Android preview visible and as fast as the host delivers;
  the host is the bottleneck (about 24 fps rear at 12.5 MP, 30 fps front).
- **Days:** the binned preview mode (kernel driver table plus testing),
  tuning files for both sensors, RGBA preview path in Deckard's HAL.
  Expected: 30 fps preview on both cameras.
- **Weeks:** zero-copy raw input (CAMSV stride), still-capture role switch,
  warm camera service; shutter lag and cold start near target.
- **Months:** raw ring buffer with multi-frame merge (HDR/denoise, then
  night mode), on GPU compute.

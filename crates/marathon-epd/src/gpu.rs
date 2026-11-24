//! The engine as a GLES 3.1 compute pass (`tcon.comp`), on a surfaceless EGL context.
//!
//! State, net drive and the tables stay in GPU buffers across ticks; each tick uploads the
//! target and reads back the drive and the stats. On the phone the drive buffer would be the
//! scanout buffer itself and the readback goes away.

use std::fmt;

use glow::HasContext;
use khronos_egl as egl;

use crate::engine::{drive_len, Dc, Params, Stats};
use crate::waveform::Lut;

const SHADER: &str = include_str!("tcon.comp");
const EGL_PLATFORM_SURFACELESS_MESA: egl::Enum = 0x31DD;

#[derive(Debug)]
pub enum GpuError {
    /// No usable EGL/GLES 3.1 device.
    Unavailable(egl::Error),
    Gl(String),
}

impl fmt::Display for GpuError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            GpuError::Unavailable(e) => write!(f, "gpu: egl: {e}"),
            GpuError::Gl(e) => write!(f, "gpu: {e}"),
        }
    }
}

impl std::error::Error for GpuError {}

impl From<egl::Error> for GpuError {
    fn from(e: egl::Error) -> Self {
        GpuError::Unavailable(e)
    }
}

impl From<String> for GpuError {
    fn from(e: String) -> Self {
        GpuError::Gl(e)
    }
}

const STATE: u32 = 0;
const DC: u32 = 1;
const TARGET: u32 = 2;
const DRIVE: u32 = 3;
const CODES: u32 = 4;
const LENS: u32 = 5;
const STATS: u32 = 6;

pub struct GpuEngine {
    display: egl::Display,
    context: egl::Context,
    gl: glow::Context,
    program: glow::Program,
    buffers: [glow::Buffer; 7],
    pub width: usize,
    pub height: usize,
    pub renderer: String,
}

fn bytes<T: Copy>(v: &[T]) -> &[u8] {
    // SAFETY: only called with u32/i8/u8 slices, which have no padding or invalid bit patterns.
    unsafe { std::slice::from_raw_parts(v.as_ptr().cast::<u8>(), std::mem::size_of_val(v)) }
}

impl GpuEngine {
    /// # Panics
    /// If `width` is not a multiple of 16.
    pub fn new(width: usize, height: usize, lut: &Lut) -> Result<Self, GpuError> {
        assert!(
            width.is_multiple_of(16),
            "width {width} is not a multiple of 16"
        );
        let api = &egl::API;
        // SAFETY: the surfaceless platform takes no native display.
        let display = unsafe {
            api.get_platform_display(
                EGL_PLATFORM_SURFACELESS_MESA,
                egl::DEFAULT_DISPLAY,
                &[egl::ATTRIB_NONE],
            )
        }?;
        api.initialize(display)?;
        api.bind_api(egl::OPENGL_ES_API)?;
        // Surfaceless displays may list no configs at all; EGL_KHR_no_config_context covers that.
        let config = match api.choose_first_config(
            display,
            &[egl::RENDERABLE_TYPE, egl::OPENGL_ES3_BIT, egl::NONE],
        )? {
            Some(c) => c,
            // SAFETY: EGL_NO_CONFIG_KHR is the null config handle.
            None => unsafe { egl::Config::from_ptr(std::ptr::null_mut()) },
        };
        let context = api.create_context(
            display,
            config,
            None,
            &[
                egl::CONTEXT_MAJOR_VERSION,
                3,
                egl::CONTEXT_MINOR_VERSION,
                1,
                egl::NONE,
            ],
        )?;
        api.make_current(display, None, None, Some(context))?;
        // SAFETY: the context is current on this thread; EGL returns GLES entry points.
        let gl = unsafe {
            glow::Context::from_loader_function(|s| {
                api.get_proc_address(s)
                    .map_or(std::ptr::null(), |f| f as *const std::ffi::c_void)
            })
        };
        // SAFETY: plain GL object creation and uploads on the current context.
        unsafe {
            let renderer = gl.get_parameter_string(glow::RENDERER);
            let program = compile(&gl)?;
            let mut buffers = Vec::new();
            for _ in 0..7 {
                buffers.push(gl.create_buffer()?);
            }
            let buffers: [glow::Buffer; 7] = buffers
                .try_into()
                .map_err(|v: Vec<_>| GpuError::Gl(format!("{} buffers", v.len())))?;
            let n = width * height;
            let lens: Vec<u32> = lut.lens.iter().map(|&l| u32::from(l)).collect();
            let sizes: [(u32, Vec<u8>); 7] = [
                (STATE, vec![0; n * 4]),
                (DC, vec![0; n]),
                (TARGET, vec![0; n]),
                (DRIVE, vec![0; drive_len(width, height)]),
                (CODES, bytes(&lut.codes).to_vec()),
                (LENS, bytes(&lens).to_vec()),
                (STATS, vec![0; 20]),
            ];
            for (idx, data) in &sizes {
                let b = buffers[*idx as usize];
                gl.bind_buffer(glow::SHADER_STORAGE_BUFFER, Some(b));
                gl.buffer_data_u8_slice(glow::SHADER_STORAGE_BUFFER, data, glow::DYNAMIC_DRAW);
                gl.bind_buffer_base(glow::SHADER_STORAGE_BUFFER, *idx, Some(b));
            }
            gl.use_program(Some(program));
            let set = |name: &str, v: u32| {
                gl.uniform_1_u32(gl.get_uniform_location(program, name).as_ref(), v);
            };
            set("uWords16", u32::try_from(width / 16).unwrap_or(0));
            set("uHeight", u32::try_from(height).unwrap_or(0));
            set("uLutWords", u32::try_from(lut.words).unwrap_or(0));
            Ok(Self {
                display,
                context,
                gl,
                program,
                buffers,
                width,
                height,
                renderer,
            })
        }
    }

    /// # Panics
    /// If `state` does not match the panel size.
    pub fn upload_state(&self, state: &[u32], dc: &[Dc]) {
        assert_eq!(state.len(), self.width * self.height);
        self.write(STATE, bytes(state));
        self.write(DC, bytes(dc));
    }

    pub fn download_state(&self, state: &mut [u32], dc: &mut [Dc]) {
        let mut raw = vec![0u8; state.len() * 4];
        self.read(STATE, &mut raw);
        for (s, b) in state.iter_mut().zip(raw.as_chunks::<4>().0) {
            *s = u32::from_le_bytes(*b);
        }
        let mut raw = vec![0u8; dc.len()];
        self.read(DC, &mut raw);
        for (d, b) in dc.iter_mut().zip(raw) {
            *d = b.cast_signed();
        }
    }

    /// Dispatches one tick and waits for it.
    ///
    /// # Panics
    /// If `target` does not match the panel size.
    pub fn dispatch(&self, target: &[u8], p: &Params) {
        assert_eq!(target.len(), self.width * self.height);
        self.write(TARGET, target);
        let mut stats = [0u32; 5];
        stats[3] = u32::MAX;
        self.write(STATS, bytes(&stats));
        let gl = &self.gl;
        // SAFETY: uniforms and a dispatch on the current context with all buffers bound.
        unsafe {
            let set = |name: &str, v: u32| {
                gl.uniform_1_u32(gl.get_uniform_location(self.program, name).as_ref(), v);
            };
            set("uAllowGrey", u32::from(p.allow_grey));
            set("uQuietFrames", p.quiet_frames);
            set("uQuietBonus", p.quiet_bonus);
            set("uGreyRewindMax", p.grey_rewind_max);
            set("uBinTable", p.bin_table);
            set("uGreyTable", p.grey_table);
            set("uRepay", u32::from(p.repay));
            gl.uniform_1_i32(
                gl.get_uniform_location(self.program, "uWhiteDc").as_ref(),
                p.white_dc,
            );
            let gx = u32::try_from((self.width / 16).div_ceil(8)).unwrap_or(0);
            let gy = u32::try_from(self.height.div_ceil(8)).unwrap_or(0);
            gl.dispatch_compute(gx, gy, 1);
            gl.memory_barrier(glow::BUFFER_UPDATE_BARRIER_BIT);
            gl.finish();
        }
    }

    pub fn tick(&self, target: &[u8], p: &Params, drive: &mut [u8]) -> Stats {
        self.dispatch(target, p);
        self.read(DRIVE, drive);
        let mut raw = [0u8; 20];
        self.read(STATS, &mut raw);
        let w = |i: usize| {
            u32::from_le_bytes([raw[4 * i], raw[4 * i + 1], raw[4 * i + 2], raw[4 * i + 3]])
        };
        Stats {
            active: w(0),
            pending: w(1),
            driven: w(2),
            row_min: w(3),
            row_max: w(4),
        }
    }

    fn write(&self, idx: u32, data: &[u8]) {
        // SAFETY: buffer `idx` was allocated with at least `data.len()` bytes.
        unsafe {
            self.gl.bind_buffer(
                glow::SHADER_STORAGE_BUFFER,
                Some(self.buffers[idx as usize]),
            );
            self.gl
                .buffer_sub_data_u8_slice(glow::SHADER_STORAGE_BUFFER, 0, data);
        }
    }

    fn read(&self, idx: u32, out: &mut [u8]) {
        let len = i32::try_from(out.len()).unwrap_or(i32::MAX);
        // SAFETY: maps `len` bytes of a buffer at least that large for reading; the mapping is
        // copied out and released before returning.
        unsafe {
            self.gl.bind_buffer(
                glow::SHADER_STORAGE_BUFFER,
                Some(self.buffers[idx as usize]),
            );
            let p =
                self.gl
                    .map_buffer_range(glow::SHADER_STORAGE_BUFFER, 0, len, glow::MAP_READ_BIT);
            assert!(!p.is_null(), "glMapBufferRange failed");
            std::ptr::copy_nonoverlapping(p, out.as_mut_ptr(), out.len());
            self.gl.unmap_buffer(glow::SHADER_STORAGE_BUFFER);
        }
    }
}

/// # Safety
/// `gl` must be current on this thread.
unsafe fn compile(gl: &glow::Context) -> Result<glow::Program, GpuError> {
    // SAFETY: the caller guarantees a current context.
    unsafe {
        let shader = gl.create_shader(glow::COMPUTE_SHADER)?;
        gl.shader_source(shader, SHADER);
        gl.compile_shader(shader);
        if !gl.get_shader_compile_status(shader) {
            return Err(GpuError::Gl(format!(
                "compile: {}",
                gl.get_shader_info_log(shader)
            )));
        }
        let program = gl.create_program()?;
        gl.attach_shader(program, shader);
        gl.link_program(program);
        if !gl.get_program_link_status(program) {
            return Err(GpuError::Gl(format!(
                "link: {}",
                gl.get_program_info_log(program)
            )));
        }
        gl.delete_shader(shader);
        Ok(program)
    }
}

impl Drop for GpuEngine {
    fn drop(&mut self) {
        // SAFETY: deleting our own objects on the still-current context.
        unsafe {
            for b in self.buffers {
                self.gl.delete_buffer(b);
            }
            self.gl.delete_program(self.program);
        }
        let api = &egl::API;
        api.make_current(self.display, None, None, None).ok();
        api.destroy_context(self.display, self.context).ok();
    }
}

#[cfg(test)]
#[allow(
    clippy::panic,
    clippy::cast_possible_truncation,
    clippy::many_single_char_names,
    clippy::print_stderr,
    clippy::similar_names,
    reason = "tests"
)]
mod tests {
    use super::*;
    use crate::engine::{idle_state, pack, target, CpuEngine, CLASS_AUTO, STAGE_DONE};
    use crate::waveform::EngineWaveform;

    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u32 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            (self.0 >> 32) as u32
        }
    }

    fn gpu(w: usize, h: usize, lut: &Lut) -> Option<GpuEngine> {
        match GpuEngine::new(w, h, lut) {
            Ok(g) => Some(g),
            // No EGL device (CI containers): the comparison cannot run here.
            Err(GpuError::Unavailable(e)) => {
                eprintln!("skipping GPU test: {e}");
                None
            }
            Err(e) => panic!("{e}"),
        }
    }

    /// Random valid states, random targets with bursts of change, random parameters: the GPU
    /// must match the CPU reference bit for bit on state, net drive, drive bytes and stats.
    #[test]
    fn gpu_matches_cpu_bit_exactly() {
        let wf = EngineWaveform::reference();
        let (w, h) = (160, 96);
        let Some(g) = gpu(w, h, &wf.lut) else { return };
        eprintln!("renderer: {}", g.renderer);

        let mut rng = Rng(0x9E37_79B9_7F4A_7C15);
        let base = Params::new(&wf, 0);
        let mut cpu = CpuEngine::new(w, h, 15, &base);
        for (s, d) in cpu.state.iter_mut().zip(cpu.dc.iter_mut()) {
            let lvl = rng.next() % 16;
            *s = if rng.next().is_multiple_of(3) {
                idle_state(lvl)
            } else {
                pack(
                    lvl,
                    rng.next() % 16,
                    0,
                    STAGE_DONE,
                    0,
                    rng.next() % 16,
                    rng.next() % 16,
                )
            };
            *d = (rng.next() % 61) as i8 - 30;
        }
        g.upload_state(&cpu.state, &cpu.dc);
        let mut tg: Vec<u8> = (0..w * h)
            .map(|_| target(rng.next() % 16, rng.next().is_multiple_of(2), CLASS_AUTO))
            .collect();
        let (mut dc, mut dg) = (vec![0u8; drive_len(w, h)], vec![0u8; drive_len(w, h)]);
        let (mut sg, mut dcg) = (vec![0u32; w * h], vec![0i8; w * h]);
        for tick in 0..400 {
            if tick % 7 < 3 {
                for t in &mut tg {
                    if rng.next().is_multiple_of(6) {
                        *t = target(
                            rng.next() % 16,
                            rng.next().is_multiple_of(2),
                            rng.next() % 4,
                        );
                    }
                }
            }
            let p = Params {
                allow_grey: !rng.next().is_multiple_of(4),
                quiet_frames: rng.next() % 16,
                quiet_bonus: if rng.next().is_multiple_of(10) {
                    rng.next() % 40
                } else {
                    0
                },
                grey_rewind_max: rng.next() % 30,
                repay: !rng.next().is_multiple_of(5),
                ..base
            };
            let a = cpu.tick(&tg, &p, &wf.lut, &mut dc);
            let b = g.tick(&tg, &p, &mut dg);
            assert_eq!(a, b, "stats, tick {tick}");
            assert!(dc == dg, "drive, tick {tick}");
            if tick % 50 == 49 {
                g.download_state(&mut sg, &mut dcg);
                assert!(sg == cpu.state, "state, tick {tick}");
                assert!(dcg == cpu.dc, "dc, tick {tick}");
            }
        }
    }
}

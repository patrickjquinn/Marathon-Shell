//! `MarathonOS.Terminal`: `TerminalEngine` backed by `alacritty_terminal` and a POSIX PTY.

use std::ffi::{CString, OsString};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::ffi::OsStringExt;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::grid::Dimensions;
use alacritty_terminal::index::{Column, Line, Point, Side};
use alacritty_terminal::selection::{Selection, SelectionType};
use alacritty_terminal::term::cell::{Cell, Flags};
use alacritty_terminal::term::{Config, Term};
use alacritty_terminal::vte::ansi::{Color, NamedColor, Processor};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString, QStringList};

#[cxx_qt::bridge(namespace = "marathon::terminal")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, running, READ, NOTIFY = running_changed)]
        #[qproperty(bool, failed, READ, NOTIFY = running_changed)]
        #[qproperty(QString, title, READ, NOTIFY = title_changed)]
        type TerminalEngine = super::TerminalEngineRust;

        #[qsignal]
        #[cxx_name = "runningChanged"]
        fn running_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "titleChanged"]
        fn title_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn finished(self: Pin<&mut Self>, exit_code: i32);
        #[qsignal]
        #[cxx_name = "screenChanged"]
        fn screen_changed(self: Pin<&mut Self>);

        #[qinvokable]
        fn start(self: Pin<&mut Self>);
        #[qinvokable]
        fn terminate(self: Pin<&mut Self>);
        #[qinvokable]
        #[cxx_name = "sendInput"]
        fn send_input(self: &Self, text: &QString);
        #[qinvokable]
        #[cxx_name = "sendKey"]
        fn send_key(self: &Self, key: i32, text: &QString, modifiers: i32);
        #[qinvokable]
        fn resize(self: Pin<&mut Self>, cols: i32, rows: i32);
        #[qinvokable]
        #[cxx_name = "recentLines"]
        fn recent_lines(self: &Self, count: i32) -> QStringList;

        #[cxx_name = "historyLines"]
        fn history_lines(self: &Self) -> i32;
        fn cols(self: &Self) -> i32;
        fn rows(self: &Self) -> i32;
        #[cxx_name = "cursorX"]
        fn cursor_x(self: &Self) -> i32;
        #[cxx_name = "cursorY"]
        fn cursor_y(self: &Self) -> i32;
        fn select(self: Pin<&mut Self>, start_x: i32, start_y: i32, end_x: i32, end_y: i32);
        #[cxx_name = "clearSelection"]
        fn clear_selection(self: Pin<&mut Self>);
        #[cxx_name = "selectedText"]
        fn selected_text(self: &Self) -> QString;
        #[cxx_name = "cellCode"]
        fn cell_code(self: &Self, x: i32, y: i32) -> u32;
        #[cxx_name = "cellFg"]
        fn cell_fg(self: &Self, x: i32, y: i32) -> u32;
        #[cxx_name = "cellBg"]
        fn cell_bg(self: &Self, x: i32, y: i32) -> u32;
        #[cxx_name = "cellFlags"]
        fn cell_flags(self: &Self, x: i32, y: i32) -> i32;
    }

    impl cxx_qt::Threading for TerminalEngine {}
}

use qobject::TerminalEngine;

const DEFAULT_FG: u32 = 0xFFFF_FFFF;
const DEFAULT_BG: u32 = 0xFF00_0000;

const PALETTE_16: [u32; 16] = [
    0xFF00_0000,
    0xFFCC_0000,
    0xFF4E_9A06,
    0xFFC4_A000,
    0xFF34_65A4,
    0xFF75_507B,
    0xFF06_989A,
    0xFFD3_D7CF,
    0xFF55_5753,
    0xFFEF_2929,
    0xFF8A_E234,
    0xFFFC_E94F,
    0xFF72_9FCF,
    0xFFAD_7FA8,
    0xFF34_E2E2,
    0xFFEE_EEEC,
];

#[derive(Clone, Default)]
struct Proxy {
    title: Arc<Mutex<Option<String>>>,
}

impl EventListener for Proxy {
    fn send_event(&self, event: Event) {
        match event {
            Event::Title(t) => {
                *self.title.lock().unwrap_or_else(|_| std::process::abort()) = Some(t);
            }
            Event::ResetTitle => {
                *self.title.lock().unwrap_or_else(|_| std::process::abort()) =
                    Some("Terminal".to_owned());
            }
            _ => {}
        }
    }
}

struct Size {
    cols: usize,
    rows: usize,
}

impl Dimensions for Size {
    fn total_lines(&self) -> usize {
        self.rows
    }

    fn screen_lines(&self) -> usize {
        self.rows
    }

    fn columns(&self) -> usize {
        self.cols
    }
}

pub struct TerminalEngineRust {
    running: bool,
    failed: bool,
    title: QString,
    master_fd: Option<OwnedFd>,
    pid: i32,
    session_id: u64,
    proxy: Proxy,
    term: Term<Proxy>,
    parser: Processor,
}

impl Default for TerminalEngineRust {
    fn default() -> Self {
        let proxy = Proxy::default();
        let config = Config {
            scrolling_history: 1000,
            ..Config::default()
        };
        let term = Term::new(config, &Size { cols: 80, rows: 24 }, proxy.clone());
        Self {
            running: false,
            failed: false,
            title: QString::from("Terminal"),
            master_fd: None,
            pid: -1,
            session_id: 0,
            proxy,
            term,
            parser: Processor::new(),
        }
    }
}

impl Drop for TerminalEngineRust {
    fn drop(&mut self) {
        self.kill_child();
    }
}

impl TerminalEngineRust {
    fn kill_child(&mut self) {
        drop(self.master_fd.take());
        if self.pid > 0 {
            let pid = self.pid;
            self.pid = -1;
            // SAFETY: killing and reaping our own child process spawned by forkpty.
            unsafe {
                libc::kill(pid, libc::SIGKILL);
                libc::waitpid(pid, std::ptr::null_mut(), 0);
            }
        }
        self.running = false;
    }

    fn advance_bytes(&mut self, bytes: &[u8]) -> Option<String> {
        self.parser.advance(&mut self.term, bytes);
        self.proxy
            .title
            .lock()
            .unwrap_or_else(|_| std::process::abort())
            .take()
    }

    fn cell_at(&self, x: i32, y: i32) -> Option<&Cell> {
        let grid = self.term.grid();
        let history = i32::try_from(grid.history_size()).unwrap_or(0);
        let rows = i32::try_from(grid.screen_lines()).unwrap_or(0);
        let cols = i32::try_from(grid.columns()).unwrap_or(0);
        if y < -history || y >= rows || x < 0 || x >= cols {
            return None;
        }
        let col = usize::try_from(x).ok()?;
        Some(&grid[Line(y)][Column(col)])
    }
}

fn indexed_color(idx: u8) -> u32 {
    let slot = usize::from(idx);
    if let Some(&c) = PALETTE_16.get(slot) {
        return c;
    }
    if idx < 232 {
        let cube = u32::from(idx - 16);
        let comp = |val: u32| if val == 0 { 0 } else { val * 40 + 55 };
        let red = comp(cube / 36);
        let green = comp((cube / 6) % 6);
        let blue = comp(cube % 6);
        0xFF00_0000 | (red << 16) | (green << 8) | blue
    } else {
        let gray = u32::from(idx - 232) * 10 + 8;
        0xFF00_0000 | (gray << 16) | (gray << 8) | gray
    }
}

fn resolve_color(color: Color, is_fg: bool) -> u32 {
    match color {
        Color::Spec(rgb) => {
            0xFF00_0000 | (u32::from(rgb.r) << 16) | (u32::from(rgb.g) << 8) | u32::from(rgb.b)
        }
        Color::Indexed(idx) => indexed_color(idx),
        Color::Named(named) => match named {
            NamedColor::Foreground
            | NamedColor::BrightForeground
            | NamedColor::DimForeground
            | NamedColor::Background => {
                if is_fg {
                    DEFAULT_FG
                } else {
                    DEFAULT_BG
                }
            }
            other => {
                let code = other as usize;
                if let Some(&c) = PALETTE_16.get(code) {
                    c
                } else if (NamedColor::DimBlack as usize..=NamedColor::DimWhite as usize)
                    .contains(&code)
                {
                    PALETTE_16
                        .get(code - NamedColor::DimBlack as usize)
                        .copied()
                        .unwrap_or(DEFAULT_FG)
                } else if is_fg {
                    DEFAULT_FG
                } else {
                    DEFAULT_BG
                }
            }
        },
    }
}

fn write_all_fd(fd: &OwnedFd, mut data: &[u8]) {
    while !data.is_empty() {
        // SAFETY: fd is a valid open PTY master descriptor and data points to valid memory.
        let written = unsafe { libc::write(fd.as_raw_fd(), data.as_ptr().cast(), data.len()) };
        if written > 0 {
            let Ok(n) = usize::try_from(written) else {
                break;
            };
            data = &data[n..];
        } else {
            break;
        }
    }
}

struct ShellExec {
    _argv0: CString,
    programs: Vec<CString>,
    argv: [*const libc::c_char; 3],
    fallback_argv: [*const libc::c_char; 3],
    _environment: Vec<CString>,
    envp: Vec<*const libc::c_char>,
}

fn prepare_shell_exec(shell_prog: &str) -> ShellExec {
    let argv0 = CString::new(shell_prog.as_bytes()).unwrap_or_default();
    let programs = if shell_prog.as_bytes().contains(&b'/') {
        vec![CString::new(shell_prog.as_bytes()).unwrap_or_default()]
    } else {
        let path = std::env::var_os("PATH").unwrap_or_else(|| OsString::from("/bin:/usr/bin"));
        std::env::split_paths(&path)
            .map(|directory| {
                CString::new(directory.join(shell_prog).into_os_string().into_vec())
                    .unwrap_or_default()
            })
            .collect()
    };

    let environment: Vec<CString> = std::env::vars_os()
        .filter(|(key, _)| key != "TERM" && key != "COLORTERM")
        .map(|(key, value)| {
            let mut entry = key.into_vec();
            entry.push(b'=');
            entry.extend(value.into_vec());
            CString::new(entry).unwrap_or_default()
        })
        .collect();
    let mut envp: Vec<*const libc::c_char> =
        environment.iter().map(|entry| entry.as_ptr()).collect();
    envp.push(c"TERM=xterm-256color".as_ptr());
    envp.push(c"COLORTERM=truecolor".as_ptr());
    envp.push(std::ptr::null());

    let argv = [argv0.as_ptr(), c"-i".as_ptr(), std::ptr::null()];
    let fallback_argv = [c"sh".as_ptr(), c"-i".as_ptr(), std::ptr::null()];
    ShellExec {
        _argv0: argv0,
        programs,
        argv,
        fallback_argv,
        _environment: environment,
        envp,
    }
}

fn exec_shell(command: &ShellExec) -> ! {
    // SAFETY: all pointers were prepared before fork and remain valid; execve and
    // _exit are async-signal-safe and this path performs no allocation.
    unsafe {
        for program in &command.programs {
            libc::execve(
                program.as_ptr(),
                command.argv.as_ptr(),
                command.envp.as_ptr(),
            );
        }
        libc::execve(
            c"/bin/sh".as_ptr(),
            command.fallback_argv.as_ptr(),
            command.envp.as_ptr(),
        );
        libc::_exit(127);
    }
}

impl TerminalEngine {
    fn feed_bytes(mut self: Pin<&mut Self>, bytes: &[u8]) {
        let new_title = self.as_mut().rust_mut().advance_bytes(bytes);
        if let Some(t) = new_title {
            let q = QString::from(&t);
            if self.title != q {
                self.as_mut().rust_mut().title = q;
                self.as_mut().title_changed();
            }
        }
        self.screen_changed();
    }

    fn write_notice(self: Pin<&mut Self>, text: &str) {
        let msg = format!("\r\n{text}\r\n");
        self.feed_bytes(msg.as_bytes());
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        clippy::too_many_lines,
        reason = "PTY creation, ownership transfer, and reader startup form one ordered transaction"
    )]
    fn start(mut self: Pin<&mut Self>) {
        if self.pid > 0 {
            return;
        }
        let shell_prog = std::env::var("SHELL")
            .ok()
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "/bin/bash".to_owned());
        let shell_exec = prepare_shell_exec(&shell_prog);
        self.as_mut().rust_mut().failed = false;

        let mut winp = libc::winsize {
            ws_row: self.rows().max(1) as u16,
            ws_col: self.cols().max(1) as u16,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        let mut master_fd: libc::c_int = -1;
        // SAFETY: forkpty initializes master_fd and forks a child attached to a new pseudo-terminal.
        let pid = unsafe {
            libc::forkpty(
                &raw mut master_fd,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                &raw mut winp,
            )
        };
        if pid < 0 {
            self.as_mut().rust_mut().failed = true;
            let notice = format!("[Couldn't start {shell_prog}]");
            self.as_mut().write_notice(&notice);
            self.running_changed();
            return;
        }
        if pid == 0 {
            exec_shell(&shell_exec);
        }

        // SAFETY: forkpty returned this descriptor to the parent, which takes ownership here.
        let master_fd = unsafe { OwnedFd::from_raw_fd(master_fd) };
        let Ok(reader_fd) = master_fd.try_clone() else {
            drop(master_fd);
            // SAFETY: terminate and reap the child whose PTY cannot be safely monitored.
            unsafe {
                libc::kill(pid, libc::SIGKILL);
                libc::waitpid(pid, std::ptr::null_mut(), 0);
            }
            self.as_mut().rust_mut().failed = true;
            let notice = format!("[Couldn't start {shell_prog}]");
            self.as_mut().write_notice(&notice);
            self.running_changed();
            return;
        };

        let session_id = {
            let mut r = self.as_mut().rust_mut();
            r.master_fd = Some(master_fd);
            r.pid = pid;
            r.running = true;
            r.session_id = r.session_id.wrapping_add(1);
            r.session_id
        };
        self.as_mut().running_changed();

        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let started = Instant::now();
            let mut buf = [0u8; 4096];
            loop {
                // SAFETY: reader_fd exclusively owns a valid duplicate of the PTY master.
                let n = unsafe {
                    libc::read(reader_fd.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len())
                };
                if n > 0 {
                    let Ok(len) = usize::try_from(n) else { break };
                    let chunk = buf[..len].to_vec();
                    if qt
                        .queue(move |obj| {
                            if obj.session_id == session_id {
                                obj.feed_bytes(&chunk);
                            }
                        })
                        .is_err()
                    {
                        break;
                    }
                } else {
                    let err = std::io::Error::last_os_error();
                    if n < 0 && err.raw_os_error() == Some(libc::EINTR) {
                        continue;
                    }
                    let fast_fail = started.elapsed().as_millis() < 2000;
                    let shell_copy = shell_prog.clone();
                    qt.queue(move |mut obj| {
                        if obj.session_id != session_id || obj.pid <= 0 {
                            return;
                        }
                        if fast_fail {
                            obj.as_mut().rust_mut().failed = true;
                            let notice = format!("[Couldn't start {shell_copy}]");
                            obj.as_mut().write_notice(&notice);
                        }
                        obj.terminate();
                    })
                    .ok();
                    break;
                }
            }
        });
    }

    fn terminate(mut self: Pin<&mut Self>) {
        if self.pid > 0 {
            self.as_mut().rust_mut().kill_child();
            self.as_mut().running_changed();
            self.finished(-1);
        }
    }

    fn send_input(&self, text: &QString) {
        if let Some(master_fd) = &self.master_fd {
            write_all_fd(master_fd, text.to_string().as_bytes());
        }
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "ASCII control codes 1..=26 fit in u8"
    )]
    fn send_key(&self, key: i32, text: &QString, modifiers: i32) {
        const CTRL_MOD: i32 = 0x0400_0000;
        const ALT_MOD: i32 = 0x0800_0000;
        const KEY_RETURN: i32 = 0x0100_0004;
        const KEY_ENTER: i32 = 0x0100_0005;
        const KEY_BACKSPACE: i32 = 0x0100_0003;
        const KEY_TAB: i32 = 0x0100_0001;
        const KEY_ESCAPE: i32 = 0x0100_0000;
        const KEY_HOME: i32 = 0x0100_0010;
        const KEY_END: i32 = 0x0100_0011;
        const KEY_LEFT: i32 = 0x0100_0012;
        const KEY_UP: i32 = 0x0100_0013;
        const KEY_RIGHT: i32 = 0x0100_0014;
        const KEY_DOWN: i32 = 0x0100_0015;
        const KEY_PAGE_UP: i32 = 0x0100_0016;
        const KEY_PAGE_DOWN: i32 = 0x0100_0017;

        let Some(master_fd) = &self.master_fd else {
            return;
        };

        let mut data = Vec::<u8>::new();
        if (modifiers & CTRL_MOD) != 0 {
            if (0x41..=0x5A).contains(&key) {
                data.push((key - 0x41 + 1) as u8);
            } else if key == 0x5B {
                data.push(0x1B);
            } else if key == 0x5C {
                data.push(0x1C);
            } else if key == 0x5D {
                data.push(0x1D);
            }
        } else {
            match key {
                KEY_RETURN | KEY_ENTER => data.push(b'\r'),
                KEY_BACKSPACE => data.push(0x7F),
                KEY_TAB => data.push(b'\t'),
                KEY_UP => data.extend_from_slice(b"\x1b[A"),
                KEY_DOWN => data.extend_from_slice(b"\x1b[B"),
                KEY_RIGHT => data.extend_from_slice(b"\x1b[C"),
                KEY_LEFT => data.extend_from_slice(b"\x1b[D"),
                KEY_ESCAPE => data.push(0x1B),
                KEY_HOME => data.extend_from_slice(b"\x1b[H"),
                KEY_END => data.extend_from_slice(b"\x1b[F"),
                KEY_PAGE_UP => data.extend_from_slice(b"\x1b[5~"),
                KEY_PAGE_DOWN => data.extend_from_slice(b"\x1b[6~"),
                _ => {
                    let s = text.to_string();
                    if !s.is_empty() {
                        data.extend_from_slice(s.as_bytes());
                    }
                }
            }
        }
        if !data.is_empty() {
            if (modifiers & ALT_MOD) != 0 {
                data.insert(0, 0x1B);
            }
            write_all_fd(master_fd, &data);
        }
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "terminal cols and rows are clamped to positive u16 values"
    )]
    fn resize(mut self: Pin<&mut Self>, cols: i32, rows: i32) {
        let cols = cols.max(2);
        let rows = rows.max(1);
        if let Some(master_fd) = &self.master_fd {
            let winp = libc::winsize {
                ws_row: rows as u16,
                ws_col: cols as u16,
                ws_xpixel: 0,
                ws_ypixel: 0,
            };
            // SAFETY: TIOCSWINSZ updates the kernel PTY window size on valid master_fd.
            unsafe {
                libc::ioctl(master_fd.as_raw_fd(), libc::TIOCSWINSZ, &raw const winp);
            }
        }
        self.as_mut().rust_mut().term.resize(Size {
            cols: cols as usize,
            rows: rows as usize,
        });
        self.screen_changed();
    }

    fn recent_lines(&self, count: i32) -> QStringList {
        let grid = self.term.grid();
        let cols = grid.columns();
        let cursor_y = grid.cursor.point.line.0;
        let mut lines = Vec::<String>::new();
        for y in 0..=cursor_y {
            let row = &grid[Line(y)];
            let mut s = String::with_capacity(cols);
            for x in 0..cols {
                let ch = row[Column(x)].c;
                s.push(if ch == '\0' { ' ' } else { ch });
            }
            let trimmed = s.trim_end_matches(' ').to_owned();
            lines.push(trimmed);
        }
        while lines.last().is_some_and(String::is_empty) {
            lines.pop();
        }
        let n = usize::try_from(count.max(0)).unwrap_or(0);
        let start = lines.len().saturating_sub(n);
        let mut out = QList::<QString>::default();
        for line in &lines[start..] {
            out.append(QString::from(line));
        }
        QStringList::from(&out)
    }

    fn history_lines(&self) -> i32 {
        i32::try_from(self.term.grid().history_size()).unwrap_or(0)
    }

    fn cols(&self) -> i32 {
        i32::try_from(self.term.grid().columns()).unwrap_or(80)
    }

    fn rows(&self) -> i32 {
        i32::try_from(self.term.grid().screen_lines()).unwrap_or(24)
    }

    fn cursor_x(&self) -> i32 {
        i32::try_from(self.term.grid().cursor.point.column.0).unwrap_or(0)
    }

    fn cursor_y(&self) -> i32 {
        self.term.grid().cursor.point.line.0
    }

    fn select(mut self: Pin<&mut Self>, start_x: i32, start_y: i32, end_x: i32, end_y: i32) {
        let ((sx, sy), (ex, ey)) = if start_y > end_y || (start_y == end_y && start_x > end_x) {
            ((end_x, end_y), (start_x, start_y))
        } else {
            ((start_x, start_y), (end_x, end_y))
        };
        let max_col = self.cols().saturating_sub(1).max(0);
        let min_row = -self.history_lines();
        let max_row = self.rows().saturating_sub(1).max(0);
        let sc = usize::try_from(sx.clamp(0, max_col)).unwrap_or(0);
        let ec = usize::try_from(ex.clamp(0, max_col)).unwrap_or(0);
        let sr = sy.clamp(min_row, max_row);
        let er = ey.clamp(min_row, max_row);

        let mut sel = Selection::new(
            SelectionType::Simple,
            Point::new(Line(sr), Column(sc)),
            Side::Left,
        );
        sel.update(Point::new(Line(er), Column(ec)), Side::Right);
        self.as_mut().rust_mut().term.selection = Some(sel);
        self.screen_changed();
    }

    fn clear_selection(mut self: Pin<&mut Self>) {
        if self.term.selection.is_some() {
            self.as_mut().rust_mut().term.selection = None;
            self.screen_changed();
        }
    }

    fn selected_text(&self) -> QString {
        self.term
            .selection_to_string()
            .map_or_else(QString::default, |s| QString::from(&s))
    }

    fn cell_code(&self, x: i32, y: i32) -> u32 {
        self.cell_at(x, y).map_or(0, |c| u32::from(c.c))
    }

    fn cell_fg(&self, x: i32, y: i32) -> u32 {
        self.cell_at(x, y)
            .map_or(DEFAULT_FG, |c| resolve_color(c.fg, true))
    }

    fn cell_bg(&self, x: i32, y: i32) -> u32 {
        self.cell_at(x, y)
            .map_or(DEFAULT_BG, |c| resolve_color(c.bg, false))
    }

    fn cell_flags(&self, x: i32, y: i32) -> i32 {
        let Some(c) = self.cell_at(x, y) else {
            return 0;
        };
        let mut bits = 0;
        if c.flags.contains(Flags::BOLD) {
            bits |= 1;
        }
        if c.flags.contains(Flags::INVERSE) {
            bits |= 2;
        }
        if let Ok(col) = usize::try_from(x) {
            let point = Point::new(Line(y), Column(col));
            if self
                .term
                .selection
                .as_ref()
                .and_then(|s| s.to_range(&self.term))
                .is_some_and(|r| r.contains(point))
            {
                bits |= 4;
            }
        }
        bits
    }
}

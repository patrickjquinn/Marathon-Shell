//! Reading flatpak's terminal output: progress redraws and its error line.

use std::sync::LazyLock;

use regex::Regex;

/// "Installing 2/3… 45%": step, step count and the step's percentage.
static STEP_RE: LazyLock<Regex> = LazyLock::new(|| {
    #[allow(clippy::unwrap_used, reason = "constant pattern")]
    Regex::new(r"(?s)([0-9]+)/([0-9]+)….*[^0-9]([0-9]{1,3})%").unwrap()
});

/// One redraw's progress folded into a single figure across all steps.
pub fn percent(chunk: &str) -> Option<u32> {
    let caps = STEP_RE.captures(chunk)?;
    let step: u32 = caps[1].parse().ok()?;
    let steps: u32 = caps[2].parse().ok()?;
    let pct: u32 = caps[3].parse().ok()?;
    if step == 0 || steps == 0 {
        return None;
    }
    Some(((step - 1) * 100 + pct) / steps)
}

/// flatpak's own reason for failing, without terminal escapes.
pub fn last_error(log: &[u8]) -> Option<String> {
    let plain = strip_ansi_escapes::strip_str(String::from_utf8_lossy(log));
    plain
        .lines()
        .rev()
        .find_map(|line| line.find("error: ").map(|at| line[at + 7..].to_owned()))
}

/// A state file's error text: printable and bounded.
pub fn sanitize(message: &str) -> String {
    message
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .take(400)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folds_step_progress() {
        assert_eq!(percent("Installing 1/1… ████    45%  1.2 MB/s"), Some(45));
        assert_eq!(percent("Installing 2/4… ██ 50%"), Some(37));
        assert_eq!(percent("Installing 3/3… 100%"), Some(100));
        assert_eq!(percent("Looking for matches…"), None);
        assert_eq!(percent("Installing 0/0… 5%"), None);
    }

    #[test]
    fn takes_the_last_percentage_of_a_redraw() {
        assert_eq!(percent("Installing 1/2… 10%\n 20%"), Some(10));
        assert_eq!(percent("Updating 1/1… 3% 7%"), Some(7));
    }

    #[test]
    fn finds_the_last_error_line() {
        let log = b"\x1b]777;notify\x1b\\Installing\x1b[1m 1/1\x1b[0m\nerror: first\n\
                    Warning: x\n\x1b[31merror: \x1b[0mNo remote refs found for 'org.x.Y'\n";
        assert_eq!(
            last_error(log).as_deref(),
            Some("No remote refs found for 'org.x.Y'")
        );
        assert_eq!(last_error(b"all fine\n"), None);
    }

    #[test]
    fn sanitizes_messages() {
        assert_eq!(sanitize("a\tb\u{1b}c \"q\""), "a b c \"q\"");
        assert_eq!(sanitize(&"x".repeat(1000)).len(), 400);
    }
}

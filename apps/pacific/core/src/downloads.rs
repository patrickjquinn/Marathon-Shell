// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Downloads: the records behind the downloads page (what, where, how far,
//! what went wrong), safe file names, and resumption.
//!
//! A download is written to `<name>.part` and renamed when complete.
//! Resuming sends `Range: bytes=<received>-` (with `If-Range` on the ETag
//! or Last-Modified seen first); a server that answers 200 instead of 206
//! restarts it from zero. Private-tab downloads are kept in the private
//! session's in-memory profile, so they leave no record (the files stay
//! where the person saved them).

use std::path::{Path, PathBuf};

use rusqlite::{params, OptionalExtension};
use serde::Serialize;

use crate::db::Profile;
use crate::util::now_ms;
use crate::{Error, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Running,
    Paused,
    Finished,
    Failed,
    Cancelled,
}

impl State {
    /// From the lower-case name (`running`, `paused`, `finished`,
    /// `failed`, `cancelled`).
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "running" => Self::Running,
            "paused" => Self::Paused,
            "finished" => Self::Finished,
            "failed" => Self::Failed,
            "cancelled" => Self::Cancelled,
            _ => return None,
        })
    }

    fn to_i64(self) -> i64 {
        match self {
            Self::Running => 0,
            Self::Paused => 1,
            Self::Finished => 2,
            Self::Failed => 3,
            Self::Cancelled => 4,
        }
    }

    fn from_i64(v: i64) -> Self {
        match v {
            0 => Self::Running,
            1 => Self::Paused,
            2 => Self::Finished,
            4 => Self::Cancelled,
            _ => Self::Failed,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Download {
    pub id: i64,
    pub url: String,
    /// The final path (the `.part` file while running).
    pub path: String,
    pub file_name: String,
    pub mime: String,
    /// -1 when unknown.
    pub total: i64,
    pub received: i64,
    pub state: State,
    pub error: String,
    pub started: i64,
    pub finished: i64,
    pub referrer: String,
}

impl Download {
    fn from_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<Self> {
        let path: String = r.get(2)?;
        Ok(Self {
            id: r.get(0)?,
            url: r.get(1)?,
            file_name: Path::new(&path)
                .file_name()
                .map(|f| f.to_string_lossy().into_owned())
                .unwrap_or_default(),
            path,
            mime: r.get(3)?,
            total: r.get(4)?,
            received: r.get(5)?,
            state: State::from_i64(r.get(6)?),
            error: r.get(7)?,
            started: r.get(8)?,
            finished: r.get(9)?,
            referrer: r.get(10)?,
        })
    }

    /// The partial file while not finished.
    pub fn part_path(&self) -> PathBuf {
        part_path(Path::new(&self.path))
    }

    /// 0..1, or -1 when the size is unknown.
    #[allow(clippy::cast_precision_loss, reason = "a progress fraction")]
    pub fn progress(&self) -> f64 {
        if self.total > 0 {
            (self.received as f64 / self.total as f64).clamp(0.0, 1.0)
        } else if self.state == State::Finished {
            1.0
        } else {
            -1.0
        }
    }
}

pub fn part_path(path: &Path) -> PathBuf {
    let mut p = path.as_os_str().to_owned();
    p.push(".part");
    PathBuf::from(p)
}

const COLUMNS: &str =
    "id, url, path, mime, total, received, state, error, started, finished, referrer";

/// A file name safe to create: no directories, control characters or
/// leading dots, at most 200 bytes, never empty.
pub fn safe_file_name(name: &str) -> String {
    let base = name.rsplit(['/', '\\']).next().unwrap_or("");
    let mut out: String = base
        .chars()
        .map(|c| {
            if c.is_control() || matches!(c, ':' | '*' | '?' | '"' | '<' | '>' | '|') {
                '_'
            } else {
                c
            }
        })
        .collect();
    out = out.trim().trim_start_matches('.').trim().to_string();
    while out.len() > 200 {
        let cut = out
            .char_indices()
            .map(|(i, _)| i)
            .rfind(|i| *i <= 200)
            .unwrap_or(0);
        // Keep the extension when cutting.
        let ext = Path::new(&out)
            .extension()
            .map(|e| e.to_string_lossy().into_owned())
            .filter(|e| e.len() <= 16);
        out = match ext {
            Some(e) => format!("{}.{e}", &out[..cut.saturating_sub(e.len() + 1)]),
            None => out[..cut].to_owned(),
        };
    }
    if out.is_empty() {
        "download".into()
    } else {
        out
    }
}

/// The file name for a download: the server's `Content-Disposition`
/// name, else the last path segment of the URL, else "download".
pub fn file_name_for(url: &str, suggested: &str) -> String {
    if !suggested.trim().is_empty() {
        return safe_file_name(suggested);
    }
    let seg = url::Url::parse(url)
        .ok()
        .and_then(|u| {
            u.path_segments()
                .and_then(|mut s| s.next_back().map(str::to_owned))
        })
        .map(|s| {
            url::form_urlencoded::parse(format!("x={s}").as_bytes())
                .next()
                .map(|(_, v)| v.into_owned())
                .unwrap_or(s)
        })
        .unwrap_or_default();
    safe_file_name(&seg)
}

/// A path in `dir` for `name` that is not taken (`a.pdf`, `a (1).pdf`,
/// ...), counting `.part` files of running downloads.
pub fn unique_path(dir: &Path, name: &str) -> PathBuf {
    let p = Path::new(name);
    let stem = p
        .file_stem()
        .map_or_else(|| name.to_owned(), |s| s.to_string_lossy().into_owned());
    let ext = p
        .extension()
        .map(|e| format!(".{}", e.to_string_lossy()))
        .unwrap_or_default();
    let taken = |c: &Path| c.exists() || part_path(c).exists();
    let first = dir.join(name);
    if !taken(&first) {
        return first;
    }
    (1..10_000)
        .map(|i| dir.join(format!("{stem} ({i}){ext}")))
        .find(|c| !taken(c))
        .unwrap_or_else(|| dir.join(format!("{stem} ({}){ext}", now_ms())))
}

impl Profile {
    /// Records a new download into `dir`; returns it with its final path.
    pub fn start_download(
        &self,
        url: &str,
        suggested_name: &str,
        mime: &str,
        referrer: &str,
        dir: &Path,
    ) -> Result<Download> {
        std::fs::create_dir_all(dir).map_err(|e| Error::io(dir, e))?;
        let path = unique_path(dir, &file_name_for(url, suggested_name));
        // Claim the name at once, so two downloads never pick the same one.
        std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(part_path(&path))
            .map_err(|e| Error::io(part_path(&path), e))?;
        self.conn.execute(
            "INSERT INTO downloads(url, path, mime, total, received, state, started, referrer)
             VALUES (?1, ?2, ?3, -1, 0, ?4, ?5, ?6)",
            params![
                url,
                path.to_string_lossy(),
                mime,
                State::Running.to_i64(),
                now_ms(),
                referrer
            ],
        )?;
        let id = self.conn.last_insert_rowid();
        self.download(id)?
            .ok_or_else(|| Error::NotFound(format!("download {id}")))
    }

    /// Records a download the web engine writes itself to `path` (the
    /// web view's `Download` objects); progress is reported with
    /// [`Profile::update_download_by_path`].
    pub fn record_download(
        &self,
        url: &str,
        path: &Path,
        mime: &str,
        referrer: &str,
    ) -> Result<i64> {
        self.conn.execute(
            "INSERT INTO downloads(url, path, mime, total, received, state, started, referrer)
             VALUES (?1, ?2, ?3, -1, 0, ?4, ?5, ?6)",
            params![
                url,
                path.to_string_lossy(),
                mime,
                State::Running.to_i64(),
                now_ms(),
                referrer
            ],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    pub fn download_by_path(&self, path: &str) -> Result<Option<Download>> {
        Ok(self
            .conn
            .query_row(
                &format!(
                    "SELECT {COLUMNS} FROM downloads WHERE path = ?1 ORDER BY id DESC LIMIT 1"
                ),
                [path],
                Download::from_row,
            )
            .optional()?)
    }

    /// Progress or a new state of the newest download writing `path`.
    pub fn update_download_by_path(
        &self,
        path: &str,
        received: i64,
        total: i64,
        state: State,
        error: &str,
    ) -> Result<()> {
        let Some(d) = self.download_by_path(path)? else {
            return Err(Error::NotFound(format!("download to {path}")));
        };
        self.download_progress(d.id, received, total)?;
        if state != d.state || !error.is_empty() {
            if state == State::Finished {
                self.finish_download(d.id)?;
            } else {
                self.set_download_state(d.id, state, error)?;
            }
        }
        Ok(())
    }

    pub fn download(&self, id: i64) -> Result<Option<Download>> {
        Ok(self
            .conn
            .query_row(
                &format!("SELECT {COLUMNS} FROM downloads WHERE id = ?1"),
                [id],
                Download::from_row,
            )
            .optional()?)
    }

    /// Newest first.
    pub fn downloads(&self) -> Result<Vec<Download>> {
        let mut stmt = self.conn.prepare_cached(&format!(
            "SELECT {COLUMNS} FROM downloads ORDER BY started DESC, id DESC"
        ))?;
        let rows = stmt
            .query_map([], Download::from_row)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }

    pub fn download_progress(&self, id: i64, received: i64, total: i64) -> Result<()> {
        self.conn.execute(
            "UPDATE downloads SET received = ?2, total = ?3 WHERE id = ?1",
            params![id, received, total],
        )?;
        Ok(())
    }

    /// Moves the `.part` file into place and marks the download finished.
    pub fn finish_download(&self, id: i64) -> Result<Download> {
        let d = self
            .download(id)?
            .ok_or_else(|| Error::NotFound(format!("download {id}")))?;
        let part = d.part_path();
        if part.exists() {
            std::fs::rename(&part, &d.path).map_err(|e| Error::io(&d.path, e))?;
        }
        let size = std::fs::metadata(&d.path)
            .map(|m| i64::try_from(m.len()).unwrap_or(i64::MAX))
            .unwrap_or(d.received);
        self.conn.execute(
            "UPDATE downloads SET state = ?2, received = ?3, total = ?3, finished = ?4, error = '' WHERE id = ?1",
            params![id, State::Finished.to_i64(), size, now_ms()],
        )?;
        self.download(id)?
            .ok_or_else(|| Error::NotFound(format!("download {id}")))
    }

    pub fn set_download_state(&self, id: i64, state: State, error: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE downloads SET state = ?2, error = ?3, finished = CASE WHEN ?2 IN (2, 3, 4) THEN ?4 ELSE finished END WHERE id = ?1",
            params![id, state.to_i64(), error, now_ms()],
        )?;
        if state == State::Cancelled {
            if let Some(d) = self.download(id)? {
                let _ = std::fs::remove_file(d.part_path());
            }
        }
        Ok(())
    }

    /// Downloads interrupted by a crash or exit: running ones become
    /// paused, so they can be resumed.
    pub fn pause_interrupted_downloads(&self) -> Result<usize> {
        Ok(self.conn.execute(
            "UPDATE downloads SET state = ?1 WHERE state = ?2",
            params![State::Paused.to_i64(), State::Running.to_i64()],
        )?)
    }

    /// Forgets a download (the file is kept unless `delete_file`).
    pub fn remove_download(&self, id: i64, delete_file: bool) -> Result<()> {
        if let Some(d) = self.download(id)? {
            let _ = std::fs::remove_file(d.part_path());
            if delete_file {
                let _ = std::fs::remove_file(&d.path);
            }
        }
        self.conn
            .execute("DELETE FROM downloads WHERE id = ?1", [id])?;
        Ok(())
    }

    /// Forgets finished, failed and cancelled downloads.
    pub fn clear_finished_downloads(&self) -> Result<usize> {
        Ok(self
            .conn
            .execute("DELETE FROM downloads WHERE state IN (2, 3, 4)", [])?)
    }
}

/// The headers that resume download `d` from what is on disk, and the
/// offset to append at. `validator` is the ETag or Last-Modified seen when
/// it started.
pub fn resume_headers(d: &Download, validator: &str) -> (u64, Vec<(String, String)>) {
    let have = std::fs::metadata(d.part_path())
        .map(|m| m.len())
        .unwrap_or(0);
    if have == 0 {
        return (0, Vec::new());
    }
    let mut h = vec![("Range".to_owned(), format!("bytes={have}-"))];
    if !validator.is_empty() {
        h.push(("If-Range".to_owned(), validator.to_owned()));
    }
    (have, h)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names() {
        assert_eq!(safe_file_name("../../etc/passwd"), "passwd");
        assert_eq!(safe_file_name("..hidden"), "hidden");
        assert_eq!(safe_file_name("a:b*c?.pdf"), "a_b_c_.pdf");
        assert_eq!(safe_file_name("  "), "download");
        assert_eq!(safe_file_name("x\u{0}y.txt"), "x_y.txt");
        let long = format!("{}.pdf", "a".repeat(300));
        let s = safe_file_name(&long);
        assert!(
            s.len() <= 200
                && std::path::Path::new(&s)
                    .extension()
                    .is_some_and(|e| e == "pdf"),
            "{s}"
        );
        assert_eq!(
            file_name_for("https://e.example/files/report%20q3.pdf?x=1", ""),
            "report q3.pdf"
        );
        assert_eq!(file_name_for("https://e.example/", ""), "download");
        assert_eq!(
            file_name_for("https://e.example/a.bin", "Real Name.zip"),
            "Real Name.zip"
        );
    }

    #[test]
    fn unique_paths() {
        let d = tempfile::tempdir().unwrap();
        assert_eq!(unique_path(d.path(), "a.pdf"), d.path().join("a.pdf"));
        std::fs::write(d.path().join("a.pdf"), b"x").unwrap();
        std::fs::write(d.path().join("a (1).pdf.part"), b"x").unwrap();
        assert_eq!(unique_path(d.path(), "a.pdf"), d.path().join("a (2).pdf"));
        assert_eq!(unique_path(d.path(), "noext"), d.path().join("noext"));
    }

    #[test]
    fn lifecycle_of_a_download() {
        let d = tempfile::tempdir().unwrap();
        let p = Profile::in_memory().unwrap();
        let dl = p
            .start_download(
                "https://e.example/f.txt",
                "",
                "text/plain",
                "https://e.example/",
                d.path(),
            )
            .unwrap();
        assert_eq!(dl.state, State::Running);
        assert!(dl.part_path().exists());
        // A second one of the same name gets its own path.
        let other = p
            .start_download("https://e.example/f.txt", "", "text/plain", "", d.path())
            .unwrap();
        assert_ne!(other.path, dl.path);
        std::fs::write(dl.part_path(), b"hello").unwrap();
        p.download_progress(dl.id, 5, 10).unwrap();
        assert!((p.download(dl.id).unwrap().unwrap().progress() - 0.5).abs() < 1e-9);
        let (offset, headers) = resume_headers(&p.download(dl.id).unwrap().unwrap(), "\"etag\"");
        assert_eq!(offset, 5);
        assert_eq!(headers[0], ("Range".into(), "bytes=5-".into()));
        assert_eq!(headers[1].0, "If-Range");
        assert_eq!(p.pause_interrupted_downloads().unwrap(), 2);
        assert_eq!(p.download(dl.id).unwrap().unwrap().state, State::Paused);
        let done = p.finish_download(dl.id).unwrap();
        assert_eq!(done.state, State::Finished);
        assert_eq!(done.received, 5);
        assert!(Path::new(&done.path).exists());
        assert!(!done.part_path().exists());
        p.set_download_state(other.id, State::Cancelled, "")
            .unwrap();
        assert!(!p.download(other.id).unwrap().unwrap().part_path().exists());
        assert_eq!(p.downloads().unwrap().len(), 2);
        assert_eq!(p.clear_finished_downloads().unwrap(), 2);
        assert!(p.downloads().unwrap().is_empty());
        // The file itself stays.
        assert!(Path::new(&done.path).exists());
    }

    #[test]
    fn engine_written_downloads() {
        let d = tempfile::tempdir().unwrap();
        let p = Profile::in_memory().unwrap();
        let path = d.path().join("x.zip");
        let id = p
            .record_download("https://e.example/x.zip", &path, "application/zip", "")
            .unwrap();
        let key = path.to_string_lossy().into_owned();
        p.update_download_by_path(&key, 10, 100, State::Running, "")
            .unwrap();
        assert!((p.download(id).unwrap().unwrap().progress() - 0.1).abs() < 1e-9);
        std::fs::write(&path, vec![0u8; 100]).unwrap();
        p.update_download_by_path(&key, 100, 100, State::Finished, "")
            .unwrap();
        let done = p.download(id).unwrap().unwrap();
        assert_eq!((done.state, done.received), (State::Finished, 100));
        assert!(p
            .update_download_by_path("/nope", 0, 0, State::Failed, "x")
            .is_err());
        assert_eq!(State::parse("paused"), Some(State::Paused));
        assert_eq!(State::parse("?"), None);
    }

    #[test]
    fn remove_with_file() {
        let d = tempfile::tempdir().unwrap();
        let p = Profile::in_memory().unwrap();
        let dl = p
            .start_download("https://e.example/g.bin", "", "", "", d.path())
            .unwrap();
        let done = p.finish_download(dl.id).unwrap();
        p.remove_download(done.id, true).unwrap();
        assert!(!Path::new(&done.path).exists());
        assert!(p.download(done.id).unwrap().is_none());
    }
}

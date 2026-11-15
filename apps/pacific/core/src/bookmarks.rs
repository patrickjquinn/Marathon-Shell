// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Bookmarks in folders, with Netscape bookmark-file import and export
//! (the format every browser reads and writes).

use std::fmt::Write as _;

use rusqlite::{params, OptionalExtension};
use serde::Serialize;

use crate::db::Profile;
use crate::util::{html_escape, now_ms};
use crate::{Error, Result};

/// The root folder; it always exists and cannot be deleted.
pub const ROOT: i64 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Bookmark {
    pub id: i64,
    pub parent: i64,
    pub folder: bool,
    pub title: String,
    pub url: String,
    pub position: i64,
    pub added: i64,
    pub modified: i64,
}

impl Bookmark {
    fn from_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<Self> {
        Ok(Self {
            id: r.get(0)?,
            parent: r.get::<_, Option<i64>>(1)?.unwrap_or(0),
            folder: r.get(2)?,
            title: r.get(3)?,
            url: r.get(4)?,
            position: r.get(5)?,
            added: r.get(6)?,
            modified: r.get(7)?,
        })
    }
}

const COLUMNS: &str = "id, parent, folder, title, url, position, added, modified";

pub(crate) fn ensure_roots(p: &Profile) -> Result<()> {
    let now = now_ms();
    p.conn.execute(
        "INSERT OR IGNORE INTO bookmarks(id, parent, folder, title, url, position, added, modified)
         VALUES (?1, NULL, 1, 'Bookmarks', '', 0, ?2, ?2)",
        params![ROOT, now],
    )?;
    Ok(())
}

impl Profile {
    pub fn is_bookmarked(&self, url: &str) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT 1 FROM bookmarks WHERE url = ?1 AND folder = 0 LIMIT 1",
                [url],
                |_| Ok(()),
            )
            .optional()?
            .is_some())
    }

    /// The bookmark of `url`, if any (the first one).
    pub fn bookmark_for(&self, url: &str) -> Result<Option<Bookmark>> {
        Ok(self
            .conn
            .query_row(
                &format!("SELECT {COLUMNS} FROM bookmarks WHERE url = ?1 AND folder = 0 ORDER BY id LIMIT 1"),
                [url],
                Bookmark::from_row,
            )
            .optional()?)
    }

    pub fn bookmark(&self, id: i64) -> Result<Option<Bookmark>> {
        Ok(self
            .conn
            .query_row(
                &format!("SELECT {COLUMNS} FROM bookmarks WHERE id = ?1"),
                [id],
                Bookmark::from_row,
            )
            .optional()?)
    }

    fn check_folder(&self, id: i64) -> Result<()> {
        match self.bookmark(id)? {
            Some(b) if b.folder => Ok(()),
            _ => Err(Error::NotFound(format!("folder {id}"))),
        }
    }

    fn next_position(&self, parent: i64) -> Result<i64> {
        Ok(self.conn.query_row(
            "SELECT coalesce(max(position) + 1, 0) FROM bookmarks WHERE parent = ?1",
            [parent],
            |r| r.get(0),
        )?)
    }

    /// Adds a bookmark at the end of `parent`.
    pub fn add_bookmark(&self, url: &str, title: &str, parent: i64) -> Result<i64> {
        url::Url::parse(url).map_err(|_| Error::BadUrl(url.to_owned()))?;
        self.check_folder(parent)?;
        let now = now_ms();
        self.conn.execute(
            "INSERT INTO bookmarks(parent, folder, title, url, position, added, modified)
             VALUES (?1, 0, ?2, ?3, ?4, ?5, ?5)",
            params![parent, title, url, self.next_position(parent)?, now],
        )?;
        let id = self.conn.last_insert_rowid();
        self.refresh_frecency_of(url)?;
        Ok(id)
    }

    pub fn add_folder(&self, title: &str, parent: i64) -> Result<i64> {
        self.check_folder(parent)?;
        let now = now_ms();
        self.conn.execute(
            "INSERT INTO bookmarks(parent, folder, title, url, position, added, modified)
             VALUES (?1, 1, ?2, '', ?3, ?4, ?4)",
            params![parent, title, self.next_position(parent)?, now],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Renames a bookmark or folder, and changes a bookmark's address.
    pub fn update_bookmark(&self, id: i64, title: &str, url: Option<&str>) -> Result<()> {
        let old = self
            .bookmark(id)?
            .ok_or_else(|| Error::NotFound(format!("bookmark {id}")))?;
        let url = if old.folder {
            ""
        } else {
            url.unwrap_or(&old.url)
        };
        if !old.folder {
            url::Url::parse(url).map_err(|_| Error::BadUrl(url.to_owned()))?;
        }
        self.conn.execute(
            "UPDATE bookmarks SET title = ?2, url = ?3, modified = ?4 WHERE id = ?1",
            params![id, title, url, now_ms()],
        )?;
        if !old.folder && old.url != url {
            self.refresh_frecency_of(&old.url)?;
            self.refresh_frecency_of(url)?;
        }
        Ok(())
    }

    /// Moves `id` into `parent` at `position` (clamped; -1 for the end).
    /// A folder cannot move into itself or its descendants.
    pub fn move_bookmark(&self, id: i64, parent: i64, position: i64) -> Result<()> {
        if id == ROOT {
            return Err(Error::Invalid("the root folder cannot move".into()));
        }
        self.check_folder(parent)?;
        let mut cur = Some(parent);
        while let Some(c) = cur {
            if c == id {
                return Err(Error::Invalid("a folder cannot move into itself".into()));
            }
            cur = self.bookmark(c)?.map(|b| b.parent).filter(|p| *p != 0);
        }
        let tx = self.conn.unchecked_transaction()?;
        let mut siblings: Vec<i64> = {
            let mut stmt = tx.prepare(
                "SELECT id FROM bookmarks WHERE parent = ?1 AND id <> ?2 ORDER BY position, id",
            )?;
            let rows = stmt
                .query_map(params![parent, id], |r| r.get(0))?
                .collect::<rusqlite::Result<_>>()?;
            rows
        };
        let at = usize::try_from(position).map_or(siblings.len(), |p| p.min(siblings.len()));
        siblings.insert(at, id);
        for (i, sid) in siblings.iter().enumerate() {
            tx.execute(
                "UPDATE bookmarks SET parent = ?2, position = ?3 WHERE id = ?1",
                params![sid, parent, i64::try_from(i).unwrap_or(i64::MAX)],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    /// Deletes a bookmark, or a folder with everything in it.
    pub fn delete_bookmark(&self, id: i64) -> Result<()> {
        if id == ROOT {
            return Err(Error::Invalid("the root folder cannot be deleted".into()));
        }
        let mut urls = Vec::new();
        self.collect_urls(id, &mut urls)?;
        self.conn
            .execute("DELETE FROM bookmarks WHERE id = ?1", [id])?;
        for u in urls {
            self.refresh_frecency_of(&u)?;
        }
        Ok(())
    }

    /// Removes every bookmark of `url`.
    pub fn unbookmark(&self, url: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM bookmarks WHERE url = ?1 AND folder = 0", [url])?;
        self.refresh_frecency_of(url)?;
        Ok(())
    }

    fn collect_urls(&self, id: i64, out: &mut Vec<String>) -> Result<()> {
        if let Some(b) = self.bookmark(id)? {
            if b.folder {
                for c in self.bookmarks_in(id)? {
                    self.collect_urls(c.id, out)?;
                }
            } else {
                out.push(b.url);
            }
        }
        Ok(())
    }

    /// The children of a folder, folders first, then in position order.
    pub fn bookmarks_in(&self, parent: i64) -> Result<Vec<Bookmark>> {
        let mut stmt = self.conn.prepare_cached(&format!(
            "SELECT {COLUMNS} FROM bookmarks WHERE parent = ?1 ORDER BY folder DESC, position, id"
        ))?;
        let rows = stmt
            .query_map([parent], Bookmark::from_row)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }

    /// Every folder with its depth, in tree order (for a folder picker).
    pub fn folder_tree(&self) -> Result<Vec<(Bookmark, usize)>> {
        let mut out = Vec::new();
        let root = self
            .bookmark(ROOT)?
            .ok_or_else(|| Error::NotFound("root folder".into()))?;
        self.walk_folders(root, 0, &mut out)?;
        Ok(out)
    }

    fn walk_folders(
        &self,
        b: Bookmark,
        depth: usize,
        out: &mut Vec<(Bookmark, usize)>,
    ) -> Result<()> {
        let id = b.id;
        out.push((b, depth));
        for c in self.bookmarks_in(id)? {
            if c.folder && depth < 32 {
                self.walk_folders(c, depth + 1, out)?;
            }
        }
        Ok(())
    }

    /// Bookmarks whose title or address contains every word of `query`.
    pub fn find_bookmarks(&self, query: &str, limit: usize) -> Result<Vec<Bookmark>> {
        let words: Vec<String> = query
            .split_whitespace()
            .take(8)
            .map(|w| format!("%{}%", w.to_lowercase().replace(['%', '_'], "")))
            .collect();
        let mut stmt = self.conn.prepare_cached(&format!(
            "SELECT {COLUMNS} FROM bookmarks WHERE folder = 0 ORDER BY modified DESC"
        ))?;
        let mut out = Vec::new();
        for b in stmt.query_map([], Bookmark::from_row)? {
            let b = b?;
            let hay = format!("{} {}", b.title, b.url).to_lowercase();
            if words.iter().all(|w| hay.contains(w.trim_matches('%'))) {
                out.push(b);
                if out.len() >= limit {
                    break;
                }
            }
        }
        Ok(out)
    }

    /// The most recently added bookmarks (new-tab page).
    pub fn recent_bookmarks(&self, limit: usize) -> Result<Vec<Bookmark>> {
        let mut stmt = self.conn.prepare_cached(&format!(
            "SELECT {COLUMNS} FROM bookmarks WHERE folder = 0 ORDER BY added DESC LIMIT ?1"
        ))?;
        let rows = stmt
            .query_map(
                [i64::try_from(limit).unwrap_or(i64::MAX)],
                Bookmark::from_row,
            )?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }

    /// All bookmarks as a Netscape bookmark file.
    pub fn export_bookmarks_html(&self) -> Result<String> {
        let mut out = String::from(
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n<TITLE>Bookmarks</TITLE>\n<H1>Bookmarks</H1>\n<DL><p>\n",
        );
        self.export_folder(ROOT, 1, &mut out)?;
        out.push_str("</DL><p>\n");
        Ok(out)
    }

    fn export_folder(&self, id: i64, depth: usize, out: &mut String) -> Result<()> {
        let pad = "    ".repeat(depth);
        for b in self.bookmarks_in(id)? {
            let added = b.added / 1000;
            if b.folder {
                let _ = write!(
                    out,
                    "{pad}<DT><H3 ADD_DATE=\"{added}\">{}</H3>\n{pad}<DL><p>\n",
                    html_escape(&b.title)
                );
                if depth < 32 {
                    self.export_folder(b.id, depth + 1, out)?;
                }
                let _ = writeln!(out, "{pad}</DL><p>");
            } else {
                let _ = writeln!(
                    out,
                    "{pad}<DT><A HREF=\"{}\" ADD_DATE=\"{added}\">{}</A>",
                    html_escape(&b.url),
                    html_escape(&b.title)
                );
            }
        }
        Ok(())
    }

    /// Imports a Netscape bookmark file (Firefox, Chrome, Safari exports)
    /// into a new folder under the root named `folder_title`. Returns the
    /// number of bookmarks imported. Only http(s) bookmarks are kept.
    pub fn import_bookmarks_html(&self, html: &str, folder_title: &str) -> Result<usize> {
        let tx = self.conn.unchecked_transaction()?;
        let top = self.add_folder(folder_title, ROOT)?;
        let mut stack = vec![top];
        let mut pending_folder: Option<String> = None;
        let mut count = 0;
        let lower = html.to_ascii_lowercase();
        let mut i = 0;
        while let Some(off) = lower[i..].find('<') {
            let at = i + off;
            let rest = &lower[at..];
            if rest.starts_with("<h3") {
                let (text, end) = element_text(html, at, "</h3>");
                pending_folder = Some(text);
                i = end;
            } else if rest.starts_with("<dl") {
                if let Some(title) = pending_folder.take() {
                    let parent = *stack.last().unwrap_or(&top);
                    let id = self.add_folder(&title, parent)?;
                    stack.push(id);
                }
                i = at + 3;
            } else if rest.starts_with("</dl") {
                if stack.len() > 1 {
                    stack.pop();
                }
                i = at + 4;
            } else if rest.starts_with("<a ") {
                let tag_end = lower[at..].find('>').map_or(lower.len(), |e| at + e);
                let href = attribute(&html[at..tag_end], "href");
                let (title, end) = element_text(html, at, "</a>");
                if let Some(href) = href.filter(|h| crate::history::is_storable(h)) {
                    let parent = *stack.last().unwrap_or(&top);
                    let t = if title.is_empty() {
                        href.clone()
                    } else {
                        title
                    };
                    self.add_bookmark(&href, &t, parent)?;
                    count += 1;
                }
                i = end;
            } else {
                i = at + 1;
            }
        }
        tx.commit()?;
        Ok(count)
    }
}

/// The text of the element whose start tag begins at `at`, entity-decoded,
/// and the index after `close`.
fn element_text(html: &str, at: usize, close: &str) -> (String, usize) {
    let lower = html.to_ascii_lowercase();
    let start = lower[at..].find('>').map_or(html.len(), |e| at + e + 1);
    let end = lower[start..].find(close).map_or(html.len(), |e| start + e);
    (
        decode_entities(html[start..end].trim()),
        (end + close.len()).min(html.len()),
    )
}

fn attribute(tag: &str, name: &str) -> Option<String> {
    let lower = tag.to_ascii_lowercase();
    let key = format!("{name}=");
    let pos = lower.find(&key)? + key.len();
    let rest = &tag[pos..];
    let quote = rest.chars().next()?;
    let value = if quote == '"' || quote == '\'' {
        let inner = &rest[1..];
        &inner[..inner.find(quote)?]
    } else {
        rest.split(|c: char| c.is_whitespace() || c == '>').next()?
    };
    Some(decode_entities(value))
}

fn decode_entities(s: &str) -> String {
    s.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&#x27;", "'")
        .replace("&amp;", "&")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folders_order_and_moves() {
        let p = Profile::in_memory().unwrap();
        let f = p.add_folder("News", ROOT).unwrap();
        let a = p.add_bookmark("https://a.example/", "A", ROOT).unwrap();
        let b = p.add_bookmark("https://b.example/", "B", ROOT).unwrap();
        let titles = |id| {
            p.bookmarks_in(id)
                .unwrap()
                .into_iter()
                .map(|b| b.title)
                .collect::<Vec<_>>()
        };
        assert_eq!(titles(ROOT), ["News", "A", "B"]);
        p.move_bookmark(b, ROOT, 0).unwrap();
        assert_eq!(titles(ROOT), ["News", "B", "A"]);
        p.move_bookmark(a, f, -1).unwrap();
        assert_eq!(titles(f), ["A"]);
        let sub = p.add_folder("Sub", f).unwrap();
        assert!(p.move_bookmark(f, sub, 0).is_err());
        assert!(p.move_bookmark(ROOT, f, 0).is_err());
        assert!(p.delete_bookmark(ROOT).is_err());
        assert_eq!(
            p.folder_tree()
                .unwrap()
                .iter()
                .map(|(b, d)| (b.title.clone(), *d))
                .collect::<Vec<_>>(),
            [
                ("Bookmarks".to_string(), 0),
                ("News".to_string(), 1),
                ("Sub".to_string(), 2)
            ]
        );
        p.delete_bookmark(f).unwrap();
        assert!(!p.is_bookmarked("https://a.example/").unwrap());
        assert!(p.add_bookmark("not a url", "x", ROOT).is_err());
        assert!(p.add_bookmark("https://x.example/", "x", 999).is_err());
    }

    #[test]
    fn bookmarking_raises_frecency() {
        let p = Profile::in_memory().unwrap();
        p.add_bookmark("https://never.example/", "Never visited", ROOT)
            .unwrap();
        let place = p.place("https://never.example/").unwrap().unwrap();
        assert!(place.frecency > 0.0);
        p.unbookmark("https://never.example/").unwrap();
        let place = p.place("https://never.example/").unwrap().unwrap();
        assert!(place.frecency.abs() < f64::EPSILON);
    }

    #[test]
    fn update_and_find() {
        let p = Profile::in_memory().unwrap();
        let id = p
            .add_bookmark("https://a.example/", "Alpha news", ROOT)
            .unwrap();
        p.update_bookmark(id, "Alpha weather", Some("https://w.example/"))
            .unwrap();
        assert!(p.is_bookmarked("https://w.example/").unwrap());
        assert!(!p.is_bookmarked("https://a.example/").unwrap());
        assert_eq!(p.find_bookmarks("weather alpha", 10).unwrap().len(), 1);
        assert_eq!(p.find_bookmarks("news", 10).unwrap().len(), 0);
        assert!(p.update_bookmark(id, "x", Some("bad")).is_err());
        assert_eq!(p.recent_bookmarks(5).unwrap()[0].id, id);
    }

    #[test]
    fn netscape_round_trip() {
        let p = Profile::in_memory().unwrap();
        let f = p.add_folder("Dev & Tools", ROOT).unwrap();
        p.add_bookmark("https://docs.rs/?a=1&b=2", "Docs <rs>", f)
            .unwrap();
        p.add_bookmark("https://example.com/", "Example", ROOT)
            .unwrap();
        let html = p.export_bookmarks_html().unwrap();
        assert!(html.contains("Docs &lt;rs&gt;"));
        assert!(html.contains("https://docs.rs/?a=1&amp;b=2"));

        let q = Profile::in_memory().unwrap();
        assert_eq!(q.import_bookmarks_html(&html, "Imported").unwrap(), 2);
        let imported = q.bookmarks_in(ROOT).unwrap();
        assert_eq!(imported[0].title, "Imported");
        let inside = q.bookmarks_in(imported[0].id).unwrap();
        assert_eq!(inside[0].title, "Dev & Tools");
        assert!(inside[0].folder);
        let deep = q.bookmarks_in(inside[0].id).unwrap();
        assert_eq!(deep[0].url, "https://docs.rs/?a=1&b=2");
        assert_eq!(deep[0].title, "Docs <rs>");
        assert_eq!(inside[1].url, "https://example.com/");
    }

    #[test]
    fn import_skips_non_web_links() {
        let p = Profile::in_memory().unwrap();
        let html = "<DL><p><DT><A HREF=\"javascript:alert(1)\">x</A><DT><A HREF='https://ok.example/'>ok</A></DL>";
        assert_eq!(p.import_bookmarks_html(html, "In").unwrap(), 1);
    }
}

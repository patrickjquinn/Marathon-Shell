//! `medialibrary.db`: the photos and videos under Pictures and DCIM, by
//! album (the folder they are in), with a thumbnail for each photo.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use image::imageops::FilterType;
use image::{DynamicImage, ImageDecoder, ImageReader};
use rusqlite::{params, Connection, OptionalExtension};
use zbus::Variant as Value;

pub type Row = std::collections::HashMap<&'static str, Value<'static>>;

const PHOTOS: &[&str] = &["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif"];
const VIDEOS: &[&str] = &["mp4", "mov", "avi", "mkv", "webm", "m4v", "3gp"];

fn kind(path: &Path) -> Option<&'static str> {
    let ext = path.extension()?.to_str()?.to_ascii_lowercase();
    if PHOTOS.contains(&ext.as_str()) {
        Some("photo")
    } else if VIDEOS.contains(&ext.as_str()) {
        Some("video")
    } else {
        None
    }
}

fn album(path: &Path) -> String {
    match path
        .parent()
        .and_then(Path::file_name)
        .and_then(|n| n.to_str())
    {
        None | Some("" | "Pictures" | "DCIM") => "Camera Roll".to_owned(),
        Some(name) => name.to_owned(),
    }
}

fn url(path: &str) -> String {
    if path.is_empty() {
        String::new()
    } else {
        format!("file://{path}")
    }
}

/// A file found by a scan.
pub struct Found {
    path: String,
    kind: &'static str,
    timestamp: i64,
}

impl Found {
    pub fn path(&self) -> &str {
        &self.path
    }
}

/// The media files under `roots`.
pub fn walk(roots: &[PathBuf]) -> Vec<Found> {
    roots
        .iter()
        .flat_map(|root| walkdir::WalkDir::new(root).into_iter().flatten())
        .filter(|e| e.file_type().is_file())
        .filter_map(|e| {
            let kind = kind(e.path())?;
            let modified = e
                .metadata()
                .ok()?
                .modified()
                .ok()?
                .duration_since(UNIX_EPOCH)
                .ok()?;
            Some(Found {
                path: e.path().to_string_lossy().into_owned(),
                kind,
                timestamp: i64::try_from(modified.as_millis()).ok()?,
            })
        })
        .collect()
}

/// A picture scaled to fit `size`, as PNG for PNGs and screenshots, else
/// JPEG; kept by a hash of its source's path.
pub fn thumbnail(source: &str, dir: &Path, size: u32) -> Option<String> {
    let hash = source.bytes().fold(0xcbf2_9ce4_8422_2325_u64, |h, b| {
        (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3)
    });
    let path = Path::new(source);
    let png = path
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("png"))
        || source.to_lowercase().contains("/screenshots/")
        || path
            .file_stem()
            .is_some_and(|s| s.to_string_lossy().to_lowercase().contains("screenshot"));
    let thumb = dir.join(format!(
        "{hash:016x}_thumb_v3_{size}.{}",
        if png { "png" } else { "jpg" }
    ));
    if thumb.exists() {
        return Some(thumb.to_string_lossy().into_owned());
    }
    let mut decoder = ImageReader::open(path)
        .ok()?
        .with_guessed_format()
        .ok()?
        .into_decoder()
        .ok()?;
    let orientation = decoder.orientation().ok()?;
    let mut image = DynamicImage::from_decoder(decoder).ok()?;
    image.apply_orientation(orientation);
    let image = image.resize(size, size, FilterType::Triangle);
    fs::create_dir_all(dir).ok()?;
    let saved = if png {
        image.save_with_format(&thumb, image::ImageFormat::Png)
    } else {
        let mut file = fs::File::create(&thumb).ok()?;
        DynamicImage::ImageRgb8(image.to_rgb8()).write_with_encoder(
            image::codecs::jpeg::JpegEncoder::new_with_quality(&mut file, 92),
        )
    };
    saved.ok().map(|()| thumb.to_string_lossy().into_owned())
}

pub struct Library {
    db: Connection,
    pub thumbnails: PathBuf,
    pub size: u32,
}

impl Library {
    pub fn open(db: &Path, thumbnails: PathBuf, size: u32) -> rusqlite::Result<Self> {
        if let Some(dir) = db.parent() {
            fs::create_dir_all(dir).ok();
        }
        let db = Connection::open(db)?;
        db.execute_batch(
            "PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS media (id INTEGER PRIMARY KEY AUTOINCREMENT,
                 path TEXT NOT NULL UNIQUE, type TEXT NOT NULL, album TEXT, timestamp INTEGER NOT NULL,
                 width INTEGER DEFAULT 0, height INTEGER DEFAULT 0, thumbnail_path TEXT);",
        )?;
        Ok(Self {
            db,
            thumbnails,
            size,
        })
    }

    /// The files a scan found that the library does not have, and the
    /// photos without a thumbnail; files gone since are dropped.
    pub fn reconcile(&self, found: Vec<Found>) -> rusqlite::Result<Vec<Found>> {
        let known: HashSet<String> = self
            .db
            .prepare("SELECT path FROM media")?
            .query_map([], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?;
        let present: HashSet<&str> = found.iter().map(|f| f.path.as_str()).collect();
        for gone in known.iter().filter(|p| !present.contains(p.as_str())) {
            self.db
                .execute("DELETE FROM media WHERE path = ?", [gone])?;
        }
        let unthumbed: HashSet<String> = self
            .db
            .prepare(
                "SELECT path FROM media WHERE type = 'photo' AND IFNULL(thumbnail_path, '') = ''",
            )?
            .query_map([], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?;
        Ok(found
            .into_iter()
            .filter(|f| !known.contains(&f.path) || unthumbed.contains(&f.path))
            .collect())
    }

    /// Adds or completes a file's row; whether it is new.
    pub fn add(&self, f: &Found) -> rusqlite::Result<bool> {
        let (mut width, mut height, mut thumb) = (0, 0, String::new());
        if f.kind == "photo" {
            (width, height) = image::image_dimensions(&f.path).unwrap_or_default();
            thumb = thumbnail(&f.path, &self.thumbnails, self.size).unwrap_or_default();
        }
        let added = self.db.execute(
            "INSERT OR IGNORE INTO media (path, type, album, timestamp, width, height, thumbnail_path) VALUES (?, ?, ?, ?, ?, ?, ?)",
            params![f.path, f.kind, album(Path::new(&f.path)), f.timestamp, width, height, thumb],
        )? > 0;
        if !added && !thumb.is_empty() {
            self.db.execute(
                "UPDATE media SET thumbnail_path = ? WHERE path = ?",
                params![thumb, f.path],
            )?;
        }
        Ok(added)
    }

    pub fn albums(&self) -> rusqlite::Result<Vec<Row>> {
        let mut query = self.db.prepare(
            "SELECT album, COUNT(*), MIN(path), MAX(timestamp) AS last FROM media WHERE type = 'photo'
             GROUP BY album ORDER BY last DESC",
        )?;
        let rows = query.query_map([], |r| {
            let id: String = r.get::<_, Option<String>>(0)?.unwrap_or_default();
            Ok(Row::from([
                (
                    "name",
                    Value::from(if id.is_empty() {
                        "All Photos".to_owned()
                    } else {
                        id.clone()
                    }),
                ),
                ("id", Value::from(id)),
                ("photoCount", Value::from(r.get::<_, i32>(1)?)),
                ("coverPath", Value::from(r.get::<_, String>(2)?)),
                ("lastModified", Value::from(r.get::<_, i64>(3)?)),
            ]))
        })?;
        rows.collect()
    }

    pub fn count(&self, kind: &str) -> i32 {
        self.db
            .query_row("SELECT COUNT(*) FROM media WHERE type = ?", [kind], |r| {
                r.get(0)
            })
            .unwrap_or_default()
    }

    /// Photos (of `album`, or all with their album) or videos, newest first.
    pub fn items(&self, kind: &str, album: Option<&str>) -> rusqlite::Result<Vec<Row>> {
        let mut query = self.db.prepare(
            "SELECT id, path, IFNULL(thumbnail_path, ''), width, height, timestamp, IFNULL(album, '') FROM media
             WHERE type = ?1 AND (?2 IS NULL OR album = ?2) ORDER BY timestamp DESC",
        )?;
        let rows = query.query_map(params![kind, album], |r| {
            let mut row = Row::from([
                ("id", Value::from(r.get::<_, i32>(0)?)),
                ("path", Value::from(url(&r.get::<_, String>(1)?))),
                ("thumbnailPath", Value::from(url(&r.get::<_, String>(2)?))),
                ("timestamp", Value::from(r.get::<_, i64>(5)?)),
            ]);
            if kind == "photo" {
                row.insert("width", Value::from(r.get::<_, i32>(3)?));
                row.insert("height", Value::from(r.get::<_, i32>(4)?));
                if album.is_none() {
                    row.insert("album", Value::from(r.get::<_, String>(6)?));
                }
            }
            Ok(row)
        })?;
        rows.collect()
    }

    /// Deletes the file, its thumbnail and its row.
    pub fn delete(&self, id: i32) -> rusqlite::Result<bool> {
        let found: Option<(String, Option<String>)> = self
            .db
            .query_row(
                "SELECT path, thumbnail_path FROM media WHERE id = ?",
                [id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        let Some((path, thumb)) = found else {
            return Ok(false);
        };
        fs::remove_file(path).ok();
        if let Some(thumb) = thumb.filter(|t| !t.is_empty()) {
            fs::remove_file(thumb).ok();
        }
        Ok(self.db.execute("DELETE FROM media WHERE id = ?", [id])? > 0)
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn a_scan_finds_albums_thumbnails_and_what_went() {
        let dir = tempfile::tempdir().unwrap();
        let pictures = dir.path().join("Pictures");
        fs::create_dir_all(pictures.join("Trip")).unwrap();
        image::RgbImage::new(1200, 800)
            .save(pictures.join("a.jpg"))
            .unwrap();
        image::RgbImage::new(64, 64)
            .save(pictures.join("Trip/b.png"))
            .unwrap();
        fs::write(pictures.join("Trip/notes.txt"), "x").unwrap();
        let lib =
            Library::open(&dir.path().join("media.db"), dir.path().join("thumbs"), 256).unwrap();
        let new = lib
            .reconcile(walk(std::slice::from_ref(&pictures)))
            .unwrap();
        assert_eq!(new.len(), 2);
        assert!(new.iter().all(|f| lib.add(f).unwrap()));
        let albums: Vec<String> = lib
            .albums()
            .unwrap()
            .iter()
            .map(|a| String::try_from(a["id"].try_clone().unwrap()).unwrap())
            .collect();
        assert_eq!(albums.len(), 2);
        assert!(albums.contains(&"Camera Roll".to_owned()) && albums.contains(&"Trip".to_owned()));
        let roll = lib.items("photo", Some("Camera Roll")).unwrap();
        assert_eq!(roll[0]["width"], Value::from(1200));
        let thumb = String::try_from(roll[0]["thumbnailPath"].try_clone().unwrap()).unwrap();
        assert!(
            thumb.starts_with("file://")
                && Path::new(&thumb).extension().is_some_and(|e| e == "jpg")
        );
        assert_eq!(
            image::image_dimensions(thumb.trim_start_matches("file://")).unwrap(),
            (256, 171)
        );
        assert_eq!(
            lib.reconcile(walk(std::slice::from_ref(&pictures)))
                .unwrap()
                .len(),
            0
        );
        fs::remove_file(pictures.join("a.jpg")).unwrap();
        lib.reconcile(walk(&[pictures])).unwrap();
        assert_eq!(lib.count("photo"), 1);
    }
}

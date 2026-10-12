//! `.marathon` package archives: zip files of an app directory.

use std::fs::{self, File};
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use walkdir::WalkDir;
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipArchive, ZipWriter};

/// Zips `source_dir` into `archive`, following symlinks as `zip -r` did, and
/// keeping each entry's permission bits.
pub fn create(source_dir: &Path, archive: &Path) -> Result<(), String> {
    let out = File::create(archive).map_err(|e| format!("{}: {e}", archive.display()))?;
    let skip = fs::canonicalize(archive).ok();
    let mut zip = ZipWriter::new(out);
    let base = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);

    for entry in WalkDir::new(source_dir)
        .follow_links(true)
        .min_depth(1)
        .sort_by_file_name()
    {
        let entry = entry.map_err(|e| e.to_string())?;
        if skip.is_some() && fs::canonicalize(entry.path()).ok() == skip {
            continue;
        }
        let relative = entry
            .path()
            .strip_prefix(source_dir)
            .map_err(|e| e.to_string())?;
        let name = relative
            .to_str()
            .ok_or_else(|| format!("{}: name is not UTF-8", relative.display()))?;
        let mode = entry
            .metadata()
            .map_err(|e| e.to_string())?
            .permissions()
            .mode()
            & 0o777;
        let options = base.unix_permissions(mode);
        if entry.file_type().is_dir() {
            zip.add_directory(name, options)
                .map_err(|e| format!("{name}: {e}"))?;
        } else {
            zip.start_file(name, options)
                .map_err(|e| format!("{name}: {e}"))?;
            let mut file = File::open(entry.path()).map_err(|e| format!("{name}: {e}"))?;
            io::copy(&mut file, &mut zip).map_err(|e| format!("{name}: {e}"))?;
        }
    }
    zip.finish().map_err(|e| e.to_string())?;
    Ok(())
}

/// Extracts `archive` into `dest_dir`. An archive holding a symlink, or an
/// entry whose name would land outside `dest_dir`, is refused before
/// anything is written.
pub fn extract(archive: &Path, dest_dir: &Path) -> Result<(), String> {
    let file = File::open(archive).map_err(|e| format!("{}: {e}", archive.display()))?;
    let mut zip = ZipArchive::new(file).map_err(|e| format!("Not a package archive: {e}"))?;
    for i in 0..zip.len() {
        let entry = zip.by_index_raw(i).map_err(|e| e.to_string())?;
        let name = entry.name().map_err(|e| e.to_string())?;
        if entry.is_symlink() {
            return Err(format!("Archive contains symlink: {name}"));
        }
        if entry.enclosed_name().is_none() {
            return Err(format!("Archive entry escapes the package: {name}"));
        }
    }
    zip.extract(dest_dir).map_err(|e| e.to_string())
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;
    use std::io::Write;
    use std::os::unix::fs::symlink;

    fn app(dir: &Path) {
        fs::create_dir_all(dir.join("qml/pages")).unwrap();
        fs::write(dir.join("manifest.json"), br#"{"id":"org.test.app"}"#).unwrap();
        fs::write(dir.join("qml/pages/Main.qml"), "Item {}").unwrap();
        fs::write(dir.join("run.sh"), "#!/bin/sh\n").unwrap();
        fs::set_permissions(dir.join("run.sh"), fs::Permissions::from_mode(0o755)).unwrap();
    }

    fn crafted(path: &Path, build: impl FnOnce(&mut ZipWriter<File>)) {
        let mut zip = ZipWriter::new(File::create(path).unwrap());
        build(&mut zip);
        zip.finish().unwrap();
    }

    #[test]
    fn round_trip_keeps_content_tree_and_modes() {
        let tmp = tempfile::tempdir().unwrap();
        let src = tmp.path().join("src");
        app(&src);
        let pkg = tmp.path().join("app.marathon");
        create(&src, &pkg).unwrap();

        let out = tmp.path().join("out");
        extract(&pkg, &out).unwrap();
        assert_eq!(
            fs::read(out.join("qml/pages/Main.qml")).unwrap(),
            b"Item {}"
        );
        assert_eq!(
            fs::read(out.join("manifest.json")).unwrap(),
            fs::read(src.join("manifest.json")).unwrap()
        );
        let mode = fs::metadata(out.join("run.sh"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o755);
    }

    #[test]
    fn create_follows_symlinks() {
        let tmp = tempfile::tempdir().unwrap();
        let src = tmp.path().join("src");
        app(&src);
        symlink(src.join("manifest.json"), src.join("alias.json")).unwrap();
        let pkg = tmp.path().join("app.marathon");
        create(&src, &pkg).unwrap();

        let out = tmp.path().join("out");
        extract(&pkg, &out).unwrap();
        let alias = out.join("alias.json");
        assert!(!fs::symlink_metadata(&alias)
            .unwrap()
            .file_type()
            .is_symlink());
        assert_eq!(
            fs::read(alias).unwrap(),
            fs::read(src.join("manifest.json")).unwrap()
        );
    }

    #[test]
    fn create_skips_an_archive_inside_the_source() {
        let tmp = tempfile::tempdir().unwrap();
        app(tmp.path());
        let pkg = tmp.path().join("app.marathon");
        create(tmp.path(), &pkg).unwrap();
        let zip = ZipArchive::new(File::open(&pkg).unwrap()).unwrap();
        assert!(zip.index_for_name("app.marathon").is_none());
        assert!(zip.index_for_name("manifest.json").is_some());
    }

    #[test]
    fn extract_refuses_symlinks() {
        let tmp = tempfile::tempdir().unwrap();
        let pkg = tmp.path().join("evil.marathon");
        crafted(&pkg, |zip| {
            zip.add_symlink("evil_link", "/etc/passwd", SimpleFileOptions::default())
                .unwrap();
        });
        let out = tmp.path().join("out");
        let err = extract(&pkg, &out).unwrap_err();
        assert!(err.contains("symlink"), "{err}");
        assert!(!out.exists());
    }

    #[test]
    fn extract_refuses_traversal() {
        let tmp = tempfile::tempdir().unwrap();
        let pkg = tmp.path().join("evil.marathon");
        crafted(&pkg, |zip| {
            zip.start_file("../escaped.txt", SimpleFileOptions::default())
                .unwrap();
            zip.write_all(b"x").unwrap();
        });
        let out = tmp.path().join("out");
        assert!(extract(&pkg, &out).unwrap_err().contains("escapes"));
        assert!(!tmp.path().join("escaped.txt").exists());
    }

    #[test]
    fn extract_rejects_non_zip() {
        let tmp = tempfile::tempdir().unwrap();
        let pkg = tmp.path().join("junk.marathon");
        fs::write(&pkg, "not a zip").unwrap();
        assert!(extract(&pkg, &tmp.path().join("out")).is_err());
    }
}

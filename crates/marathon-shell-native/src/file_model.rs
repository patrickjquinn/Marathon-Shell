//! `FileChooserModel`: the file chooser's list, a folder's entries, folders
//! first, filtered by name globs or MIME types; or files whose names hold
//! `search` under the folder; or the recent files.

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::time::{Duration, SystemTime};

use cxx_qt::CxxQtType;
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QList, QMap, QMapPair_QString_QVariant, QModelIndex, QString, QStringList, QVariant};
use globset::{GlobBuilder, GlobSet, GlobSetBuilder};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!(<QtCore/QAbstractListModel>);
        type QAbstractListModel;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;
        include!("cxx-qt-lib/qhash.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[base = QAbstractListModel]
        #[qproperty(QString, folder, READ, WRITE, NOTIFY)]
        #[qproperty(QStringList, name_filters, cxx_name = "nameFilters", READ, WRITE, NOTIFY)]
        #[qproperty(QStringList, mime_filters, cxx_name = "mimeFilters", READ, WRITE, NOTIFY)]
        #[qproperty(bool, show_hidden, cxx_name = "showHidden", READ, WRITE, NOTIFY)]
        #[qproperty(bool, directories_only, cxx_name = "directoriesOnly", READ, WRITE, NOTIFY)]
        #[qproperty(QString, search, READ, WRITE, NOTIFY)]
        #[qproperty(bool, recent, READ, WRITE, NOTIFY)]
        #[qproperty(i32, count, READ, NOTIFY)]
        type FileChooserModel = super::FileChooserModelRust;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut FileChooserModel>);
        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut FileChooserModel>);
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &FileChooserModel, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn data(self: &FileChooserModel, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &FileChooserModel) -> QHash_i32_QByteArray;

        /// Home and the media folders: [{name, path}]
        #[qinvokable]
        fn places(self: &FileChooserModel) -> QList_QVariant;
        #[qinvokable]
        fn exists(self: &FileChooserModel, path: &QString) -> bool;
        #[qinvokable]
        fn join(self: &FileChooserModel, folder: &QString, name: &QString) -> QString;
    }

    impl cxx_qt::Initialize for FileChooserModel {}
}

use qobject::FileChooserModel;

const MAX_SEARCH: usize = 500;
const MAX_RECENT: usize = 100;
const RECENT: Duration = Duration::from_hours(30 * 24);
const VISITED: usize = 20_000;
const ROLES: [&str; 6] = ["name", "path", "isDir", "size", "isImage", "url"];
const USER_ROLE: i32 = 0x0100;

struct Entry {
    name: String,
    path: PathBuf,
    dir: bool,
    size: u64,
    modified: SystemTime,
    image: bool,
}

#[derive(Default)]
pub struct FileChooserModelRust {
    folder: QString,
    name_filters: QStringList,
    mime_filters: QStringList,
    show_hidden: bool,
    directories_only: bool,
    search: QString,
    recent: bool,
    count: i32,
    entries: Vec<Entry>,
}

fn strings(list: &QStringList) -> Vec<String> {
    QList::<QString>::from(list).iter().map(ToString::to_string).collect()
}

fn hidden(path: &Path) -> bool {
    path.file_name().is_some_and(|n| n.to_string_lossy().starts_with('.'))
}

fn mime(path: &Path) -> Option<mime_guess::Mime> {
    mime_guess::from_path(path).first()
}

/// What the filters let through.
struct Accepts {
    globs: GlobSet,
    any_glob: bool,
    mimes: Vec<String>,
    dirs_only: bool,
}

impl Accepts {
    fn new(m: &FileChooserModelRust) -> Self {
        let globs = strings(&m.name_filters);
        let mut set = GlobSetBuilder::new();
        for g in &globs {
            if let Ok(glob) = GlobBuilder::new(g).case_insensitive(true).literal_separator(true).build() {
                set.add(glob);
            }
        }
        Self { globs: set.build().unwrap_or_else(|_| GlobSet::empty()), any_glob: !globs.is_empty(), mimes: strings(&m.mime_filters), dirs_only: m.directories_only }
    }

    fn file(&self, path: &Path) -> bool {
        if self.dirs_only {
            return false;
        }
        if !self.any_glob && self.mimes.is_empty() {
            return true;
        }
        if path.file_name().is_some_and(|n| self.globs.is_match(n)) {
            return true;
        }
        let Some(m) = mime(path) else { return false };
        self.mimes.iter().any(|want| want.strip_suffix("/*").map_or_else(|| m.essence_str() == want, |kind| m.type_() == kind))
    }
}

fn entry(path: PathBuf, meta: &std::fs::Metadata) -> Entry {
    let image = !meta.is_dir() && mime(&path).is_some_and(|m| m.type_() == mime_guess::mime::IMAGE);
    Entry {
        name: path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
        dir: meta.is_dir(),
        size: meta.len(),
        modified: meta.modified().unwrap_or(SystemTime::UNIX_EPOCH),
        image,
        path,
    }
}

fn media() -> Vec<(&'static str, PathBuf)> {
    let home = marathon_rt::dirs::home();
    // Without user-dirs.dirs, the folders' usual names in the home.
    let mut out: Vec<(&str, PathBuf)> = [
        ("Documents", dirs::document_dir()),
        ("Downloads", dirs::download_dir()),
        ("Pictures", dirs::picture_dir()),
        ("Music", dirs::audio_dir()),
        ("Videos", dirs::video_dir()),
    ]
    .into_iter()
    .map(|(n, p)| (n, p.unwrap_or_else(|| home.join(n))))
    .filter(|(_, p)| *p != home && p.is_dir())
    .collect();
    let dcim = home.join("DCIM");
    if dcim.is_dir() {
        out.push(("Camera", dcim));
    }
    out
}

/// The files touched lately: GTK's recently-used list and the media folders.
fn recent(accepts: &Accepts) -> Vec<Entry> {
    let since = SystemTime::now() - RECENT;
    let mut paths: Vec<PathBuf> = Vec::new();
    if let Ok(xbel) = std::fs::read_to_string(marathon_rt::dirs::data().join("recently-used.xbel")) {
        let mut reader = quick_xml::Reader::from_str(&xbel);
        while let Ok(event) = reader.read_event() {
            match event {
                quick_xml::events::Event::Start(e) | quick_xml::events::Event::Empty(e) if AsRef::<str>::as_ref(&e.name()) == "bookmark" => {
                    let href = e.try_get_attribute("href").ok().flatten().and_then(|a| a.normalized_value(quick_xml::XmlVersion::default()).ok().map(std::borrow::Cow::into_owned));
                    if let Some(p) = href.and_then(|h| url::Url::parse(&h).ok()).and_then(|u| u.to_file_path().ok()) {
                        paths.push(p);
                    }
                }
                quick_xml::events::Event::Eof => break,
                _ => {}
            }
        }
    }
    let walked = media().into_iter().flat_map(|(_, dir)| walkdir::WalkDir::new(dir).min_depth(1).into_iter().filter_map(Result::ok).take(VISITED)).filter(|e| e.file_type().is_file()).map(walkdir::DirEntry::into_path);
    paths.extend(walked);
    let mut seen = std::collections::HashSet::new();
    let mut out: Vec<Entry> = paths
        .into_iter()
        .filter(|p| !hidden(p) && seen.insert(p.clone()) && accepts.file(p))
        .filter_map(|p| std::fs::metadata(&p).ok().filter(|m| m.is_file() && m.modified().is_ok_and(|t| t >= since)).map(|m| entry(p, &m)))
        .collect();
    out.sort_by_key(|e| std::cmp::Reverse(e.modified));
    out.truncate(MAX_RECENT);
    out
}

impl cxx_qt::Initialize for FileChooserModel {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().on_folder_changed(FileChooserModel::reload).release();
        self.as_mut().on_name_filters_changed(FileChooserModel::reload).release();
        self.as_mut().on_mime_filters_changed(FileChooserModel::reload).release();
        self.as_mut().on_show_hidden_changed(FileChooserModel::reload).release();
        self.as_mut().on_directories_only_changed(FileChooserModel::reload).release();
        self.as_mut().on_search_changed(FileChooserModel::reload).release();
        self.as_mut().on_recent_changed(FileChooserModel::reload).release();
    }
}

impl FileChooserModel {
    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() { 0 } else { self.count }
    }

    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(e) = usize::try_from(index.row()).ok().and_then(|r| self.entries.get(r)) else { return QVariant::default() };
        let text = |s: &str| QVariant::from(&QString::from(s));
        match role - USER_ROLE - 1 {
            0 => text(&e.name),
            1 => text(&e.path.to_string_lossy()),
            2 => QVariant::from(&e.dir),
            3 => QVariant::from(&i64::try_from(e.size).unwrap_or(i64::MAX)),
            4 => QVariant::from(&e.image),
            5 => text(&url::Url::from_file_path(&e.path).map(String::from).unwrap_or_default()),
            _ => QVariant::default(),
        }
    }

    #[allow(clippy::unused_self, reason = "a QAbstractListModel override")]
    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (role, name) in (USER_ROLE + 1..).zip(ROLES) {
            roles.insert(role, QByteArray::from(name));
        }
        roles
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn places(&self) -> QList<QVariant> {
        let home = marathon_rt::dirs::home();
        let mut out = QList::<QVariant>::default();
        let place = |name: &str, path: &Path| {
            let mut m = QMap::<QMapPair_QString_QVariant>::default();
            m.insert(QString::from("name"), QVariant::from(&QString::from(name)));
            m.insert(QString::from("path"), QVariant::from(&QString::from(&*path.to_string_lossy())));
            QVariant::from(&m)
        };
        out.append(place("Home", &home));
        for (name, path) in media() {
            out.append(place(name, &path));
        }
        out
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn exists(&self, path: &QString) -> bool {
        Path::new(&path.to_string()).exists()
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn join(&self, folder: &QString, name: &QString) -> QString {
        QString::from(&*Path::new(&folder.to_string()).join(name.to_string()).to_string_lossy())
    }

    fn reload(mut self: Pin<&mut Self>) {
        let accepts = Accepts::new(&self);
        let folder = PathBuf::from(self.folder.to_string());
        let search = self.search.to_string().to_lowercase();
        let show_hidden = self.show_hidden;
        let mut entries: Vec<Entry> = if self.recent {
            recent(&accepts)
        } else if folder.as_os_str().is_empty() {
            Vec::new()
        } else if !search.is_empty() {
            walkdir::WalkDir::new(&folder)
                .min_depth(1)
                .into_iter()
                .filter_entry(|e| show_hidden || !hidden(e.path()))
                .filter_map(Result::ok)
                .take(VISITED)
                .filter(|e| e.file_type().is_file() && e.file_name().to_string_lossy().to_lowercase().contains(&search) && accepts.file(e.path()))
                .filter_map(|e| e.metadata().ok().map(|m| entry(e.into_path(), &m)))
                .take(MAX_SEARCH)
                .collect()
        } else {
            let mut list: Vec<Entry> = std::fs::read_dir(&folder)
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
                .filter(|e| show_hidden || !hidden(&e.path()))
                .filter_map(|e| std::fs::metadata(e.path()).ok().map(|m| entry(e.path(), &m)))
                .filter(|e| e.dir || accepts.file(&e.path))
                .collect();
            list.sort_by_key(|e| (!e.dir, e.name.to_lowercase()));
            list
        };
        entries.shrink_to_fit();
        let count = i32::try_from(entries.len()).unwrap_or(i32::MAX);
        let changed = count != self.count;
        self.as_mut().begin_reset_model();
        let mut rust = self.as_mut().rust_mut();
        rust.entries = entries;
        rust.count = count;
        self.as_mut().end_reset_model();
        if changed {
            self.count_changed();
        }
    }
}

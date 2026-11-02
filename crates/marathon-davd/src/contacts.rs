//! The address book: one vCard per contact, `<name>_<id>.vcf`, in the
//! shell's old contacts folder.

use std::collections::HashMap;
use std::fmt::Write as _;
use std::fs;
use std::io::{self, BufReader, Write};
use std::path::{Path, PathBuf};

use marathon_rt::daemon::same_number;
use zbus::{OwnedVariant as OwnedValue, Variant as Value};

pub type Row = HashMap<&'static str, Value<'static>>;

/// A number or address and its kind: "mobile", "home", "work", "fax" or
/// "other".
#[derive(Clone, Default, PartialEq, Debug)]
pub struct Entry {
    pub kind: String,
    pub value: String,
}

impl Entry {
    fn new(kind: &str, value: &str) -> Self {
        Self {
            kind: kind.to_owned(),
            value: value.to_owned(),
        }
    }

    fn row(&self) -> Row {
        Row::from([
            ("type", Value::from(self.kind.clone())),
            ("value", Value::from(self.value.clone())),
        ])
    }
}

#[derive(Clone, Default, PartialEq, Debug)]
pub struct Contact {
    pub id: i32,
    pub name: String,
    pub phones: Vec<Entry>,
    pub emails: Vec<Entry>,
    pub organization: String,
    pub note: String,
    pub favorite: bool,
}

// vCard 3.0 TYPE values, by the kind they read as; the first written.
const TEL_TYPES: &[(&str, &str)] = &[
    ("fax", "FAX"),
    ("mobile", "CELL"),
    ("mobile", "IPHONE"),
    ("home", "HOME"),
    ("work", "WORK"),
    ("other", "VOICE"),
];
const EMAIL_TYPES: &[(&str, &str)] = &[("home", "HOME"), ("work", "WORK"), ("other", "")];

fn kind_of(p: &ical::property::Property, types: &[(&'static str, &str)]) -> &'static str {
    let given: Vec<String> = p
        .params
        .iter()
        .flatten()
        .filter(|(k, _)| k.eq_ignore_ascii_case("TYPE"))
        .flat_map(|(_, v)| v.iter().flat_map(|t| t.split(',')))
        .map(str::to_ascii_uppercase)
        .collect();
    types
        .iter()
        .find(|(_, t)| given.iter().any(|g| g == t))
        .map_or("other", |(kind, _)| kind)
}

fn type_for<'a>(kind: &str, types: &[(&str, &'a str)]) -> &'a str {
    types
        .iter()
        .find(|(k, _)| *k == kind)
        .map_or("", |(_, t)| t)
}

// RFC 6350 3.4 text escaping.
fn escape(text: &str) -> String {
    text.replace('\\', "\\\\")
        .replace('\n', "\\n")
        .replace(',', "\\,")
        .replace(';', "\\;")
}

fn unescape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n' | 'N') => out.push('\n'),
            Some(other) => out.push(other),
            None => out.push('\\'),
        }
    }
    out
}

/// A list of `{type, value}` maps, as QML sends them.
fn entries(value: &Value<'_>) -> Vec<Entry> {
    let Value::Array(items) = value else {
        return Vec::new();
    };
    let text = |v: &Value<'_>| match v {
        Value::Str(s) => s.as_str().to_owned(),
        Value::Variant(inner) => match &**inner {
            Value::Str(s) => s.as_str().to_owned(),
            _ => String::new(),
        },
        _ => String::new(),
    };
    items
        .iter()
        .filter_map(|item| {
            let item = match item {
                Value::Variant(inner) => &**inner,
                other => other,
            };
            let Value::Dict(dict) = item else {
                return None;
            };
            let mut entry = Entry::default();
            for (k, v) in dict.iter() {
                match text(k).as_str() {
                    "type" => entry.kind = text(v),
                    "value" => text(v).trim().clone_into(&mut entry.value),
                    _ => {}
                }
            }
            (!entry.value.is_empty()).then_some(entry)
        })
        .collect()
}

impl Contact {
    /// The number to call: the first that is not a fax.
    pub fn phone(&self) -> &str {
        self.phones
            .iter()
            .find(|e| e.kind != "fax")
            .map_or("", |e| e.value.as_str())
    }

    pub fn email(&self) -> &str {
        self.emails.first().map_or("", |e| e.value.as_str())
    }

    pub fn row(&self) -> Row {
        let list =
            |entries: &[Entry]| Value::from(entries.iter().map(Entry::row).collect::<Vec<_>>());
        Row::from([
            ("id", Value::from(self.id)),
            ("name", Value::from(self.name.clone())),
            ("phone", Value::from(self.phone().to_owned())),
            ("email", Value::from(self.email().to_owned())),
            ("phones", list(&self.phones)),
            ("emails", list(&self.emails)),
            ("organization", Value::from(self.organization.clone())),
            ("note", Value::from(self.note.clone())),
            ("favorite", Value::from(self.favorite)),
        ])
    }

    /// The contact a vCard describes.
    pub fn from_vcard(card: &ical::parser::vcard::component::VcardContact) -> Self {
        let mut c = Self::default();
        for p in &card.properties {
            let value = p.value.as_deref().unwrap_or_default().trim();
            match p.name.to_ascii_uppercase().as_str() {
                "FN" => value.clone_into(&mut c.name),
                "ORG" => value
                    .split(';')
                    .next()
                    .unwrap_or_default()
                    .trim()
                    .clone_into(&mut c.organization),
                "EMAIL" if !value.is_empty() => c.emails.push(Entry::new(
                    kind_of(p, EMAIL_TYPES),
                    value.trim_start_matches("mailto:"),
                )),
                "TEL" if !value.is_empty() => c.phones.push(Entry::new(
                    kind_of(p, TEL_TYPES),
                    value.trim_start_matches("tel:"),
                )),
                "NOTE" => c.note = unescape(value),
                "X-MARATHON-FAVORITE" => c.favorite = value.eq_ignore_ascii_case("true"),
                _ => {}
            }
        }
        c
    }

    fn vcard(&self) -> String {
        let mut card = format!("BEGIN:VCARD\nVERSION:3.0\nFN:{}\n", self.name);
        for e in &self.phones {
            let kind = type_for(&e.kind, TEL_TYPES);
            let kind = if kind.is_empty() { "VOICE" } else { kind };
            writeln!(card, "TEL;TYPE={kind}:{}", e.value).ok();
        }
        for e in &self.emails {
            match type_for(&e.kind, EMAIL_TYPES) {
                "" => writeln!(card, "EMAIL;TYPE=INTERNET:{}", e.value),
                kind => writeln!(card, "EMAIL;TYPE=INTERNET,{kind}:{}", e.value),
            }
            .ok();
        }
        if !self.organization.is_empty() {
            writeln!(card, "ORG:{}", self.organization).ok();
        }
        if !self.note.is_empty() {
            writeln!(card, "NOTE:{}", escape(&self.note)).ok();
        }
        if self.favorite {
            card.push_str("X-MARATHON-FAVORITE:TRUE\n");
        }
        card + "END:VCARD\n"
    }

    fn file_name(&self) -> String {
        let name: String = self
            .name
            .chars()
            .map(|c| if "/\\:*?\"<>| ".contains(c) { '_' } else { c })
            .collect();
        format!("{name}_{}.vcf", self.id)
    }

    /// `updateContact`'s fields; the others stay. `phone` and `email`
    /// replace the first number to call and the first address.
    pub fn update(&mut self, data: &HashMap<String, OwnedValue>) {
        let text = |key: &str| {
            data.get(key)
                .and_then(|v| String::try_from(v.try_clone().ok()?).ok())
        };
        for (key, field) in [
            ("name", &mut self.name),
            ("organization", &mut self.organization),
            ("note", &mut self.note),
        ] {
            if let Some(value) = text(key) {
                *field = value;
            }
        }
        if let Some(phones) = data.get("phones") {
            self.phones = entries(phones);
        }
        if let Some(emails) = data.get("emails") {
            self.emails = entries(emails);
        }
        if let Some(phone) = text("phone") {
            match self.phones.iter().position(|e| e.kind != "fax") {
                Some(i) => self.phones[i].value = phone,
                None => self.phones.push(Entry::new("mobile", &phone)),
            }
            self.phones.retain(|e| !e.value.is_empty());
        }
        if let Some(email) = text("email") {
            match self.emails.first_mut() {
                Some(first) => first.value = email,
                None => self.emails.push(Entry::new("home", &email)),
            }
            self.emails.retain(|e| !e.value.is_empty());
        }
        if let Some(favorite) = data.get("favorite").and_then(|v| bool::try_from(v).ok()) {
            self.favorite = favorite;
        }
    }
}

pub struct Book {
    dir: PathBuf,
    contacts: Vec<Contact>,
}

impl Book {
    pub fn open(dir: PathBuf) -> Self {
        fs::create_dir_all(&dir).ok();
        let mut contacts = Vec::new();
        let mut files: Vec<_> = fs::read_dir(&dir)
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| e.path())
            .collect();
        files.sort();
        for path in files
            .into_iter()
            .filter(|p| p.extension().is_some_and(|e| e == "vcf"))
        {
            let Ok(file) = fs::File::open(&path) else {
                continue;
            };
            let Some(Ok(card)) = ical::VcardParser::new(BufReader::new(file)).next() else {
                continue;
            };
            let mut contact = Contact::from_vcard(&card);
            let id = path
                .file_stem()
                .and_then(|s| s.to_str()?.rsplit_once('_')?.1.parse().ok());
            contact.id = id.unwrap_or(0);
            if !contact.name.is_empty() {
                contacts.push(contact);
            }
        }
        let mut top = contacts.iter().map(|c| c.id).max().unwrap_or(0);
        for c in contacts.iter_mut().filter(|c| c.id <= 0) {
            top += 1;
            c.id = top;
        }
        Self { dir, contacts }
    }

    pub fn all(&self) -> &[Contact] {
        &self.contacts
    }

    pub fn get(&self, id: i32) -> Option<&Contact> {
        self.contacts.iter().find(|c| c.id == id)
    }

    pub fn by_number(&self, number: &str) -> Option<&Contact> {
        self.contacts
            .iter()
            .find(|c| c.phones.iter().any(|e| same_number(&e.value, number)))
    }

    pub fn search(&self, query: &str) -> Vec<&Contact> {
        let q = query.to_lowercase();
        self.contacts
            .iter()
            .filter(|c| {
                c.name.to_lowercase().contains(&q)
                    || c.phones.iter().any(|e| e.value.contains(query))
                    || c.emails.iter().any(|e| e.value.to_lowercase().contains(&q))
            })
            .collect()
    }

    fn save(&self, contact: &Contact) -> io::Result<()> {
        fs::create_dir_all(&self.dir)?;
        let target = self
            .file(contact.id)?
            .unwrap_or_else(|| self.dir.join(contact.file_name()));
        write_atomic(&target, contact.vcard().as_bytes())
    }

    fn file(&self, id: i32) -> io::Result<Option<PathBuf>> {
        let suffix = format!("_{id}.vcf");
        let mut files = Vec::new();
        for entry in fs::read_dir(&self.dir)? {
            let entry = entry?;
            if entry.file_name().to_string_lossy().ends_with(&suffix) {
                files.push(entry.path());
            }
        }
        files.sort();
        Ok(files.into_iter().next())
    }

    fn remove_files(&self, id: i32) -> io::Result<()> {
        let suffix = format!("_{id}.vcf");
        for entry in fs::read_dir(&self.dir)? {
            let entry = entry?;
            if entry.file_name().to_string_lossy().ends_with(&suffix) {
                fs::remove_file(entry.path())?;
            }
        }
        Ok(())
    }

    /// The new contact's id; none without a name.
    pub fn add(&mut self, mut contact: Contact) -> io::Result<Option<i32>> {
        if contact.name.is_empty() {
            return Ok(None);
        }
        contact.id = self.contacts.iter().map(|c| c.id).max().unwrap_or(0) + 1;
        self.save(&contact)?;
        self.contacts.push(contact);
        Ok(self.contacts.last().map(|c| c.id))
    }

    pub fn update(&mut self, id: i32, data: &HashMap<String, OwnedValue>) -> io::Result<bool> {
        let Some(index) = self.contacts.iter().position(|c| c.id == id) else {
            return Ok(false);
        };
        let mut contact = self.contacts[index].clone();
        contact.update(data);
        self.save(&contact)?;
        self.contacts[index] = contact;
        Ok(true)
    }

    /// Takes a synced contact: a new one, or one already here by that name
    /// with its numbers and addresses from the server. The id when changed.
    pub fn merge(&mut self, synced: Contact) -> io::Result<Option<i32>> {
        let Some(index) = self.contacts.iter().position(|c| c.name == synced.name) else {
            return self.add(synced);
        };
        let known = &self.contacts[index];
        let merged = Contact {
            id: known.id,
            favorite: known.favorite,
            ..synced
        };
        if *known == merged {
            return Ok(None);
        }
        self.save(&merged)?;
        self.contacts[index] = merged.clone();
        Ok(Some(merged.id))
    }

    pub fn delete(&mut self, id: i32) -> io::Result<bool> {
        if !self.contacts.iter().any(|c| c.id == id) {
            return Ok(false);
        }
        self.remove_files(id)?;
        self.contacts.retain(|c| c.id != id);
        Ok(true)
    }
}

fn write_atomic(path: &Path, contents: &[u8]) -> io::Result<()> {
    let temporary = path.with_extension("tmp");
    let write = || -> io::Result<()> {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&temporary)?;
        file.write_all(contents)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary, path)
    };
    if let Err(error) = write() {
        fs::remove_file(temporary).ok();
        return Err(error);
    }
    Ok(())
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn maya() -> Contact {
        Contact {
            name: "Maya Chen".into(),
            phones: vec![Entry::new("mobile", "+1 415 555 0142")],
            emails: vec![Entry::new("home", "maya@example.com")],
            ..Contact::default()
        }
    }

    #[test]
    fn contacts_survive_a_restart() {
        let dir = tempfile::tempdir().unwrap();
        let mut book = Book::open(dir.path().to_owned());
        let id = book.add(maya()).unwrap().unwrap();
        let update = HashMap::from([
            (
                "organization".to_owned(),
                OwnedValue::from(zbus::Str::from("Acme")),
            ),
            ("favorite".to_owned(), OwnedValue::from(true)),
        ]);
        assert!(book.update(id, &update).unwrap());
        let book = Book::open(dir.path().to_owned());
        let c = book.get(id).unwrap();
        assert_eq!((c.organization.as_str(), c.favorite), ("Acme", true));
        assert_eq!(book.by_number("4155550142").map(|c| c.id), Some(id));
    }

    // A renamed contact left its old file behind, and came back twice.
    #[test]
    fn a_renamed_contact_is_one_file() {
        let dir = tempfile::tempdir().unwrap();
        let mut book = Book::open(dir.path().to_owned());
        let id = book.add(maya()).unwrap().unwrap();
        book.update(
            id,
            &HashMap::from([(
                "name".to_owned(),
                OwnedValue::from(zbus::Str::from("Maya Lee")),
            )]),
        )
        .unwrap();
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
        assert_eq!(Book::open(dir.path().to_owned()).all().len(), 1);
        assert!(book.delete(id).unwrap());
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 0);
    }

    #[test]
    fn a_synced_contact_is_merged_by_name() {
        let dir = tempfile::tempdir().unwrap();
        let mut book = Book::open(dir.path().to_owned());
        let id = book.add(maya()).unwrap().unwrap();
        assert_eq!(book.merge(maya()).unwrap(), None);
        assert_eq!(
            book.merge(Contact {
                phones: vec![Entry::new("mobile", "+1 415 555 0199")],
                ..maya()
            })
            .unwrap(),
            Some(id)
        );
        assert_eq!(book.all().len(), 1);
    }

    #[test]
    fn failed_add_is_not_kept_in_memory() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("not-a-directory");
        fs::write(&path, "occupied").unwrap();
        let mut book = Book::open(path);

        assert!(book.add(maya()).is_err());
        assert_eq!(book.all(), &[] as &[Contact]);
    }

    #[test]
    fn failed_update_preserves_the_saved_and_in_memory_contact() {
        let dir = tempfile::tempdir().unwrap();
        let mut book = Book::open(dir.path().to_owned());
        let id = book.add(maya()).unwrap().unwrap();
        fs::create_dir(book.file(id).unwrap().unwrap().with_extension("tmp")).unwrap();
        let update = HashMap::from([(
            "name".to_owned(),
            OwnedValue::from(zbus::Str::from("Maya Lee")),
        )]);

        assert!(book.update(id, &update).is_err());
        assert_eq!(book.get(id).unwrap().name, "Maya Chen");
        assert_eq!(
            Book::open(dir.path().to_owned()).get(id).unwrap().name,
            "Maya Chen"
        );
    }

    #[test]
    fn a_servers_vcard_is_read() {
        let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:1\r\nFN:Sam\r\n Rivera\r\nTEL;TYPE=fax:+15550001\r\nTEL;TYPE=cell:tel:+15550002\r\nEMAIL:mailto:sam@example.com\r\nORG:Acme;Labs\r\nEND:VCARD\r\n";
        let parsed = ical::VcardParser::new(BufReader::new(card.as_bytes()))
            .next()
            .unwrap()
            .unwrap();
        let c = Contact::from_vcard(&parsed);
        assert_eq!(
            (
                c.name.as_str(),
                c.phone(),
                c.email(),
                c.organization.as_str()
            ),
            ("SamRivera", "+15550002", "sam@example.com", "Acme")
        );
        assert_eq!(
            c.phones,
            [
                Entry::new("fax", "+15550001"),
                Entry::new("mobile", "+15550002")
            ]
        );
    }

    // A second number and a note were dropped on the next save.
    #[test]
    fn every_number_address_and_the_note_are_kept() {
        let dir = tempfile::tempdir().unwrap();
        let mut book = Book::open(dir.path().to_owned());
        let id = book.add(maya()).unwrap().unwrap();
        let entry = |kind: &str, value: &str| {
            Value::from(HashMap::from([
                ("type".to_owned(), Value::from(kind.to_owned())),
                ("value".to_owned(), Value::from(value.to_owned())),
            ]))
        };
        let update = HashMap::from([
            (
                "phones".to_owned(),
                OwnedValue::try_from(Value::from(vec![
                    entry("mobile", "+1 415 555 0142"),
                    entry("work", "+1 415 555 0100"),
                    entry("home", " "),
                ]))
                .unwrap(),
            ),
            (
                "emails".to_owned(),
                OwnedValue::try_from(Value::from(vec![
                    entry("work", "maya@acme.example"),
                    entry("home", "maya@example.com"),
                ]))
                .unwrap(),
            ),
            (
                "note".to_owned(),
                OwnedValue::from(zbus::Str::from("Gate code 4521; ring twice,\nthen wait")),
            ),
        ]);
        assert!(book.update(id, &update).unwrap());
        let book = Book::open(dir.path().to_owned());
        let c = book.get(id).unwrap();
        assert_eq!(
            c.phones,
            [
                Entry::new("mobile", "+1 415 555 0142"),
                Entry::new("work", "+1 415 555 0100")
            ]
        );
        assert_eq!(c.email(), "maya@acme.example");
        assert_eq!(c.emails[1], Entry::new("home", "maya@example.com"));
        assert_eq!(c.note, "Gate code 4521; ring twice,\nthen wait");
        assert_eq!(book.by_number("4155550100").map(|c| c.id), Some(id));
    }
}

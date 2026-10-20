//! The address book: one vCard per contact, `<name>_<id>.vcf`, in the
//! shell's old contacts folder.

use std::collections::HashMap;
use std::fs;
use std::io::BufReader;
use std::path::PathBuf;

use marathon_rt::daemon::same_number;
use zbus::zvariant::{OwnedValue, Value};

pub type Row = HashMap<&'static str, Value<'static>>;

#[derive(Clone, Default, PartialEq, Debug)]
pub struct Contact {
    pub id: i32,
    pub name: String,
    pub phone: String,
    pub email: String,
    pub organization: String,
    pub favorite: bool,
}

impl Contact {
    pub fn row(&self) -> Row {
        Row::from([
            ("id", Value::from(self.id)),
            ("name", Value::from(self.name.clone())),
            ("phone", Value::from(self.phone.clone())),
            ("email", Value::from(self.email.clone())),
            ("organization", Value::from(self.organization.clone())),
            ("favorite", Value::from(self.favorite)),
        ])
    }

    /// The contact a vCard describes, its first number and address
    /// (a number that is not a fax first).
    pub fn from_vcard(card: &ical::parser::vcard::component::VcardContact) -> Self {
        let mut c = Self::default();
        let mut phones = Vec::new();
        for p in &card.properties {
            let value = p.value.as_deref().unwrap_or_default().trim();
            match p.name.to_ascii_uppercase().as_str() {
                "FN" => value.clone_into(&mut c.name),
                "ORG" => value.split(';').next().unwrap_or_default().trim().clone_into(&mut c.organization),
                "EMAIL" if c.email.is_empty() => value.trim_start_matches("mailto:").clone_into(&mut c.email),
                "TEL" => {
                    let fax = p.params.iter().flatten().any(|(k, v)| k.eq_ignore_ascii_case("TYPE") && v.iter().any(|t| t.eq_ignore_ascii_case("fax")));
                    phones.push((fax, value.trim_start_matches("tel:").to_owned()));
                }
                "X-MARATHON-FAVORITE" => c.favorite = value.eq_ignore_ascii_case("true"),
                _ => {}
            }
        }
        phones.sort_by_key(|(fax, _)| *fax);
        c.phone = phones.into_iter().next().map(|(_, n)| n).unwrap_or_default();
        c
    }

    fn vcard(&self) -> String {
        let mut card = format!("BEGIN:VCARD\nVERSION:3.0\nFN:{}\n", self.name);
        for (key, value) in [("TEL;TYPE=CELL", &self.phone), ("EMAIL;TYPE=INTERNET", &self.email), ("ORG", &self.organization)] {
            if !value.is_empty() {
                card.push_str(&[key, ":", value.as_str(), "\n"].concat());
            }
        }
        if self.favorite {
            card.push_str("X-MARATHON-FAVORITE:TRUE\n");
        }
        card + "END:VCARD\n"
    }

    fn file_name(&self) -> String {
        let name: String = self.name.chars().map(|c| if "/\\:*?\"<>| ".contains(c) { '_' } else { c }).collect();
        format!("{name}_{}.vcf", self.id)
    }

    /// `updateContact`'s fields; the others stay.
    pub fn update(&mut self, data: &HashMap<String, OwnedValue>) {
        let text = |key: &str| data.get(key).and_then(|v| String::try_from(v.try_clone().ok()?).ok());
        for (key, field) in [("name", &mut self.name), ("phone", &mut self.phone), ("email", &mut self.email), ("organization", &mut self.organization)] {
            if let Some(value) = text(key) {
                *field = value;
            }
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
        let mut files: Vec<_> = fs::read_dir(&dir).into_iter().flatten().flatten().map(|e| e.path()).collect();
        files.sort();
        for path in files.into_iter().filter(|p| p.extension().is_some_and(|e| e == "vcf")) {
            let Ok(file) = fs::File::open(&path) else { continue };
            let Some(Ok(card)) = ical::VcardParser::new(BufReader::new(file)).next() else { continue };
            let mut contact = Contact::from_vcard(&card);
            let id = path.file_stem().and_then(|s| s.to_str()?.rsplit_once('_')?.1.parse().ok());
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
        self.contacts.iter().find(|c| same_number(&c.phone, number))
    }

    pub fn search(&self, query: &str) -> Vec<&Contact> {
        let q = query.to_lowercase();
        self.contacts
            .iter()
            .filter(|c| c.name.to_lowercase().contains(&q) || c.phone.contains(query) || c.email.to_lowercase().contains(&q))
            .collect()
    }

    fn save(&self, contact: &Contact) {
        self.remove_files(contact.id);
        if let Err(e) = fs::write(self.dir.join(contact.file_name()), contact.vcard()) {
            marathon_rt::log::warn("Contacts", format_args!("cannot save {}: {e}", contact.name));
        }
    }

    fn remove_files(&self, id: i32) {
        let suffix = format!("_{id}.vcf");
        for entry in fs::read_dir(&self.dir).into_iter().flatten().flatten() {
            if entry.file_name().to_string_lossy().ends_with(&suffix) {
                fs::remove_file(entry.path()).ok();
            }
        }
    }

    /// The new contact's id; none without a name.
    pub fn add(&mut self, mut contact: Contact) -> Option<i32> {
        if contact.name.is_empty() {
            return None;
        }
        contact.id = self.contacts.iter().map(|c| c.id).max().unwrap_or(0) + 1;
        self.save(&contact);
        self.contacts.push(contact);
        self.contacts.last().map(|c| c.id)
    }

    pub fn update(&mut self, id: i32, data: &HashMap<String, OwnedValue>) -> bool {
        let Some(contact) = self.contacts.iter_mut().find(|c| c.id == id) else { return false };
        contact.update(data);
        let contact = contact.clone();
        self.save(&contact);
        true
    }

    /// Takes a synced contact: a new one, or one already here by that name
    /// with its numbers and addresses from the server. The id when changed.
    pub fn merge(&mut self, synced: Contact) -> Option<i32> {
        let Some(known) = self.contacts.iter_mut().find(|c| c.name == synced.name) else { return self.add(synced) };
        let merged = Contact { id: known.id, favorite: known.favorite, ..synced };
        if *known == merged {
            return None;
        }
        *known = merged.clone();
        self.save(&merged);
        Some(merged.id)
    }

    pub fn delete(&mut self, id: i32) -> bool {
        let before = self.contacts.len();
        self.contacts.retain(|c| c.id != id);
        self.remove_files(id);
        self.contacts.len() < before
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn maya() -> Contact {
        Contact { name: "Maya Chen".into(), phone: "+1 415 555 0142".into(), email: "maya@example.com".into(), ..Contact::default() }
    }

    #[test]
    fn contacts_survive_a_restart() {
        let dir = tempfile::tempdir().unwrap();
        let mut book = Book::open(dir.path().to_owned());
        let id = book.add(maya()).unwrap();
        let update = HashMap::from([("organization".to_owned(), OwnedValue::from(zbus::zvariant::Str::from("Acme"))), ("favorite".to_owned(), OwnedValue::from(true))]);
        assert!(book.update(id, &update));
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
        let id = book.add(maya()).unwrap();
        book.update(id, &HashMap::from([("name".to_owned(), OwnedValue::from(zbus::zvariant::Str::from("Maya Lee")))]));
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
        assert_eq!(Book::open(dir.path().to_owned()).all().len(), 1);
        assert!(book.delete(id));
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 0);
    }

    #[test]
    fn a_synced_contact_is_merged_by_name() {
        let dir = tempfile::tempdir().unwrap();
        let mut book = Book::open(dir.path().to_owned());
        let id = book.add(maya()).unwrap();
        assert_eq!(book.merge(maya()), None);
        assert_eq!(book.merge(Contact { phone: "+1 415 555 0199".into(), ..maya() }), Some(id));
        assert_eq!(book.all().len(), 1);
    }

    #[test]
    fn a_servers_vcard_is_read() {
        let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:1\r\nFN:Sam\r\n Rivera\r\nTEL;TYPE=fax:+15550001\r\nTEL;TYPE=cell:tel:+15550002\r\nEMAIL:mailto:sam@example.com\r\nORG:Acme;Labs\r\nEND:VCARD\r\n";
        let parsed = ical::VcardParser::new(BufReader::new(card.as_bytes())).next().unwrap().unwrap();
        let c = Contact::from_vcard(&parsed);
        assert_eq!((c.name.as_str(), c.phone.as_str(), c.email.as_str(), c.organization.as_str()), ("SamRivera", "+15550002", "sam@example.com", "Acme"));
    }
}

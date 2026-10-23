//! Passwords and OAuth refresh tokens, in the session's keyring (Secret
//! Service), never in the store.

use std::collections::HashMap;

use secret_service::{EncryptionType, SecretService};

use crate::store::Account;

fn attributes(account: i64) -> (String, HashMap<&'static str, String>) {
    let id = account.to_string();
    (
        id.clone(),
        HashMap::from([("service", "marathon-mail".to_owned()), ("account", id)]),
    )
}

pub async fn store(account: i64, secret: &str) -> Result<(), String> {
    let ss = SecretService::connect(EncryptionType::Dh)
        .await
        .map_err(|e| e.to_string())?;
    let collection = ss
        .get_default_collection()
        .await
        .map_err(|e| e.to_string())?;
    if collection.is_locked().await.unwrap_or(false) {
        collection.unlock().await.map_err(|e| e.to_string())?;
    }
    let (id, attrs) = attributes(account);
    let attrs = attrs.iter().map(|(k, v)| (*k, v.as_str())).collect();
    collection
        .create_item(
            &format!("Marathon Mail account {id}"),
            attrs,
            secret.as_bytes(),
            true,
            "text/plain",
        )
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub async fn load(account: i64) -> Result<String, String> {
    let ss = SecretService::connect(EncryptionType::Dh)
        .await
        .map_err(|e| e.to_string())?;
    let (_, attrs) = attributes(account);
    let found = ss
        .search_items(attrs.iter().map(|(k, v)| (*k, v.as_str())).collect())
        .await
        .map_err(|e| e.to_string())?;
    let item = found
        .unlocked
        .into_iter()
        .chain(found.locked)
        .next()
        .ok_or("no password in the keyring")?;
    if item.is_locked().await.unwrap_or(false) {
        item.unlock().await.map_err(|e| e.to_string())?;
    }
    String::from_utf8(item.get_secret().await.map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())
}

pub async fn remove(account: i64) {
    let Ok(ss) = SecretService::connect(EncryptionType::Dh).await else {
        return;
    };
    let (_, attrs) = attributes(account);
    if let Ok(found) = ss
        .search_items(attrs.iter().map(|(k, v)| (*k, v.as_str())).collect())
        .await
    {
        for item in found.unlocked.into_iter().chain(found.locked) {
            item.delete().await.ok();
        }
    }
}

/// What signs the account in: its password, or a fresh OAuth access token.
pub async fn credential(account: &Account) -> Result<String, String> {
    let secret = load(account.id).await?;
    if account.provider.is_empty() {
        return Ok(secret);
    }
    crate::oauth::access_token(&account.provider, account.id, &secret).await
}

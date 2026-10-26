//! The system language, handed to the session.

use crate::systemd::SystemdManagerProxy;
use crate::{io, log};

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::i18n"]
    extern "Rust" {
        /// Hands this process's `LANG` and `LANGUAGE` to the systemd user
        /// manager, unsetting there whichever is unset here.
        fn export_to_session();
    }
}

fn export_to_session() {
    let (mut set, mut unset) = (Vec::new(), Vec::new());
    for key in ["LANG", "LANGUAGE"] {
        match std::env::var(key) {
            Ok(value) if !value.is_empty() => set.push(format!("{key}={value}")),
            _ => unset.push(key.to_owned()),
        }
    }
    io::spawn(async move {
        let result = async {
            let manager = SystemdManagerProxy::new(&io::session_bus().await?).await?;
            manager.unset_and_set_environment(&unset, &set).await
        };
        if let Err(e) = result.await {
            log::warn("i18n", format_args!("session keeps its old language: {e}"));
        }
    });
}

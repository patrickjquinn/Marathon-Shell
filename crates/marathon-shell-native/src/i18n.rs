//! The system language, as the shell resolves it and hands it to the session.

use cxx_qt_lib::QString;

use crate::systemd::SystemdManagerProxy;
use crate::{io, log};

#[cxx_qt::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[namespace = "marathon::i18n"]
    extern "Rust" {
        /// `marathon_i18n::resolve`; `env` is the image's `LANGUAGE` or `LANG`.
        fn resolve(setting: &QString, env: &QString) -> QString;
        /// Hands this process's `LANG` and `LANGUAGE` to the systemd user manager.
        fn export_to_session();
    }
}

fn resolve(setting: &QString, env: &QString) -> QString {
    let env = env.to_string();
    QString::from(marathon_i18n::resolve(&setting.to_string(), Some(&env)))
}

fn export_to_session() {
    let assignments: Vec<String> = ["LANG", "LANGUAGE"]
        .into_iter()
        .filter_map(|key| Some(format!("{key}={}", std::env::var(key).ok()?)))
        .collect();
    io::spawn(async move {
        let result = async {
            let manager = SystemdManagerProxy::new(&io::session_bus().await?).await?;
            manager.set_environment(&assignments).await
        };
        if let Err(e) = result.await {
            log::warn("i18n", format_args!("session keeps its old language: {e}"));
        }
    });
}

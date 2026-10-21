//! Marathon's apps: their manifests, packages and signatures, the catalogue
//! of what is installed, and installing and removing the user's.

pub mod apps;
pub mod archive;
pub mod install;
pub mod manifest;
pub mod paths;
pub use marathon_permissions as permissions;
pub mod signature;

//! D-Bus values as QML's `QVariant`s and back, as `QtDBus` marshals them:
//! `a{sv}` is a `QVariantMap`, `av` a `QVariantList`.

use std::collections::HashMap;

use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QMetaTypeType, QString, QStringList, QVariant};
use zbus::zvariant::{OwnedValue, Value};

/// Any of D-Bus's integers.
pub fn number(value: &Value<'_>) -> Option<i64> {
    match value {
        Value::U8(n) => Some(i64::from(*n)),
        Value::I16(n) => Some(i64::from(*n)),
        Value::U16(n) => Some(i64::from(*n)),
        Value::I32(n) => Some(i64::from(*n)),
        Value::U32(n) => Some(i64::from(*n)),
        Value::I64(n) => Some(*n),
        Value::U64(n) => i64::try_from(*n).ok(),
        Value::Value(inner) => number(inner),
        _ => None,
    }
}

pub fn to_qt(value: &Value<'_>) -> QVariant {
    match value {
        Value::Bool(b) => QVariant::from(b),
        Value::F64(f) => QVariant::from(f),
        Value::Str(s) => QVariant::from(&QString::from(s.as_str())),
        Value::ObjectPath(p) => QVariant::from(&QString::from(p.as_str())),
        Value::Value(inner) => to_qt(inner),
        Value::Array(items) => {
            let mut list = QList::<QVariant>::default();
            for item in items.iter() {
                list.append(to_qt(item));
            }
            QVariant::from(&list)
        }
        Value::Dict(dict) => {
            let mut map = QMap::<QMapPair_QString_QVariant>::default();
            for (key, item) in dict.iter() {
                let key = match key {
                    Value::Str(s) => s.as_str().to_owned(),
                    other => number(other).map(|n| n.to_string()).unwrap_or_default(),
                };
                map.insert(QString::from(&key), to_qt(item));
            }
            QVariant::from(&map)
        }
        Value::Structure(fields) => {
            let mut list = QList::<QVariant>::default();
            for field in fields.fields() {
                list.append(to_qt(field));
            }
            QVariant::from(&list)
        }
        other => number(other).map_or_else(QVariant::default, |n| match i32::try_from(n) {
            Ok(n) => QVariant::from(&n),
            Err(_) => QVariant::from(&n),
        }),
    }
}

/// An `av` reply as a `QVariantList`.
pub fn qlist(items: &[OwnedValue]) -> QList<QVariant> {
    let mut list = QList::<QVariant>::default();
    for item in items {
        list.append(to_qt(item));
    }
    list
}

/// An `a{sv}` reply as a `QVariantMap`.
pub fn qmap<S: std::hash::BuildHasher>(entries: &HashMap<String, OwnedValue, S>) -> QMap<QMapPair_QString_QVariant> {
    let mut map = QMap::<QMapPair_QString_QVariant>::default();
    for (key, item) in entries {
        map.insert(QString::from(key), to_qt(item));
    }
    map
}

/// A QML value for a D-Bus `v`; `None` for types D-Bus has no word for.
pub fn from_qt(value: &QVariant) -> Option<Value<'static>> {
    Some(match value.type_id() {
        QMetaTypeType::Bool => value.value::<bool>()?.into(),
        QMetaTypeType::Int => value.value::<i32>()?.into(),
        QMetaTypeType::UInt => value.value::<u32>()?.into(),
        QMetaTypeType::LongLong => value.value::<i64>()?.into(),
        QMetaTypeType::ULongLong => value.value::<u64>()?.into(),
        QMetaTypeType::Double => value.value::<f64>()?.into(),
        QMetaTypeType::QString => value.value::<QString>()?.to_string().into(),
        QMetaTypeType::QStringList => {
            let list = QList::<QString>::from(&value.value::<QStringList>()?);
            list.iter().map(ToString::to_string).collect::<Vec<_>>().into()
        }
        QMetaTypeType::QVariantList => list(&value.value::<QList<QVariant>>()?).into(),
        QMetaTypeType::QVariantMap => map(&value.value::<QMap<QMapPair_QString_QVariant>>()?).into(),
        _ => return None,
    })
}

/// A `QVariantList` as `av`.
pub fn list(items: &QList<QVariant>) -> Vec<Value<'static>> {
    items.iter().filter_map(from_qt).collect()
}

/// A `QVariantMap` as `a{sv}`.
pub fn map(entries: &QMap<QMapPair_QString_QVariant>) -> HashMap<String, Value<'static>> {
    entries.iter().filter_map(|(k, v)| Some((k.to_string(), from_qt(v)?))).collect()
}

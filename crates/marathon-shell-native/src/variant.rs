//! JSON as QML's `QVariant`s, QML's values for D-Bus, and D-Bus callers'
//! numbers.

use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use serde_json::Value;
use zbus::zvariant;

/// Any D-Bus integer, or a whole double as a QML caller sends one.
#[allow(clippy::cast_possible_truncation, reason = "whole doubles only")]
pub fn number(value: &zvariant::Value<'_>) -> Option<i64> {
    match value {
        zvariant::Value::U8(n) => Some(i64::from(*n)),
        zvariant::Value::I16(n) => Some(i64::from(*n)),
        zvariant::Value::U16(n) => Some(i64::from(*n)),
        zvariant::Value::I32(n) => Some(i64::from(*n)),
        zvariant::Value::U32(n) => Some(i64::from(*n)),
        zvariant::Value::I64(n) => Some(*n),
        zvariant::Value::U64(n) => i64::try_from(*n).ok(),
        zvariant::Value::F64(f) if f.fract() == 0.0 && f.abs() < 9e15 => Some(*f as i64),
        zvariant::Value::Value(inner) => number(inner),
        _ => None,
    }
}

pub fn from_json(value: &Value) -> QVariant {
    match value {
        Value::Null => QVariant::default(),
        Value::Bool(b) => QVariant::from(b),
        Value::Number(n) => match n.as_i64() {
            Some(n) => i32::try_from(n).map_or_else(|_| QVariant::from(&n), |n| QVariant::from(&n)),
            None => QVariant::from(&n.as_f64().unwrap_or_default()),
        },
        Value::String(s) => QVariant::from(&QString::from(s)),
        Value::Array(items) => QVariant::from(&list(items)),
        Value::Object(_) => QVariant::from(&map(value)),
    }
}

pub fn list(items: &[Value]) -> QList<QVariant> {
    let mut list = QList::<QVariant>::default();
    for item in items {
        list.append(from_json(item));
    }
    list
}

/// An object's members; anything else is an empty map.
pub fn map(value: &Value) -> QMap<QMapPair_QString_QVariant> {
    let mut map = QMap::<QMapPair_QString_QVariant>::default();
    for (key, item) in value.as_object().into_iter().flatten() {
        map.insert(QString::from(key), from_json(item));
    }
    map
}

/// A QML string, number or bool as D-Bus sends it.
pub fn to_value(v: &QVariant) -> Option<zvariant::OwnedValue> {
    let owned = |v: zvariant::Value<'_>| v.try_to_owned().ok();
    match v.type_name() {
        "QString" => owned(v.value::<QString>()?.to_string().into()),
        "double" => owned(v.value::<f64>()?.into()),
        "int" => owned(v.value::<i32>()?.into()),
        "bool" => owned(v.value::<bool>()?.into()),
        _ => None,
    }
}

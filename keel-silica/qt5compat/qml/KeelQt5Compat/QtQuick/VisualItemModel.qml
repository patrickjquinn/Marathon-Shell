// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5's VisualItemModel (QtQuick 2.0) is Qt 6's ObjectModel. The attached
// `VisualItemModel.index` is not provided (attached properties belong to the
// C++ type); children can use `ObjectModel.index` from QtQml.Models instead.
import QtQml.Models 2.15

ObjectModel {
}

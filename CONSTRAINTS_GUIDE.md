# Marathon UI Constraints System

## Overview
This guide establishes layout constraints and best practices to prevent UI overflow, layout bugs, and ensure consistent component behavior across the Marathon Shell.

---

## Core Principles

### 1. **Never Use Row/Column Without Explicit Width Constraints**
**Problem**: `Row` and `Column` layouts don't automatically constrain children, leading to overflow.

**Bad**:
```qml
Row {
    anchors.fill: parent
    Icon { size: 32 }
    Text { text: "Long text..." }
    MarathonToggle { }  // Can overflow!
}
```

**Good**:
```qml
Icon {
    id: icon
    anchors.left: parent.left
    anchors.leftMargin: 16
}

Text {
    anchors.left: icon.right
    anchors.right: toggle.left  // Constrained!
    anchors.margins: 16
}

MarathonToggle {
    id: toggle
    anchors.right: parent.right
    anchors.rightMargin: 16
}
```

---

### 2. **Use Anchor-Based Layouts for Constrained UI**
**When to use anchors**:
- List items with leading icon, text, and trailing action
- Header bars with left/center/right sections
- Any layout where elements must not overflow

**Pattern**:
```qml
Rectangle {
    // Left element (fixed position)
    Icon {
        id: leftElement
        anchors.left: parent.left
        anchors.leftMargin: spacing
    }
    
    // Center element (constrained between left and right)
    Item {
        anchors.left: leftElement.right
        anchors.right: rightElement.left
        anchors.margins: spacing
        // Content here can never overflow
    }
    
    // Right element (fixed position)
    Item {
        id: rightElement
        anchors.right: parent.right
        anchors.rightMargin: spacing
    }
}
```

---

### 3. **Text Elision is Required for Unconstrained Text**
**Always specify**:
- `width` (explicit or via anchors)
- `elide: Text.ElideRight` (or `ElideMiddle`, `ElideLeft`)
- `wrapMode: Text.WordWrap` (for multi-line text)

**Example**:
```qml
Text {
    anchors.left: parent.left
    anchors.right: parent.right
    text: userProvidedString
    elide: Text.ElideRight  // Prevents overflow
    wrapMode: Text.NoWrap
}
```

---

### 4. **Use MListItem for Standard List Layouts**
The `MListItem` component enforces proper constraints automatically.

**Example**:
```qml
MListItem {
    leadingIcon: "bluetooth"
    title: "Bluetooth"
    subtitle: "Enabled"
    trailingContent: MarathonToggle {
        checked: SystemControlStore.isBluetoothOn
        onToggled: SystemControlStore.toggleBluetooth()
    }
}
```

**Features**:
- ✅ Automatic constraint management
- ✅ Text elision built-in
- ✅ Proper spacing and sizing
- ✅ Support for icons, text, and custom trailing content

---

## Component Guidelines

### MListItem
**Use for**:
- Settings toggle items
- Navigation list items
- Info display rows

**Properties**:
```qml
MListItem {
    leadingIcon: "icon-name"           // Optional leading icon
    leadingIconSize: 32                 // Icon size
    leadingIconColor: MColors.text      // Icon color
    
    title: "Title"                      // Required
    subtitle: "Subtitle"                // Optional
    
    trailingContent: Component { }      // Custom trailing component
    showChevron: false                  // Show right chevron
    clickable: false                    // Enable click interaction
    
    onClicked: { }                      // Click handler
}
```

---

### MPage
**Use for**: Full-screen pages with title bar

**Constraints**:
- Content area is automatically constrained to safe areas
- Title bar height is fixed
- Scrollable content should use `Flickable` or `ListView`

---

### MCard
**Use for**: Contained content blocks

**Constraints**:
- Always set explicit width/height or use anchors
- Content inside cards should respect padding

---

## Testing Checklist

Before committing UI components, verify:

- [ ] No `Row`/`Column` without explicit width constraints
- [ ] All text has `elide` or `wrapMode` set
- [ ] Trailing elements use `anchors.right` (not spacers or `Layout.fillWidth`)
- [ ] Components work with long text content
- [ ] Components work at different screen sizes
- [ ] No runtime warnings about "Cannot specify ... for items inside Row/Column"

---

## Migration Guide

### Migrating Existing Layouts

**Step 1**: Identify problematic `Row`/`Column` usage
```bash
grep -r "Row {" --include="*.qml"
grep -r "Column {" --include="*.qml"
```

**Step 2**: Check for anchor conflicts
- Look for warnings: "Cannot specify top, bottom, ... for items inside Column"

**Step 3**: Refactor to anchor-based or use `MListItem`

**Step 4**: Test with edge cases
- Very long text strings
- Disabled states
- Empty states

---

## Examples

### Before (Problematic)
```qml
Rectangle {
    Row {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16
        
        Icon { size: 32 }
        Column { Text { }; Text { } }
        Item { width: 1 }  // Spacer - bad!
        MarathonToggle { }  // Can overflow
    }
}
```

### After (Correct)
```qml
MListItem {
    leadingIcon: "icon-name"
    title: "Title"
    subtitle: "Subtitle"
    trailingContent: MarathonToggle {
        // Toggle config
    }
}
```

---

## Resources

- **MListItem**: `shell/qml/MarathonUI/Containers/MListItem.qml`
- **MCard**: `shell/qml/MarathonUI/Containers/MCard.qml`
- **MPage**: `shell/qml/MarathonUI/Containers/MPage.qml`
- **Spacing**: `shell/qml/MarathonUI/Theme/MSpacing.qml`
- **Colors**: `shell/qml/MarathonUI/Theme/MColors.qml`

---

## Summary

✅ **DO**:
- Use anchor-based layouts for constrained UI
- Use `MListItem` for list rows
- Always set text elision
- Test with long content

❌ **DON'T**:
- Use `Row`/`Column` without width constraints
- Use spacer `Item`s in rows
- Forget text elision
- Use `Layout.fillWidth` without `QtQuick.Layouts`


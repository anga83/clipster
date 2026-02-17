# File Type Rules Feature

## Overview
The new File Type Rules feature allows users to define special handling for specific file extensions, overriding the normal size-based behavior.

## Treatment Options

### 1. Always Symlink
- **Behavior**: Files of this type will always be symlinked, regardless of their size
- **Use Case**: For file types where you want to preserve the original file location (e.g., large video files, database files)
- **Example**: `.mov`, `.mp4`, `.db`, `.dmg`

### 2. Save Never
- **Behavior**: Files of this type will never be saved to clipboard history
- **Use Case**: For sensitive or temporary file types that shouldn't be tracked
- **Example**: `.tmp`, `.cache`, `.log`, `.key`

## How It Works

### In ClipboardMonitor
1. When a file is copied, the system first checks if there's a special rule for its extension
2. If a rule exists:
   - **Always Symlink**: Creates a symlink regardless of file size
   - **Save Never**: Skips the file entirely (returns early)
3. If no rule exists, applies normal size-based logic

### In Settings UI
1. Navigate to Settings → Files tab
2. Scroll to "File Type Rules" section
3. Click "Add Rule" to create new rules
4. Existing rules are displayed with their treatment type
5. Rules can be removed individually

## Technical Implementation

### Data Storage
- Rules are stored in the settings plist as a dictionary: `[String: String]`
- Keys are file extensions (lowercase, without dots)
- Values are treatment type raw values

### Methods Added to SettingsStore
- `setFileTypeTreatment(_:for:)` - Add/update a rule
- `removeFileTypeTreatment(for:)` - Remove a rule
- `getFileTypeTreatment(for:)` - Get treatment for extension
- `shouldApplySpecialTreatment(for:)` - Check if URL has special rules

## Example Usage

```swift
// Add rules programmatically
settingsStore.setFileTypeTreatment(.alwaysSymlink, for: "mp4")
settingsStore.setFileTypeTreatment(.saveNever, for: "tmp")

// Check for special treatment
if let treatment = settingsStore.shouldApplySpecialTreatment(for: fileURL) {
    switch treatment {
    case .alwaysSymlink:
        // Create symlink regardless of size
    case .saveNever:
        // Don't save this file
    }
}
```

## Benefits
1. **Flexibility**: Users can customize behavior per file type
2. **Performance**: Large files can be always symlinked to avoid data copying
3. **Privacy**: Sensitive file types can be excluded from history
4. **Consistency**: Predictable behavior for specific file types

## UI Features
- Clean, card-based interface for managing rules
- Modal dialog for adding new rules with validation
- Real-time preview of extension formatting
- Clear descriptions of each treatment option

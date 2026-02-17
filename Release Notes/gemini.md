# Gemini Code Assist - Project Context

This document provides context for Gemini Code Assist to help it generate accurate and high-quality code for this project.

## 1. Project Overview

Write a macOS-exclusive clipboard manager application named `Clipster` that allows users to manage their clipboard history. The application should provide a user-friendly interface for viewing, searching, and managing clipboard items. It should also support features like pinning items, deleting items, and searching through the clipboard history.

Each clipboard item should be stored with the following properties:
- **ID:** Unique identifier for the clipboard item.
- **Content:** The actual content of the clipboard item (text, image, etc.).
- **Timestamp:** When the item was added to the clipboard history.
- **Source:** The application or context from which the item was copied (e.g., "Safari", "Google Chrome", "Terminal").

The clipboard manager should also have an import and export feature, allowing users to save their clipboard history to a file and restore it later.

The user has the option to have the clipboard manager working 1) only from the menu bar (which has a small window showing the clipboard history) or 2) as a full application with a main window that shows the clipboard history and allows for more advanced management features. The user can open the main window from the menu bar icon. As long as only the menu bar window is open, the application should not show up in the Dock, but once the main window is opened, the application should appear in the Dock.

The application should be built using Swift and SwiftUI, leveraging modern macOS development practices. It should be resizable and responsive window featuring the modern macOS design language and Human Interface Guidelines. Also, it should have the title bar (window management buttons) integrated into the main window and not in a classic title bar.

Use Apple's native SF Symbols for icons and buttons to ensure a consistent look and feel with the macOS ecosystem, as well the macOS system font for all text elements.

## 2. Technology Stack

- **Languages:** Swift and SwiftUI
- **System Requirements:** macOS 11.0+ (if needed, raise the minimum version up to 14.0+)

- **IDE:** Note that I only have the Xcode Command Line Tools installed, not the full Xcode IDE. Building the application should therefore be done using `swift build` and `swift run` commands in the terminal, not the `xcodebuild` command.


## 3. Coding Conventions & Best Practices

- **Comments:** Use clear and concise comments to explain complex logic or important decisions in the code. Each function should have a brief description of its purpose and parameters.
- **File Structure:** While making sure the file structure is logical and easy to navigate, try to keep the number of files to a minimum. 
- **Documentation:** Document your current progress and to-do items in a helper Markdown file, so you can easily track what has been implemented and what still needs to be done.

- **Gemini Code Assist:** You are allowed to write all files you want into the `Gemini-Clipster` directory, but you should not write files outside of this directory. You can also create subdirectories within the `Gemini-Clipster` directory if needed.
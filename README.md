# DockMinimize

[![Listed on BuiltByVibe](https://builtbyvibe.dev/api/badge/dockminimize-ssns.svg)](https://builtbyvibe.dev/project/dockminimize-ssns)

A lightweight, simple native macOS utility that adds Windows/Linux-style **"Click Dock Icon to Minimize and Restore"** functionality to macOS.

---

## How It Works
- **App is open/visible** $\rightarrow$ Click its Dock icon to minimize it (with the native macOS minimize animation).
- **App is minimized** $\rightarrow$ Click its Dock icon to open/restore it.
- **App has multiple windows** $\rightarrow$ Minimizes all open windows with the native minimize animation.
- **Rearranging Dock icons** $\rightarrow$ Dragging icons on the Dock will never accidentally minimize apps.

---

## Quick Start

### 1. Launch
```bash
./build.sh
open DockMinimize.app
```
*(Or install it to `/Applications` using `./build.sh install`)*.

> **Note**: If you had the previous version running, restart it with `open DockMinimize.app`.

### 2. Grant Accessibility Permissions
macOS requires Accessibility access for utilities that observe Dock clicks:
1. In **System Settings > Privacy & Security > Accessibility**, ensure **DockMinimize** is toggled **ON**.
2. DockMinimize will automatically activate and show in the menu bar:  
   `Status: Active ✓`

---

## Menu Bar
A subtle menu bar icon provides:
- Live status indicator (`Status: Active ✓`).
- One-click shortcut to Accessibility settings if needed.
- **Launch at Login** toggle.
- Quit.

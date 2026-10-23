# Introduction

Pelikan is a native macOS environment for working with Oracle Database: writing and running SQL, developing and testing
PL/SQL code, browsing database objects, debugging, utPLSQL tests and administration tools. Its layout and shortcuts
follow PL/SQL Developer, so users of that program will find familiar windows: **SQL Window**, **Command Window**,
**Program Window**, **Test Window** and **Object Browser**.

## Getting started

1. Install Oracle Instant Client (Basic or Basic Light) and select its directory in **Preferences › Oracle**. Pelikan
   also detects the newest `instantclient_*` directory in Downloads. Without Instant Client, the *Thin* driver is used,
   with fewer features.
2. Add a connection definition: **Session › Connections › New connection…** or the button in the connection list.
3. Connect and open a **SQL Window** (⌘N). Type a query and execute it (F8 or ⌘↩).

## Main window

On the left there is a panel with tabs: Object Browser, File Browser, Window List, templates, To-Do and project.
In the middle are the document tabs — every SQL, program or test window has its own tab. The status bar shows the
window's connection, the transaction state, the cursor position, the file encoding and the Git branch.

Every action can be invoked from the menu, with a shortcut or from the **command palette** (⇧⌘P), which finds commands
by name.

## Languages

The interface is available in Polish, English, German, Spanish and Ukrainian. You choose the language in
**Preferences › General › Interface language**; the change takes effect after a restart.

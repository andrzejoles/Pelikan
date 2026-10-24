# Preferences and keyboard shortcuts

## Preferences window

You open it with **Pelikan › Settings…** (⌘,). Changes are saved immediately — there is no Apply button. The **Search
settings** field at the top finds a setting by name (in the interface language) and takes you to the right tab.

| Tab | What you set |
|---|---|
| General | session mode (Multi, Dual, Single), behavior on logoff with an open transaction, connection checking, pinning the connection of new windows, connection colors and `user@database` rules, appearance (system, light, dark), interface language, startup directories and additional file extensions, asking to save new windows |
| SQL Window | AutoSelect, AutoCommit, confirming COMMIT and ROLLBACK, Test Window AutoCommit, rows per page, number layout, Auto Format in the Large Data Editor, statistics, DBMS_OUTPUT (enabled, clearing before execution), DATE and TIMESTAMP formats |
| Editor | font (also ligatures) and colors, code completion (automatically after a dot, matching, case, standard functions, “(all)” layout), AutoReplace, remembering window state, keyword case, highlights, line status, wrapping, special characters, indentation and tabs |
| Formatter | PL/SQL formatting rules and automatic formatting (after opening from the database, before compilation, before saving) |
| Keyboard | shortcut profile and custom command shortcuts |
| Oracle | Instant Client, session NLS settings, closing idle sessions, Oracle documentation version for F1, Touch ID for saved passwords, Oracle Net and Oracle Wallet, compiler, debugger, compiler hints and naming conventions, DBA_ views |
| Object Browser | visible folders and order, confirming recompilation, drag actions, named filters, user folders |
| Tools | web searches, external editor, external diff viewer, documents, backups and window recovery, “Don’t ask again” prompts |
| Agents | agent programs, strict mode, agent call and query limits |
| Sets | preference sets, export and import, Quick Access toolbar |

A few settings take effect only after Pelikan is restarted: the Instant Client directory, Oracle Net and Oracle Wallet,
and the interface language.

### Backups and recovery

On the **Tools** tab you enable a copy of the previous version of a file on save (`file.~ext`) and keeping unsaved
windows for recovery after an unexpected exit (a snapshot at a set interval, optionally also before each execution).
After a crash Pelikan offers to recover the windows; you can also do it later with **File › Recover Windows…**.

### “Don’t ask again” prompts

Some prompts (e.g. COMMIT confirmation, moving to the Trash) have a **Don’t ask again** checkbox — Pelikan then
remembers your answer. The list of remembered answers and the **Show again** button are on the **Tools** tab.
Confirmations of changes on production and consents for AI agents cannot be turned off this way.

## Preference sets

Sets let you have different settings for different connections — e.g. a different date format for one database or
stricter rules for production. Pelikan applies the sets in this order (from the most important): **Connection
personal**, **Personal**, **Connection default**, **Default** for all connections. Connection sets have a
`user@database` pattern or a connection name with `*` and `%` (e.g. `app@prod*`) and apply when the main connection
matches them.

![Sets tab in Preferences](../img/zestawy-preferencji.png)

On the **Sets** tab (or **Tools › Preferences › Preference Sets…**):

1. Add a set: choose the kind, enter a name and a connection pattern, click **Add**.
2. In the **Save changes in Preferences to** field, choose the set you want to edit. From then on, changes on other tabs
   go to it.
3. Next to each setting you can see which set the value comes from; **Inherit** removes the value from the edited set.

**Export and import** saves selected sections of the effective preferences to a JSON file (**Tools › Preferences ›
Export Preferences…**) and loads them into the edited set (**Import Preferences…**). The export contains neither
passwords nor file history.

## Toolbar and Quick Access

**View › Customize Toolbar…** changes the toolbar layout with the standard macOS window. The **Quick Access** group on
the toolbar contains any commands (up to 20) — you add them on the **Sets** tab (**Quick Access Toolbar**) or from the
command palette.

## Keyboard

On the **Keyboard** tab choose the profile: **PL/SQL Developer (F keys, Ctrl)** or **macOS (Cmd)**. Search for a command
and record your own shortcut — Pelikan warns about a conflict with another shortcut. **Remove command shortcuts**,
**Command defaults** and **Restore all defaults** undo the changes. The menu shows one shortcut of a command, but all
its shortcuts work.

## Most important shortcuts

| Action | PL/SQL Developer profile | macOS profile |
|---|---|---|
| New SQL Window / Program Window | ⌘N / ⇧⌘N | ⌘N / ⇧⌘N |
| Execute | F8, ⌘↩ | ⌘↩, F8 |
| Execute opposite of AutoSelect | ⌃F8, ⇧⌘↩ | ⇧⌘↩, ⌃F8 |
| Break | ⇧⎋, ⌘. | ⌘. |
| Commit (COMMIT) / Rollback (ROLLBACK) | F10 / ⇧F10 (also ⌥⌘↩ / ⌥⌘⌫) | ⌥⌘↩ / ⌥⌘⌫ (also F10 / ⇧F10) |
| Explain Plan | F5 | F5 |
| Log on… | ⇧⌘L | ⇧⌘L |
| Code completion | ⌃Space | ⌥⎋, ⌃Space |
| Go to declaration | ⌃⌥D, ⌃⌘J | ⌃⌘J |
| Command history | ⌃E, ⇧⌘H | ⇧⌘H |
| Find and replace / go to line | ⌃F, ⌘F / ⌃G, ⌘L | ⌘F / ⌘L |
| Line comment | ⌃−, ⌘/ | ⌘/ |
| Format PL/SQL code | ⇧⌘F | ⇧⌘F |
| Search in Editors and Files | ⌥⇧⌘F | ⌥⇧⌘F |
| Find database objects | ⌃⇧O, ⇧⌘O | ⇧⌘O |
| Debugger: start / stop | F9 / ⇧F9 | F9 / ⇧F9 |
| Debugger: continue, step into, step over, step out | ⌃R, ⌃N, ⌃O, ⌃T | ⌃R, ⌃N, ⌃O, ⌃T |
| Breakpoint | ⌃B | ⌃B |
| utPLSQL: all tests / test under cursor | ⌃⇧U, ⇧⌘U / ⌃⌥U, ⌃⌘U | ⇧⌘U / ⌃⌘U |
| Macro: record / play | F11 / F12 | F11 / F12 |
| Next / previous window | ⌃⇥ / ⌃⇧⇥ | ⇧⌘] / ⇧⌘[ |
| Command palette | ⇧⌘P | ⇧⌘P |
| Oracle context help / manual | F1 / ⇧⌘/ | F1 / ⇧⌘/ |

The full list of commands with their current shortcuts (including your changes) is in the last chapter of the manual,
**Keyboard shortcuts**. The F1–F12 keys work as function keys after you enable this option in macOS System Settings, or
together with the fn key; some ⌃ shortcuts (e.g. ⌃F8, ⌃F2, ⌃F3) are intercepted by macOS — use the ⌘ equivalent or turn
off the system shortcut.

## Launching with parameters

Pelikan can be launched with parameters, e.g. from Terminal:

```
open -a Pelikan --args connection=dev_test editobject=APP.EMP_API
```

Supported parameters include `connection` (a connection name or `user@database`), `viewobject`, `editobject`,
`commandfile`, `project`, `workset`, `readonly` (patterns of the connections opened read-only in this launch),
`noloaddesktop` and file paths. The `pelikan://open?connection=…` address also works. A password in the parameters is
not supported — `userid=u/password@db` is accepted without the password and with a warning, and the password comes from
the Keychain or from a prompt.

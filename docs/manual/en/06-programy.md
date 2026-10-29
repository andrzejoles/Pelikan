# Program Window and code editor

## Program Window

The Program Window is used to write and compile PL/SQL units: packages, procedures, functions, types and triggers, as
well as Java sources and MLE modules (JavaScript). You open it with **File › New › Program Window** (⇧⌘N) or with
**Edit** on an object in the Object Browser (the code is loaded directly from the database).

![Program Window: a package with specification and body tabs, Code Contents on the left](../img/okno-programu.png)

- Each unit of the file has its own tab (e.g. the package specification and body). The **+** button next to the tabs or
  **File › Program Window › Add Unit…** adds a unit from a template (procedure, function, package, type, trigger, Java
  source, MLE module) with a form for names and parameters. **Remove Unit** removes the tab from the text (the object in
  the database stays).
- **Edit** on a package or type — also on its body from the “Package bodies” and “Type bodies” folders — opens the
  specification and the body in one window on two tabs (opened from the body: the body tab is active). An object
  without a body has a single tab.
- The editor shows only the unit of the selected tab; the active tab is pressed and bold. Switch tabs by clicking,
  with **File › Program Window › Show Unit…**, **Next Unit** (⌥⌘], in the PL/SQL Developer profile also ⌃⇟) and
  **Previous Unit** (⌥⌘[, ⌃⇞) — the cursor returns to where it was on that tab. Every jump to a place in another unit
  (compilation error, Code Contents, Find Next, Go to Declaration, bookmark, debugger, Back/Forward, Undo) switches the
  tab by itself. Arrow keys and ⌘A stay within the tab. Line numbers on the tab, the error list and **Go to Line**
  count unit lines like Oracle (ALL_SOURCE, ALL_ERRORS) — line 1 is the `PACKAGE BODY …` line. **Replace All**
  replaces in the whole window (all units).
- Units are recognised by `CREATE … PACKAGE`, `PACKAGE BODY`, `TYPE`, `PROCEDURE`, `FUNCTION`, `TRIGGER` headers at
  the start of a line — the file does not need a “/” after units. Pelikan never adds “/” when saving, and code loaded
  from the database and new units come without “/” (unless you turn on **Settings › Oracle › End program window
  units with “/”**). A file with “/” is saved unchanged.
- **F8** (⌘↩) compiles all units one by one and stops at the first one with an error. Compilation takes place in a
  separate session in the background, so it does not block SQL Windows.
- Compiler errors and warnings appear below the editor. A click moves to the line, a double-click opens the error
  description in the Oracle documentation.
- The status bar shows whether the text has been changed and not saved, and whether it is not compiled.
- **File › Save** (⌘S) saves the window text unchanged (no `/` is added), with a name and extension according to
  the unit (e.g. `.pck`, `.prc`, `.fnc`, `.typ`, `.trg`).

### Working safely with code in the database

- **Session › Trial compilation** compiles the units under a temporary name and shows errors without replacing the
  objects in the database.
- **Session › Check object changes in the database** checks whether someone else has changed the object since it was
  loaded or compiled (Pelikan also checks this periodically and warns in the status bar). You view the differences with
  **File › Compare › Compare with source in database**, and load the version from the database with **Session › Reload
  from database**.
- **File › Restore** discards the changes and returns to the text from the moment of opening, loading or saving.
- **File › Compare › Compare with file…** and **Compare with objects in another database…** (e.g. with a test database)
  open the diff viewer.
- **Session › Run block in Test Window** executes the selected anonymous block in a new Test Window with DBMS_OUTPUT.

### Compiler settings

In **Settings › Oracle › Compiler** you set `PLSQL_WARNINGS`, `PLSQL_OPTIMIZE_LEVEL`, `PLSQL_CODE_TYPE`,
`PLSCOPE_SETTINGS` and `PLSQL_CCFLAGS` — Pelikan sets them in the compilation session before every compilation of a
Program Window. In the **Debugger** section you enable automatically adding debug information, **Compiler hints**
(additional code inspections after compilation) and checking **naming conventions** (prefixes of parameters, local and
global variables, constants, cursors and types). An `-- Ignore` comment at the end of a line silences the hint for that
line.

## Code editor

The same editor works in SQL, program, test and command windows. It edits without delays even packages with tens of
thousands of lines.

### Completion and navigation

- **Code completion** appears by itself after a dot (e.g. `package.`, `alias.`, `sequence.`) or on demand: ⌥⎋ (in the
  PL/SQL Developer profile ⌃Space). It suggests schema objects, columns (also through table aliases), package elements,
  parameters in named notation, record fields and `%ROWTYPE`, collection methods, `:new`/`:old`, database links after
  `@`, and utPLSQL annotations and assertions. The **(all)** item inserts all columns or parameters at once. **Edit ›
  Refresh code completion** refreshes the dictionary cache.
- Hovering the mouse over a variable shows its declaration.
- **⌘+click** on a name or **Edit › Go to declaration** (⌃⌘J) moves to the declaration — in the same source, in another
  open window or in an object from the database (in a new window). **Edit › Navigation › Back** (⌃⌘←) and **Forward**
  (⌃⌘→) return after jumps.
- **View › Code Contents** shows the structure tree: the package (type) specification and body separately, with
  subprograms with parameters and return type (the full header in the tooltip), types (record, table, REF CURSOR,
  subtype), cursors, variables, constants, exceptions, pragmas and nested subprograms. Private body elements (not
  declared in the specification) are italic. A click or Enter moves the cursor to the element (also on another tab),
  arrow keys in the tree move the cursor without leaving the tree. The field above the tree filters names. The tree
  tracks the cursor and has sorting and a menu (select, copy, cut, test subprogram, expand/collapse all). Below the
  editor, the **code hierarchy** shows the path from the cursor (package › procedure › block); clicking a level
  selects it or moves to its name.
- The context menu on a database object name in the editor offers the same actions as the Object Browser.
- **F1** opens the Oracle documentation for the word under the cursor.

### Typing and selecting

| Action | Shortcut (macOS) | Menu |
|---|---|---|
| Line comment | ⌘/ | Edit › Selection |
| Duplicate line | ⇧⌘D | Edit › Selection |
| Uppercase / lowercase | ⌥⌘U / ⌥⇧⌘U | Edit › Selection |
| Increase / decrease indent | ⌘] / ⌘[ | Edit › Selection |
| Format PL/SQL code | ⇧⌘F | Edit |
| Find and replace | ⌘F | Edit |
| Find next / previous | ⌘G / ⇧⌘G | Edit |
| Go to line | ⌘L | Edit |
| Fold / expand block | ⌥⌘← / ⌥⌘→ | Edit |
| Fold / expand all | ⌥⇧⌘← / ⌥⇧⌘→ | Edit |
| Toggle bookmark | ⌘F3 | Edit › Bookmarks |
| Add cursor above / below | ⌃⇧↑ / ⌃⇧↓ | Edit › Multiple Cursors |
| Increase / decrease font size | ⌘= / ⌘− | View |

- **Code folding**: the arrow in the margin next to the line numbers folds and unfolds a block (a folded block has an
  accent-coloured arrow, and “⋯” in the text shows the folded code in a tooltip).
- **Multiple cursors**: ⌥+click adds a cursor, Esc leaves one. **Column selection**: drag with ⌥ — typing, Backspace and
  pasting work in all lines at once.
- **Find and replace** supports regular expressions (with `$1`), whole words, case sensitivity, case preservation, and
  searching only in code, comments or literals.
- **Bookmarks** 0–9 (in the PL/SQL Developer profile ⌃K n sets, ⌃Q n jumps), bookmark names and a list of the bookmarks
  of all windows. **Color Marks** highlight text fragments with one of six colors.
- The editor highlights matching brackets and `BEGIN`/`IF`/`LOOP`/`CASE` ↔ `END`, occurrences of the name under the
  cursor, the `INSERT` column corresponding to a value in `VALUES`, and the `COMMIT`, `ROLLBACK` and `SAVEPOINT`
  statements.
- **AutoReplace** (Settings › Editor) replaces abbreviations with text while you type; `|` in the replacement marks
  the cursor position.
- **View › Split Editor** shows two views of the same text. **View** also has **Wrap Lines**, **Special Characters** and
  **Line Status** (marks of lines changed and added since opening or saving).

### Formatting

**Edit › Format PL/SQL code** (⇧⌘F) formats the selection or the whole source according to the rules in **Settings ›
Formatter** (indentation, lists, commas, blank lines, case of keywords and identifiers, special spelling). The formatter
can run automatically after opening a source from the database, before compilation and before saving. A fragment between
the `-- NoFormat Start` and `-- NoFormat End` comments stays unchanged. Formatting never changes the meaning of the
code.

The **Settings › Formatter** tab has the groups **Layout**, **Lists and commas**, **SQL clauses and conditions**
(clause keywords left, right or on their own line; AND/OR at line start or end; the JOIN … ON condition; THEN on a new
line; multi-line CASE), **Column alignment** (declarations, parameters with mode and type, named arguments `=>`,
assignments `:=`, aliases in SELECT and FROM, `=` in UPDATE … SET, trailing comments), **Spacing** and **Letter case** —
separately for keywords, identifiers, data types, built-in functions and Oracle packages. On the right there is a
preview: a sample package that shows every option, with the lines changed by the last change highlighted, and above it
an example of the option under the pointer or the one changed last — **Now** and **After changing this option**. A
region without formatting can also be marked with the `-- @formatter:off` and `-- @formatter:on` comments.

### Templates, snippets and macros

- **Templates** (the **Templates** tab in the left column or **View › Template Window**) insert ready-made fragments:
  DML statements, loops, types, SQL functions, program units and utPLSQL templates. A double-click or dragging into the
  editor inserts a template; you fill in the template variables in a form (`$OSUSER`, `$DBUSER`, `$DATE`, `$TIME` are
  substituted automatically). You create your own templates with **Tools › Templates › Save selection as template…**.
- **View › Snippets** is a library of short fragments for dragging (built-in and your own).
- **Macros**: F11 starts and stops recording, F12 plays back, ⇧F12 plays back repeatedly. You save a macro in the
  library with a shortcut (**Edit › Macros › Save macro to library…**).
- **Edit › Copy as literal** copies the selected SQL as a string literal of a programming language (Swift, Java, C#,
  JavaScript, Python, C/C++, PHP, Delphi, Visual Basic); **Paste from programming language** does the reverse.
- **Clipboard history** (**View › Clipboard history**) keeps the last copied texts in memory.

### Code analysis and refactoring

![Analysis while typing: an unknown table and column underlined; the editor split into two views](../img/analiza-kodu.png)

- While you type, Pelikan underlines unknown tables, views, columns and aliases (according to the dictionary of the
  window's connection) and problems: unused variables and parameters, code after `RETURN`/`RAISE`, `UPDATE`/`DELETE`
  without `WHERE`, implicit conversions. F2 and ⇧F2 move to the next and previous problem, and **Edit › Code analysis ›
  Problem list** shows them all. You turn off the analysis in **Edit › Code analysis › Code analysis while typing**.
- **Edit › Refactoring › Find usages** (⌥F7) looks for usages of an object or column: dependent objects, lines of their
  code, PL/Scope, open windows and project files.
- **Edit › Refactoring › Rename…** (⇧F6) renames a variable or parameter within its scope, or an object or column in the
  windows and project files. Before applying it you see a preview of the differences; a change in the database (DDL)
  goes to a new window and is not executed.
- **Extract Local Constant…**, **Extract Global Constant…**, **Extract Procedure…** and **Replace Assignment with
  Initialization** in the same submenu transform the selected code; you undo any change with ⌘Z.

### To-Do items

`TODO` and `DONE` comments (with owner, priority and category) are collected in the **View › To-Do items** window.
**Edit › Insert To-Do item** inserts a comment, and **Close or reopen To-Do item** changes its state.

## Files

- Pelikan opens `.sql`, `.pck`, `.pks`, `.pkb`, `.spc`, `.bdy`, `.prc`, `.fnc`, `.trg`, `.typ`, `.tps` files, `.tst`
  tests and `.sqlnb` notebooks from the Finder and by dragging. You add extra program and test extensions in
  **Settings › General**. Dragging a directory opens all its scripts.
- Files keep their encoding (UTF-8, ISO-8859-2, Windows-1250) and line endings. A character that cannot be saved in the
  file's encoding blocks saving, with the exact line and column indicated — you change the encoding only deliberately
  with **File › File encoding…**.
- **File › Read Only** locks the window for editing.
- **File › Open with Connection…** opens a file with a connection pinned right away.
- **Edit › Open in External Editor** passes the text to the program set in **Settings › Tools** (e.g. Visual Studio
  Code); when you return to Pelikan, the changes are loaded.
- **Edit › Web Search** opens a search for the selected word (search engine addresses in Settings).
- Pelikan remembers the state of file windows (cursor, bookmarks, marks, folds, variable values).
- After an unexpected application exit, Pelikan offers to recover unsaved windows (**File › Recover Windows…**).

# Program Window and Object Browser

## Object Browser

A tree of objects in the current schema (or the one chosen in the filter) with folders by type: tables, views, packages,
types, triggers, sequences and, on 23ai, also MLE modules and domains. An object's context menu opens its source, shows
its description, DDL, dependencies and data, and lets you compile or drop the object. Invalid objects are marked.

## Program Window

The Program Window edits PL/SQL code: packages (specification and body on separate tabs), procedures, functions, types
and triggers. **Execute** (F8) compiles the code in the database, and compilation errors appear below the editor —
clicking one takes you to the line. The code outline (Code Contents) shows the structure of the unit, and
**Go to declaration** takes you to where an identifier is declared.

The editor suggests names of tables, columns, packages and their members, folds blocks, highlights `BEGIN`/`END` pairs,
formats code (**Formatter**) according to your settings and keeps a local version history of the file. Templates insert
ready-made code snippets.

## Code analysis

As you type, Pelikan underlines unknown tables, columns and aliases and points out problems: unused variables, code
after `RETURN`, `UPDATE`/`DELETE` without `WHERE`, implicit conversions. **Find Usages** searches for uses of an object
in the database and in project files, and **Rename** shows a preview of the changes before applying them.

## Files and encoding

Files keep their encoding (UTF-8, ISO-8859-2, Windows-1250) and line endings. A character that cannot be stored in the
file's encoding blocks saving and shows exactly where it is — the encoding can only be changed explicitly
(**File › File encoding**).

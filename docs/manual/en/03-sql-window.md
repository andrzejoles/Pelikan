# SQL Window and result grid

The SQL Window is used to execute queries and scripts. The result of each query appears on a separate tab below the
editor, and database messages and DBMS_OUTPUT output on the **Output** tab. You open a new window with **File › New ›
SQL Window** (⌘N); the window works on the main connection or on the connection selected in the status bar.

## Executing statements

| Action | Shortcut | Menu |
|---|---|---|
| Execute the selection or the statement under the cursor | F8, ⌘↩ | Session › Execute |
| Execute opposite to AutoSelect (e.g. the whole script) | ⌃F8, ⇧⌘↩ | Session › Execute (opposite of AutoSelect) |
| Break execution or fetching | ⇧⎋, ⌘. | Session › Break |
| Commit the transaction | F10, ⌥⌘↩ | Session › Commit (COMMIT) |
| Roll back the transaction | ⇧F10, ⌥⌘⌫ | Session › Rollback (ROLLBACK) |
| Previous / next statement of the window | ⌥⌘↑, ⌥⌘↓ | Session › Window history |

**AutoSelect** is enabled by default: without a selection, F8 executes only the statement the cursor is in, so you will
not run the whole script by accident. Selected text is executed as a whole. Statements are split as in SQL*Plus: a
semicolon ends an SQL statement, and a PL/SQL block or a `CREATE` with a body is ended by a slash `/` on a separate
line. Each query of a script gets its own result tab.

Note: on macOS the ⌃F8 shortcut is taken by the system by default (moving focus to the status menus) — use ⇧⌘↩ or turn
off the system shortcut in **System Settings › Keyboard › Keyboard Shortcuts**.

During execution the window is locked for editing, and the status bar shows “Executing…”. When it finishes, the number
of rows and the time are shown; a time longer than 100 seconds is formatted as hh:mm:ss. After a long query Pelikan can
play a sound and bounce its icon in the Dock. When **Break** does not work (some database operations do not respond to
interruption), use **Session › Terminate window session (Kill)**.

Pelikan never commits changes automatically (the **AutoCommit SQL statements** option in **Preferences › SQL Window** is
off by default). An open transaction is indicated in the status bar (“● transaction open”).

## Variables

- **Substitution variables** `&name` and `&&name` — before execution Pelikan shows the **Variables** window with fields
  for the values. In the SQL Window `&&` in text means an ordinary `&` character (e.g. `'R&&D'`); in the Command Window
  `&&` works as in SQL*Plus (the variable is remembered).
- **Bind variables** `:name` — also go to the variables window (`:new` and `:old` in triggers are skipped).
- **JasperReports report parameters** `$P{…}`, `$P!{…}` and `$X{IN, column, parameter}` — Pelikan recognizes them and
  asks for values, so you can execute a query from a report without rewriting it.
- The extended syntax `&<name="…" type="…" list="…" default="…" required="…">` lets you describe a variable: its type, a
  list of values (also from a query that depends on other variables), a default value, whether it is required, and other
  options.

Variable values are remembered in the window. The **&** button on the bar below the editor (**Session › Variable
substitution**) turns substitution off when the text contains `&` and `:` characters with another meaning.

## Directives in comments

A comment directly before a statement can control its result:

| Directive | Effect |
|---|---|
| `-- Tab=Employees` | title of the result tab; `&Count` inserts the number of rows |
| `-- Records=all` | how many rows to fetch at once: a number, `page` or `all` |
| `-- Totals=sum:SAL;count:EMPNO` | totals and other functions below the grid |
| `-- AltRowColor=…` | color of alternating rows |
| `-- Excel=report_%date%.xlsx` | save the whole result to an Excel file |
| `-- CSV=%dbuser%_%time%.csv` | save the whole result to a CSV file |

In file names you can use `%dbuser%`, `%dbname%`, `%date%`, `%time%` and `%&variable%`. A relative path is resolved from
the directory of the window's file.

## Result grid

![Editing a result: a new row and the pending changes counter](../img/siatka-edycja.png)

The grid fetches rows in batches (you set the number in **Preferences › SQL Window › Rows per page**) and fetches more
while you scroll. The “(more…)” label next to the row count means that the result is not complete. **Next page** (⌘⇟)
and **Last page (fetch all)** (⇧⌘⇟) are in the **Session › Result** menu and on the bar above the grid. For very large
results Pelikan asks before the size limit from Preferences is exceeded.

- **Sorting** — click a column header (ascending, descending, unsorted) on the fetched rows.
- **Selecting** — rows, columns and blocks of cells (click, then ⇧+click).
- **NULL** has a colored background; numbers are shown with full Oracle precision.
- **CLOB, BLOB, XML, long texts** — the button in the cell or **Edit › Result › Large Data Editor…** (⌥⌘L) opens the
  large data editor with text, XML, JSON, HTML, image, PDF and hex views, JSON/XML formatting and saving to a file.
- The **Value panel** (**View › Value panel**, ⌥⌘V) shows the current cell next to the grid as text, JSON, XML, HTML, an
  image or hex.
- **Single record view** shows the current row vertically with the column types and comments.
- A **nested cursor** (`CURSOR(…)` in a query) opens in a new result tab.
- **Column Filter…** hides columns by name, type, nullability and keys; hidden columns are skipped when copying and
  exporting.
- **Filter by cell value**, **Filter by expression…** (`=`, `<>`, `<`, `>`, `LIKE`, `IS NULL`, `AND`, `OR`) and **Group
  by column** (with counts; a double-click filters) work locally, on the fetched rows.
- **Column Totals…** calculate the sum, count, average, minimum and maximum below the grid and remember them after
  re-execution.
- **Compare records** puts the selected rows side by side column by column, and **Compare results** — two result tabs.
- **Linked queries…** open the parent and child tables of the current row (from foreign keys) in a new window.
- **Refresh Result** (⇧⌘R) re-executes the tab's statement, and **Auto Refresh…** does it every given number of seconds.
- **Pin Result** keeps the tab at the next execution (also ⇧+click on the tab).
- You change the grid font size in **View › Grid**.

Most of these actions are in the grid's context menu and in **Edit › Result** or **Session › Result**.

## Editing data in the grid

To edit a result, the query must return the `ROWID` column, e.g.:

```
select t.*, t.rowid from dept t
```

The simplest way is **Edit data** from the table's menu in the Object Browser — Pelikan prepares such a query by itself.

1. Click the padlock above the grid or choose **Session › Result › Edit data** (⌥⌘E).
2. Change cells, add rows (**Insert record**, ⌥⌘I) and delete them (**Delete record**, ⇧⌘⌫). Pending changes are marked
   in the row header (+, ~, −) and with color; the counter above the grid shows their number. Columns with an alias and
   expressions are read-only. For DATE columns a **Calendar…** is available, and for columns with a `CHECK … IN`
   constraint or a foreign key to a small table — a **Value List…**.
3. **Copy change SQL** shows the statements that will be executed.
4. **Apply changes (Post)** (⌥⌘S) sends the changes to the database — without COMMIT. After an error, the cursor moves
   to the cell concerned. **Discard changes** throws away all pending changes.
5. Commit the transaction (F10, ⌥⌘↩) or roll it back.

On a production connection saving requires confirmation, and on a read-only connection it is blocked.

## Copying and exporting

- **Edit › Result › Copy with header** (⇧⌘C), **Copy header**, **Copy as expression list** (for `IN (…)`), **Copy to
  Excel**, and in the grid's context menu also **Copy as** (a chosen format).
- **File › Export result…** saves the selection or the whole fetched result as CSV, TSV, HTML, XML, SQL (INSERT), an
  expression list or Excel (xlsx).
- **Session › Result › Export Query to File…** executes the statement under the cursor and saves the result directly to
  a file, without displaying it — convenient for large results.
- **File › Export result › Column to files…** saves a column's value (e.g. a BLOB) to a separate file for each row.
- **Generate SQL from rows…** creates INSERT, UPDATE, DELETE or MERGE statements for the selected rows in a new SQL
  Window, without executing them.
- **File › Print…** (⌘P) prints the window's code with syntax colors and the grid (the selected or all fetched rows).

## Charts

**Session › Result › Chart…** opens a chart window from the current result tab. Choose the type (bar, line, area,
scatter or pie), the category column (X axis), the series (Y axis) and an optional aggregation; set colors, the legend
and values next to the points. You can save a chart template, and export the chart to PNG, PDF or the clipboard.
**Refresh** re-executes the SQL Window's query.

![Chart window from a query result](../img/wykres.png)

## Query By Example

**Session › Result › Query By Example…** (⇧⌘E) lets you narrow down a result without writing WHERE: enter criteria under
the column names — a value, a pattern with `%`, an operator (`>`, `<>`…), `in (…)`, `between … and …` or `null` — and
Pelikan executes the query again with the conditions. Text comparison is case-insensitive, and dates are compared
without time. **Clear Query By Example** restores the original query.

## Statistics and plan

When enabled in **Preferences › SQL Window › Statistics**, the **Statistics** tab shows the change in session statistics
(V$MYSTAT) for each execution. **Tools › Explain Plan** (F5) shows the plan of the statement under the cursor, and
**Tools › Autotrace** executes it and shows the actual plan — see the *Execution plan, sessions and administration*
chapter.

## Files and history

- **File › Save** (⌘S) saves the window to a `.sql` file; files keep their encoding and line endings.
- **Edit › Command history…** (⇧⌘H, in the PL/SQL Developer profile ⌃E) shows all executed statements from all windows
  (without statements containing passwords) with a filter; you insert the chosen ones into the editor.
- **File › Paste as New SQL Window** creates a window with the clipboard contents.
- The local history of a file (**File › Local history**) is described in the *Tools* chapter.

# Tools

This chapter describes the tools from the **Tools**, **Reports**, **Project** and **File** menus: comparing and
deploying changes, export and import, reports, notebooks, projects and files. The performance and administration tools
are described in the *Execution plan, sessions and administration* chapter.

## Comparing schemas and deploying changes

### Comparing user objects

**Tools › Compare user objects…** compares the DDL of a schema's objects with a target schema — on the same or another
connection (e.g. `dev_test` with the acceptance test database).

![Comparing user objects](../img/porownanie-obiektow.png)

1. Enter the source schema and click **Load**. Select the objects (type and name filter, **Select visible**).
2. Choose the **Target connection** and optionally the **Target schema**. Set the options: **Ignore case**, **Ignore
   spacing**, **Storage** (compare storage parameters), **Drop redundant** (the script drops objects that are not in the
   source).
3. Click **Compare**. The list shows objects only in the source, different, and only in the target, in dependency order.
4. **Show differences** opens the diff viewer, and **Copy SQL** and **Open SQL** give a script that aligns the target
   with the source. The script is not executed automatically — review it and execute it deliberately.

### Database Diff and the deployment cart

**Tools › Database Diff…** compares schemas by object type (also between connections); for tables it generates `ALTER
TABLE` statements that add, modify and drop columns. You add selected differences with the **To cart** button.

**Tools › Deployment cart…** collects objects (DDL) and table data (with a WHERE filter) into a change package. You add
the object selected in the Object Browser with **Tools › Cart › Add object to cart**, and **Cart › Cart deployment
script** generates a script in dependency order in a new SQL Window — with `WHENEVER SQLERROR EXIT` and `COMMIT` at the
end.

![Deployment script generated from the cart](../img/koszyk.png)

### Comparing table data

**Tools › Compare table data…** compares data by primary key (new, different and redundant rows) with a table in another
schema or connection. The result is a script or a direct update of the target with `COMMIT` every n rows.

### Diff viewer

All text comparisons (a window with a file, an object with the database, local history, **Tools › Compare files…**) use
the built-in diff viewer: two columns, a change map, jumping to the next and previous difference, differences within a
line, ignoring case, spacing and comments, swapping sides and **Reload**. Instead of it you can use your own program —
**Preferences › Tools › External diff viewer** (arguments `%1`, `%2` — files, `%3`, `%4` — titles).

## Export and import

| Tool | What for |
|---|---|
| Tools › Export user objects… | DDL of the selected objects to one file (a script with “/”) or a file per object — the specification and body of packages and types in separate `.pks`/`.pkb` and `.tps`/`.tpb` files (extensions from Preferences) without “/” unless you turn on **End units with /**; **Specification and body in one file** gives `.pck`/`.typ` with “/”; object files contain only CREATE — privileges go to a separate `name.grants.sql` file or are skipped (**Privileges in files per object**), a disabled trigger gets `DISABLE` in `CREATE TRIGGER`, a comment with the date only with **Header with the export date**; with storage, in executable order |
| Tools › Export tables… | table data as an INSERT script (with DROP/CREATE, TRUNCATE/DELETE, disabling triggers and foreign keys, COMMIT every n, a WHERE condition), in Pelikan's own (compressed) format or through Data Pump |
| Tools › Import tables… | import of an INSERT script or the own format with a choice of tables; Data Pump import with REMAP_SCHEMA |
| Tools › Text Importer… | CSV and text files: detection of the separator, header and encoding, mapping fields to columns, transformation functions, a filter, handling of duplicates, CREATE TABLE from a file |
| Tools › Import from Excel… | .xlsx files (without Excel and ODBC): sheet, header line, range, mapping |
| Tools › Data import wizard… | a step-by-step wizard for CSV, fixed-width files and XLSX, into a new or existing table, with a saved profile |
| Tools › Copy schema… | objects and data to another schema or connection (tables, data, objects, foreign keys, triggers) |
| Tools › Data transfer… | a table or query into a table on the same or another connection, with column mapping and append / TRUNCATE / DELETE mode; definitions can be saved and run in the background |
| Tools › Data Generator… | test data from patterns, lists, queries and data sets (first names, companies, addresses, e-mails), with a master/detail relation |
| Tools › Schema documentation… | HTML documentation: tables with columns and comments, keys, indexes, views, programs with parameters |

A Data Pump export writes files on the server side (the `DATA_PUMP_DIR` directory), not on the Mac. Tools that write to
the database go through the same safeguards as the SQL Window: on a production connection they ask for confirmation, on
a read-only connection they are blocked. No saved definition (of a transfer, job or import) contains passwords.

## Reports

### Predefined reports

**Reports › Predefined reports…** opens a set of ready-made reports about the database in the categories *About
database*, *Objects*, *Tables*, *PL/SQL*, *Security* and others. A report can show a grid, a chart or DBMS_OUTPUT
output, ask for variables and have row details. **Open report in SQL Window** lets you modify the query, and you can
export the result to CSV, HTML or XLSX.

![Predefined reports](../img/raporty-predefiniowane.png)

The **Reports** menu also has quick reports: **Compilation errors**, **Invalid objects**, **Recently changed objects**,
**Table sizes**, **Table columns**, **User privileges** and **Sessions**.

### Your own reports

1. Open **File › New › Report Window** and enter a query. Variables (`&<name="…">`, `:name`, JasperReports parameters)
   work as in the SQL Window.
2. Execute the report (F8). The result is an HTML document.
3. On the **Layout** tab set, for the columns, the title, alignment, number format (e.g. `#,##0.00`) and date format
   (e.g. `yyyy-MM-dd`), hiding, **Group** (grouping with a group header, master/detail) and **Sum** (group totals and a
   grand total).
4. Choose a **Style** from the library (*Standard*, *Green*, *Compact*) and optionally **Additional CSS**; in the
   **Options** — a header with variables (`#title`, `#date`, `#user`, `#connection`, `#variable`), the report
   connection, a form layout instead of a table, a new page after each group and a background.
5. Save the report as a `.rep` file. **Report › Add report to the Reports menu** puts it in **Reports › My reports**.

![Report with groups and totals in the Green style](../img/raport-styl.png)

**Report › Save report as HTML…**, **Export report data…** (CSV, TSV, XML, Excel) and **Print report…** (also to PDF)
share the result. **Lock report definition** hides the query and layout — the report can then only be executed (until it
is unlocked).

## SQL notebook

A notebook (**File › New › SQL notebook**) combines SQL/PL/SQL cells with Markdown cells — well suited to analyses and
step-by-step instructions.

![Notebook with a Markdown cell, a query and a chart](../img/notatnik.png)

- **Add cell** inserts an SQL or Markdown cell; the arrows move cells, the trash can deletes them.
- ▶ executes a cell, **Execute all** — all of them in order (stops at an error).
- The chart button creates a chart from the cell's result (Pelikan suggests the category and series).
- Results and charts are saved in the `.sqlnb` file, so after opening you see them without executing again.
- **Export Markdown…** (**File › Notebook › Export notebook as Markdown…**) saves the notebook with its results as a
  Markdown document.

## Query Builder

**Tools › Query Builder…** builds a query visually: drag tables (also synonyms and subqueries), Pelikan adds joins from
foreign keys (you can change the join type), select columns, set aliases, WHERE and HAVING conditions, GROUP BY, ORDER
BY and DISTINCT. The query goes to the editor. You can open a selected simple SELECT in the Query Builder to modify it.

## Multi-case tests and load tests

- **Tools › Test Manager** — test sets (`.pts`): blocks with input and expected values (`=`, `LIKE`, `IN`, `NULL`, `NOT
  NULL`), global variables, DBMS_OUTPUT and a time limit. Changes made by the tests are rolled back. You open a failed
  test in a Test Window for debugging.
- **Tools › Load test…** executes SQL/PL/SQL steps in many sessions in parallel (variables `:thread` and `:iteration`),
  with live results (times, errors, throughput) and saving to Excel.
- **Tools › Event Monitor…** receives DBMS_ALERT alerts and DBMS_PIPE messages in a separate session.

## Searching

- **Edit › Search in Editors and Files…** (⌥⇧⌘F) searches the current editor, all open windows or script files in
  directories (by default in the file browser locations), with case sensitivity, whole words and regular expressions.
  Clicking a result opens the file at the line of the match.
- **Tools › Find database objects…** (⇧⌘O) searches code in the database — see the *Object Browser* chapter.
- **Project › Search in project…** searches the project's files, object sources and notes.

## Local history

Pelikan saves a version of a file or object at every save, compilation, refactoring and restore — independently of Git
and without a database connection. **File › Local history › Local history** shows the versions of the active window;
**Compare with current** opens the differences, and **Restore** inserts the old version (the current text stays in the
history). **Save version in history** adds a version manually, with a description. The history keeps up to 50 versions
from the last 30 days.

![Local history of a file](../img/historia-lokalna.png)

## Projects, worksets and files

- A **project** groups files and database objects (with notes and groups) in a `.prj` file. **Project › Build project**
  compiles everything in the order of the items, and **Project make** — only files changed since the last build and
  invalid objects. Project options include the connection, stopping after the first error, and formatting. **Save
  project desktop** remembers the open windows.
- A **workset** remembers the open windows — also with unsaved changes and variable values — and restores them at the
  next launch (**File › Workset**: new, open, save, restore, close, compare, autosave). You save the main window layout
  with **View › Save window layout**.
- When you quit with **workset autosave** on (the default; **Preferences › General › Files › Restore windows after
  relaunch** or **File › Workset › Autosave workset**) Pelikan does not ask about saving — all open windows (SQL,
  program, test, command, plan, diagram, notebook, report and connection consoles) come back on the next launch in the
  same order and with the same active window. A window without a file comes back with its text as a window without a
  file, marked as unsaved.
- The **File Browser** (the **Files** tab) shows selected directories (locations with a filter and a color) with a menu:
  open as, rename, new file or directory, move to Trash, show in Finder. The filter works on name, state, Git state,
  size and date.
- **Git**: the branch and the file's state are in the status bar, in the file browser and in the project. **Tools ›
  Git** has the file state, comparison with HEAD, `git add`, `git commit` and the file history.

## Other

- **Tools › User tools…** — your own tools: external programs with variables (`#file`, `#object`, `#selection`,
  `#connection`…) or SQL blocks for sessions. Programs are run without a shell, and the variables never contain
  passwords.
- **Tools › Local jobs…** — scripts, exports and data transfers run periodically (every n minutes, daily, on selected
  days) while Pelikan is running. Definitions do not contain passwords; the log shows the result of each run.
- **View › Background tasks** — a list of long operations (Autotrace, exports, documentation) with state, time and
  cancellation.
- **Tools › Documents…** — your documents and http(s) addresses from the list in **Preferences › Tools**.
- macOS services (the **Services** menu in any application): **Pelikan: Format SQL** formats the selected text in
  place, and **Pelikan: Open in SQL Window** moves the selected text to a new Pelikan SQL Window.

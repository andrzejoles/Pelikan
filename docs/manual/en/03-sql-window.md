# SQL Window

The SQL Window is used to execute queries and scripts. Query results appear in the grid below the editor, messages on
the *Output* tab, and DBMS_OUTPUT output on a separate tab.

## Execution

- **F8 / ⌘↩** — executes the selection or the statement under the cursor (depending on the *AutoSelect* setting).
- **⌃F8 / ⇧⌘↩** — executes the opposite of *AutoSelect* (e.g. all statements in the window instead of the one under
  the cursor).
- **Break** (⌘.) — interrupts a long-running query.
- Pelikan detects substitution variables `&` and `&&` and bind variables `:nazwa` by itself and asks for their values. It
  also recognizes JasperReports report parameters `$P{…}`, `$P!{…}` and `$X{…}`.

## Result grid

The grid fetches rows in batches and loads more as you scroll. Clicking a header sorts, and the filter works locally on
the fetched rows. Cells can be edited when the query fetches `ROWID` or comes from a single table with a key — you apply
the changes with a button and confirm them by committing the transaction. Large values (CLOB, BLOB, XML, JSON) open in
the **Large Data Editor**.

You can export the result to CSV, TSV, HTML, XML, XLSX, INSERT statements or the clipboard. The **Value panel** (⌥⌘V)
shows the current cell as text, JSON, XML, HTML, an image or hex.

## Transactions

The status bar shows an open transaction. **Commit** (F10, ⌥⌘↩) and **Rollback** are in the Session menu and on the
toolbar. In *Multi session* mode each window has its own session; in *Dual session* mode the windows share one session.

## Explain Plan and Autotrace

**Explain Plan** (F5) shows the execution plan of the statement under the cursor as a tree with cost, row count and
predicates. Plans can be compared, and **Autotrace** executes the statement and shows the actual plan with statistics.

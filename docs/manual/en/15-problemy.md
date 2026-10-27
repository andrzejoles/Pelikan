# Troubleshooting and limitations

## Most common problems

### macOS does not let Pelikan start

Pelikan is not notarized by Apple. On first launch open **System Settings › Privacy & Security** and click **Open
Anyway** (see the *Introduction* chapter).

### “Oracle Instant Client missing”

- Download Instant Client for macOS in the **ARM64** version (Basic or Basic Light) and unpack or install it according
  to Oracle's instructions.
- Select the directory containing the `libclntsh.dylib` file in **Preferences › Oracle › Oracle Instant Client** and
  restart Pelikan.
- If the client is in the Downloads folder and macOS asked about Pelikan's access to that folder and you refused, change
  it in **System Settings › Privacy & Security › Files and Folders** or move the client somewhere else.
- Temporarily you can switch the connection to the *Thin* driver (the **General** tab of the connection definition).

### I cannot connect

- Click **Test** in the connection definition — the message from the database or the Oracle client points to the cause.
- **ORA-12154 / TNS:** the alias was not found — check the configuration directory (the **Advanced** tab or
  **Preferences › Oracle › Oracle Net and Oracle Wallet**) or use a `host:port/service` address.
- **ORA-01017:** wrong password — Pelikan asks for it again; check remembering to replace the password in the Keychain.
- **ORA-28001:** the password has expired — Pelikan shows the password change window.
- **Oracle Wallet:** the **Database** field must be exactly the alias stored in the wallet, and the wallet must have the
  `cwallet.sso` file (auto-login). The wallet status is shown in **Preferences › Oracle**. Changes in this section take
  effect after a restart.
- **SSH tunnel:** Pelikan uses the system `ssh` — check in Terminal whether `ssh user@bastion.example.com` works (key in
  the SSH agent, known host). Enter the database address as the SSH server sees it.
- **Touch ID:** if you have enabled confirmation of saved passwords and you cancel the system dialog, the connection is
  not established.

### A keyboard shortcut does not work

- F keys: enable using them as standard function keys in System Settings, or press them together with the fn key.
- ⌃F8, ⌃F2, ⌃F3 and other ⌃ shortcuts may be taken by macOS (**System Settings › Keyboard › Keyboard Shortcuts**). Use
  the ⌘ equivalent (e.g. ⇧⌘↩ instead of ⌃F8) or turn off the system shortcut.
- ⌃Space switches the input source in macOS by default — invoke code completion with ⌥⎋.
- Check the command's shortcut in the command palette (⇧⌘P) or in **Preferences › Keyboard**.

### A query takes too long

**Break** (⌘.) interrupts execution and fetching. If the database does not respond (e.g. during `DBMS_SESSION.SLEEP` or
on the Thin driver, which does not support interruption), use **Session › Terminate window session (Kill)** — it
requires the ALTER SYSTEM privilege.

### I cannot edit a result in the grid

The query must return the `ROWID` column (e.g. `select t.*, t.rowid from table_name t`). The simplest way is **Edit
data** from the table's menu in the Object Browser. A read-only connection blocks saving.

### The debugger does not stop

- Check the `DEBUG CONNECT SESSION` and `DEBUG ANY PROCEDURE` privileges (or `DEBUG` on the object) — **Debug ›
  Debugger Privileges…** prepares the statements for the administrator.
- Compile the object with debug information (**Tools › Object › Add debug information**).
- A breakpoint with an empty mark was not accepted by the database (e.g. a line without executable code).

### AWR report / SQL Monitor does not work

Check the license declaration in the connection definition (the **Advanced** tab) and the database parameter
`CONTROL_MANAGEMENT_PACK_ACCESS`. Tuning Pack features require the value `DIAGNOSTIC+TUNING`.

### The agent does not start

- Pelikan looks for the agent program in the `PATH` of your login shell — check in Terminal whether the command (e.g.
  `claude`) works.
- The agent does not see the connection: check the **AI agent** tab in the connection definition.
- The agent cannot change anything: the connection is read-only, production without consent to changes, or you lowered
  the tool's level in the session permission matrix.

### Pelikan quit unexpectedly

At the next launch Pelikan offers to recover unsaved windows (also later: **File › Recover Windows…**), if keeping
unsaved windows is enabled in **Preferences › Tools**. You will also find file changes in the local history (**File ›
Local history**).

### Application log

Pelikan keeps an event log: startup, connections and their errors (ORA- code), completed statements (kind, time,
row count), background tasks, the debugger, tests, SSH tunnels, AI agents and updates. **Help › Application Log**
opens it in macOS Console; the file is in `~/Library/Logs/Pelikan`, and the same entries go to the system log
(Pelikan's subsystem in Console). Files are at most 2 MB, and Pelikan keeps the last five.

The log never contains passwords, SQL statement text or database data. Connection, server and object names and file
paths are hidden or replaced by a hash by default (the same name always has the same hash). In **Preferences ›
General › Application Log** you choose how much is logged (*Warnings and errors*, *Events*, *Details — diagnostics*)
and can show names — useful when tracking down a problem on your own computer.

## Known limitations

The following features work differently than in the reference product, are incomplete, or have not been verified in a
real environment:

- The **Thin driver** does not support TCPS and wallets, external authentication, changing an expired password, or
  interrupting execution.
- **Kerberos** on macOS: when `sqlnet.ora` enables KERBEROS5, the connection ends with a clear error (the Instant
  Client adapter conflicts with the system Kerberos inside the app); on Linux, logging in with a ticket works.
  **Microsoft Entra ID** and **TCPS connections** are implemented according to the Oracle documentation but have not
  been checked against Azure or a TCPS listener. **LDAP** (directory naming): Pelikan resolves the alias itself over
  anonymous LDAPv3 — no LDAPS and no wallet bind.
- **Debugger**: no debugging through DBMS_DEBUG_JDWP; in triggers the `:new` and `:old` values are not available; there
  can be only one breakpoint per line.
- The **grid** cannot freeze columns or rows.
- **Command Window**: the `COPY` and `SET ENVVAR` commands are not supported.
- The **Event Monitor** does not read the DBMS_OUTPUT of other sessions (Oracle does not provide it).
- **Tools in the left column** are tabs of one panel (Connections, Objects, Windows, Templates, Files); they cannot be
  docked freely or hidden automatically. Documents are tabs of one main window, not native macOS tabs.
- **Quick Look** for SQL files (preview in the Finder) may not work — macOS may reject an extension signed with a
  self-signed certificate.
- The **Pro*C remote build** has been tested on a local SSH server with the ksh93 shell; the parsers for `proc` and
  `xlc` messages were written from the documentation. Operation on AIX 6.1 (ksh88) awaits confirmation on a real server.
- **Left out** in this version: the ODBC importer (replaced by the text and Excel importers and the import wizard),
  APEXlang, Liquibase (`lb` from SQLcl).
- **VoiceOver**: interface elements have accessibility labels, but the application has not yet been checked with
  VoiceOver.

## Reporting bugs

Report bugs and suggestions on the project page:
[github.com/andrzejoles/Pelikan/issues](https://github.com/andrzejoles/Pelikan/issues). Do not include passwords, server
names or data from production databases — a description of the steps and the error message are enough.

The easiest way is to report from the app: **Help › Report a problem…** (also on the ribbon: **View › Help**), the
**Report a problem…** button in an error message, or the question after Pelikan quit unexpectedly (with a crash
description from the macOS report: exception and stack — no paths). In the report window enter a title and a
description, choose whether to include the environment and recent log entries, and check the preview. **Open issue on
GitHub** opens the new issue page with the text filled in (a copy is in the clipboard) — you submit it from your own
GitHub account; Pelikan never sends anything by itself. Issues are public: the text passes through the password and
home-path filter, and the log hides names by default.

Attach the log to your report: **Help › Export Log…** saves it together with an environment summary (version,
system, drivers) to a text file. Review the file before sending it, especially if names were shown.

## Glossary

The Polish names of windows and terms in Pelikan and their PL/SQL Developer equivalents (e.g. *Okno SQL* — SQL Window,
*Przeglądarka obiektów* — Object Browser, *Zatwierdź zmiany (Post)* — Post changes) are in the glossary:
[docs/GLOSSARY.md](https://github.com/andrzejoles/Pelikan/blob/main/docs/GLOSSARY.md).

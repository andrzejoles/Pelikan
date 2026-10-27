# Connections

A connection is a saved definition: where to connect, as whom and with which security rules. Definitions are saved
without passwords — passwords go only to the macOS Keychain.

## Connection list

The **Connections** tab in the left column shows the definitions in folders, and the **Recent** folder shows recently
used ones. The connection's open windows are listed under it.

- Double-clicking a connection connects it as the **main connection** (bold in the list). New windows open on the main
  connection.
- The connection's context menu: **Connect as main**, **Connect** (without changing the main connection),
  **Disconnect**, **New window** (SQL, program, test or command window on this connection), **Show Connection Windows**,
  **Close Connection Windows**, **Reconnect Connection Windows**, **Set Current Schema…**, **Edit…** and **Delete…**.
- The buttons above the list create a new connection (**+**) and a folder, and refresh the list.

You can also use the logon window: **Session › Log on…** (⇧⌘L). It shows all definitions with a search field and lets
you create a new connection or edit an existing one. **Session › Log off main connection** ends the sessions of the main
connection.

## New connection

Choose **Session › Connections › New connection…** or click **+** in the connection list. The definition window has four
tabs.

### General tab

- **Name** — the name in the list (empty means `user@database`). For local test databases, names with a prefix work
  well, e.g. `dev_test`.
- **Folder** and **Environment**: *Development*, *Test*, *Production* or *Other*. The environment determines the
  indicator color (test — orange, production — red), confirmation of changes and what the AI agent is allowed to do.
  **Custom indicator color** replaces the environment color.
- **User**, **Password** and **Remember password in Keychain**. Without remembering, Pelikan asks for the password on
  the first connection and keeps it only in memory until the application quits. When a saved password stops matching
  (ORA-01017), Pelikan asks for it again.
- **Database** — an EZConnect address `host:port/service` (e.g. `db.example.com:1521/FREEPDB1`), an alias from
  `tnsnames.ora` (the **TNS** button next to the field suggests aliases from the configuration), a full descriptor or a
  `tcps://…` address for encrypted connections.
- **Connect as**: Normal, SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM or SYSASM.
- **Authentication**: *Password*, *Oracle Wallet (password store)*, *External (Kerberos, OS)*, *Microsoft Entra ID
  (browser)* or *OAuth2 token from file* (described below).
- **Driver**: *Instant Client (recommended)* or *Thin (without Instant Client)*. Thin does not support TCPS and wallets,
  external authentication, changing an expired password, or interrupting execution.

Click **Test** to check the connection, then **Save**.

### Advanced tab

- **Proxy: target schema** — logging on as a proxy user into another schema (`user[schema]`).
- **Configuration directory (tnsnames.ora)** — this connection's own TNS directory.
- **TLS wallet (mTLS, e.g. Autonomous Database)** — a directory with `cwallet.sso`. The **Import ZIP…** button unpacks a
  wallet archive downloaded from the cloud console next to the ZIP file and also sets the configuration directory right
  away.
- **Edition (EBR)** and **Workspace (DBMS_WM)** — the edition and workspace set after logon.
- **Diagnostics/Tuning Pack license** — see *Oracle pack licenses* below.
- **Current schema** — `ALTER SESSION SET CURRENT_SCHEMA` in every session.
- **Read-only (blocks data and object changes)** — see below.
- **Connect on application startup**.
- **Session initialization script** — statements executed in every new session of this connection (separated by `;`,
  PL/SQL blocks terminated with `/`).
- **Login message** — text shown after connecting, e.g. a reminder that this is a shared database.

### SSH tunnel tab

When the database is reachable only through an intermediate server, check **Connect through SSH tunnel** and enter:

- **SSH server (bastion)**, e.g. `bastion.example.com`, **Port** and **SSH user**;
- **Private key file** — an empty field means the SSH agent and the settings from `~/.ssh/config`;
- optionally a **Jump host (ProxyJump)**;
- or **SSH password login (instead of a key)** and **SSH password**.

The tunnel uses the system `ssh`, so your `~/.ssh/config` configuration, the SSH agent (keys added with `ssh-add
--apple-use-keychain`) and the known hosts file all work. Enter the database host and port in the **Database** field as
the SSH server sees them (e.g. `db.internal.example.com:1521/SERVICE`). The SSH password is stored only in the Keychain
and is passed to `ssh` through a one-time pipe — never through command arguments, environment variables or files. One
tunnel serves all sessions of the connection and closes together with the last of them.

### AI agent tab

Settings for AI agents' access to the connection: whether the agent sees it at all, whether it may change data and
objects (with your consent), a separate database user for the agent, and masked columns. They are described in the *AI
agents* chapter.

## Environments and protection against mistakes

- The connection color is visible in the connection list, on the window tab, in the window list and in the status bar.
  The **Editor background in connection color** option (**Preferences › General**) also tints the editor background. On
  the same tab you can add color rules by a `user@database` pattern (e.g. `sys@*`) — they take precedence over the
  environment color.
- On a **production** connection, statements that change data or objects (DML, DDL, PL/SQL blocks) require confirmation
  in the “Changes on production connection” window.
- A **read-only** connection rejects everything except queries and session control before it is sent to the database —
  including `SELECT … FOR UPDATE` and PL/SQL blocks. The window's status bar then shows “read-only”.
- Pelikan never commits a transaction by itself. When you close a window or the application with an open transaction, it
  asks whether to commit (COMMIT) or roll back (ROLLBACK); you change the behavior on logoff in **Preferences › General
  › Logoff with an open transaction**.

## Passwords and Touch ID

Database passwords and SSH passwords are stored only in the macOS login Keychain (without iCloud synchronization). They
never go to files, logs, command history or process arguments.

In **Preferences › Oracle › Connection passwords** you can enable **Require Touch ID or Mac password before using a
saved password**. Pelikan then asks for confirmation once per connection while the application is running — also when
the connection is used by an AI agent.

When the database password has expired (ORA-28001), Pelikan shows a password change window: enter the new password
twice. If remembering is enabled, the new password replaces the old one in the Keychain as soon as the connection
succeeds.

You can also change the password at any time: **Session › Change password…** (the connection must be open). Pelikan
changes it through the OCI interface — the password never appears in SQL text or in the command history — and saves
the new one in the Keychain if the connection remembers its password.

## Oracle Wallet

Pelikan supports two kinds of wallet:

- **Password store** (Secure External Password Store) — logging on without a password in Pelikan (`/@alias`). You set
  the wallet directory and the Oracle Net configuration directory in **Preferences › Oracle › Oracle Net and Oracle
  Wallet**; Pelikan shows the wallet status there (an auto-login wallet `cwallet.sso` is required). In the connection
  definition choose the *Oracle Wallet (password store)* authentication. The **Database** field must be exactly the
  alias or connect string stored in the wallet. Changes in this Preferences section take effect after Pelikan is
  restarted.
- **TLS wallet** (mTLS, e.g. Autonomous Database) — set on the **Advanced** tab of the connection definition.

Passwords from the wallet never reach Pelikan.

## Other authentication methods

- **External (Kerberos, OS)** — logging on with operating system or Kerberos credentials.
- **Microsoft Entra ID (browser)** — for Oracle databases on Azure. You enter the tenant ID, the client application ID
  and the database application URI; Instant Client 23 opens a browser for logon and passes the token to the database
  itself. Pelikan neither sees nor stores the token. Requires a TCPS connection.
- **OAuth2 token from file** — a token prepared beforehand with an external tool (e.g. Azure CLI); you specify the token
  file or directory.

## Windows, sessions and the window connection

Each window has its own connection, visible in the status bar. Click it to switch the window to another connection; when
the window has an open transaction, Pelikan first asks about COMMIT or ROLLBACK. A window with a **pinned** connection
(📌) does not change it when you change the main connection; you enable pinning of new windows by default in
**Preferences › General**.

Session mode (**Preferences › General › Session mode**):

- **Multi** (default) — each window has its own database session, so a long query in one window does not block others,
  and the windows' transactions are independent;
- **Dual** — windows share one session, and compilation has a separate one;
- **Single** — everything in one session.

Every 60 seconds Pelikan checks whether the connection is alive (you change the interval in Preferences) and reacts when
it is lost. Optionally it closes the sessions of windows idle for longer than a set time, if they have no open
transaction (**Preferences › Oracle**).

When a query cannot be interrupted (**Break**, ⌘.), use **Session › Terminate window session (Kill)** — Pelikan ends the
window's session in the database from a separate session (requires the ALTER SYSTEM privilege) and reconnects the
window.

**Session › Connection console** opens a SQL Window assigned to the connection (one per connection). Its content is
saved automatically and comes back when reopened, also after Pelikan is restarted — a good place for handy queries.

## Exporting and importing definitions

**Session › Connections › Export Connection Definitions…** saves the definitions with their folders to a JSON file
without passwords. **Import Connection Definitions…** loads them on another Mac; you enter the passwords on the first
connection.

**Session › Connections › Export Connections with Passwords…** saves the definitions together with the database and
SSH tunnel passwords — for example to move connections to a new Mac or to read a years-old password to configure
another tool. The export requires confirmation by the Mac owner (Touch ID or password). Passwords can be **encrypted
with a passphrase** (without the passphrase they cannot be recovered) or in **plain text** — Pelikan then warns once
more, and anyone who has the file can read them. **Import Connection Definitions…** recognizes a file with passwords,
asks for the passphrase if it is encrypted, saves the passwords in the Keychain and **deletes the file**.

## Oracle pack licenses

AWR, ASH and ADDM reports require the paid Oracle Diagnostics Pack, and SQL Monitor and SQL Tuning Advisor require the
Tuning Pack. The first time you use such a feature, Pelikan asks which license the database has (*Diagnostics and Tuning
Pack*, *Diagnostics Pack only*, *No license*) and remembers the answer in the connection definition (you change it on
the **Advanced** tab). The feature also does not work when the database parameter `CONTROL_MANAGEMENT_PACK_ACCESS` does
not allow it.

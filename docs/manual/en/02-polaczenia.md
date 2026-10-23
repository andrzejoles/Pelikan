# Connections and password security

## Connection definition

A connection has a name, folder, user, database (EZConnect `host:port/usługa`, `tcps://…` or an alias from
`tnsnames.ora`), role (Normal, SYSDBA…), optionally a proxy user, an edition (EBR) and an environment: development, test
or production. Production connections have a warning color, and statements that change data require confirmation there.

A connection can be **read-only** — Pelikan then rejects DML, DDL and PL/SQL before they reach the database.

## Passwords

Passwords are stored only in the macOS **Keychain** (login keychain, without iCloud sync) and never end up in files,
logs or process arguments. A password is saved only after a successful connection, and only if you select
**Remember password in Keychain**.

In **Preferences › Oracle** you can enable **Require Touch ID or Mac password before using a saved password** — Pelikan
then asks once per connection while the application is running.

## Oracle Wallet

Pelikan supports two kinds of wallet:

- **password store** (Secure External Password Store) — `/@alias` login without entering a password; you select the
  wallet directory in **Preferences › Oracle › Oracle Net and Oracle Wallet**, and choose *Oracle Wallet*
  authentication in the connection. The “Database” field must be exactly the alias stored in the wallet;
- **TLS wallet** (e.g. Autonomous Database) — the wallet directory is set in the connection definition; you can unpack
  the ZIP archive from the portal with the **Import ZIP…** button.

## Other authentication methods

- **External** (Kerberos, operating system).
- **Microsoft Entra ID** — Instant Client 23 opens a browser for sign-in and passes the token to the database itself;
  Pelikan neither sees nor stores the token.
- **OAuth2 token from file** — a token prepared beforehand with an external tool.
- **SSH tunnel** — a connection through an intermediate server (key or SSH agent).

## Oracle pack licenses

AWR, ASH, ADDM, SQL Monitor and SQL Tuning Advisor reports require the paid Oracle Diagnostics/Tuning Pack.
On first use, Pelikan asks whether the database is licensed and remembers the answer in the connection definition.

# Security and privacy

This chapter gathers in one place how Pelikan protects passwords, data and databases — also against mistakes and against
AI agents.

## Passwords

- Database passwords, SSH passwords (tunnels and Pro*C targets) and SSH key passphrases are stored **only in the macOS
  Keychain** — in the login keychain, without iCloud synchronization, available only while the Mac is unlocked.
- Passwords **never** go to Pelikan's files (connection definitions, preferences, worksets, exports), logs, command
  history, process arguments or environment variables. Commands with passwords (`CONNECT`, `ALTER USER … IDENTIFIED BY`,
  `CREATE DATABASE LINK`) are not saved in the command history.
- A password not remembered in the Keychain is kept only in memory until the application quits.
- The **Require Touch ID or Mac password before using a saved password** option (**Preferences › Oracle › Connection
  passwords**) requires confirmation once per connection while the application is running — also when the connection is
  used by an AI agent.
- The SSH password reaches the `ssh` program through a one-time pipe accessible only to your account, not through
  arguments, the environment or a file.
- Passwords from an Oracle Wallet never reach Pelikan — logon is handled by the Oracle client.
- Connection definition exports, preference exports, definitions of jobs, transfers and user tools, utPLSQL scripts for
  CI and startup parameters do not contain passwords.

## Protecting databases against mistakes

- The **connection environment** (development, test, production) is visible as a color throughout the interface.
- On a **production** connection, statements that change data or objects require confirmation.
- A **read-only** connection blocks everything except queries before it is sent to the database (including `SELECT … FOR
  UPDATE` and PL/SQL blocks). The `readonly=` startup parameter lets you open selected connections read-only for a
  single launch.
- Pelikan does not commit transactions by itself: AutoCommit is off by default, and closing a window or the application
  with an open transaction ends with a question.
- Installing utPLSQL from the application works only on development and test connections.
- Tools that generate scripts (comparisons, the cart, refactoring, duality view DDL, ORDS) open them in a SQL Window for
  review — they do not execute them by themselves.

## AI agents

The rules for agents are described in the *AI agents* chapter. In brief:

- the agent knows connections only by name and environment — it does not see passwords, hosts, ports, services or user
  names;
- it has its own database sessions and does not see your transaction;
- it reads in read-only transactions, with limits;
- it makes changes only after your consent in a window without a default button, and DML stays uncommitted until a
  separate consent to COMMIT;
- it has no access to the Command Window, system commands, the debugger, Oracle pack reports or the remote build;
- it communicates with Pelikan only through a socket accessible to your account, with a one-time session token;
- the data the agent reads goes to the AI model provider — for sensitive data use a separate agent database user with
  limited privileges and column masking.

## What leaves your Mac

Pelikan has no telemetry or analytics. It makes network connections only:

- to the databases and SSH servers that you configure;
- to GitHub — once a day to check for updates (and to download them when you agree), and when installing utPLSQL from
  the application (downloading the official release);
- in the browser, when you yourself open the Oracle documentation (F1), a web search or a document with an http(s)
  address.

AI agent programs (Claude Code, Codex, Grok, Antigravity) are independent applications of their providers and connect to
their servers — they send there what the agent reads in Pelikan.

## Data on disk

Pelikan's data is in the `~/Library/Application Support/Pelikan` directory: connection definitions (without passwords),
preferences, command history, worksets and window recovery snapshots (they may contain the text of unsaved windows),
local file history, reports, carts, the agent log. Files with window content and the log are saved with access
permissions for your account only. If your Mac is shared, remember that a person with access to your macOS account also
has access to this data — it is protected by your Mac login password and FileVault disk encryption.

## What Pelikan does not protect against

- Malware running in your macOS account can read the memory and files of your programs — that is the job of the system
  (Gatekeeper, XProtect).
- An agent program started without strict mode has the privileges of your account.
- Committed changes (COMMIT) and DDL on tables cannot be undone — Pelikan says so plainly before execution.
- Functions called in queries can have side effects (e.g. autonomous transactions) — only the database privilege model
  limits them.

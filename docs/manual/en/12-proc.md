# Pro*C: remote build over SSH

Pelikan lets you edit Pro*C programs locally and build them on a server (e.g. AIX) over SSH, in a Git-based workflow:
changes reach the server through `git pull` in the working copy on the server, and Pelikan runs `make` there, installs
the binaries and keeps a deployment history with the option to roll back. Pelikan never sends sources to the server
directly, does not do a `merge` or `reset` on the server and does not run `git push`.

The commands are in the **Tools › Pro*C remote build** menu.

## SSH targets

**Tools › Pro*C remote build › SSH targets…** opens the target manager — the servers you deploy to. You can group
targets in folders, duplicate and delete them. The target form:

- **Connection**: name, folder, environment **UAT** or **PROD** (with a color), host, port, user and authentication —
  **Key file** (optionally with a key passphrase), **SSH agent** or **SSH password**. You save the SSH password and the
  key passphrase in the Keychain (**Remember in Keychain**); with Touch ID protection enabled (**Settings › Oracle ›
  Connection passwords**), Pelikan confirms their use once per target. **Legacy algorithms (AIX 6.1 and older servers)**
  enables SSH algorithms supported by old servers. **Name encoding** and **Console encoding** (UTF-8 or ISO-8859-2) set
  how Pelikan encodes file names and reads the output.
- **Directories on the server**: the base directory, the backup directory, the working copy, and the source and binary
  subdirectories.
- **Git and build**: branch, remote, the build command (e.g. `make`) and the list of binaries (comma-separated).
- **Shell environment**: the path to `ksh`, `ORACLE_HOME`, `LIBPATH`, `PATH` and additional variables (`NAME=value`) — a
  non-interactive shell does not read `.profile`, so here you specify what the build needs.

Target definitions are saved without secrets; **Export SSH targets…** and **Import SSH targets…** move them between
computers. No Oracle passwords are needed on the server — Pro*C is expected to be configured on the server.

### Testing a target

**Test** (in the manager, or **Tools › Pro*C remote build › Test SSH target**) checks: the SSH server version, logon,
the system (`uname -a`, on AIX `oslevel -s`), the availability of `make`, `git` and `compress`/`gzip`, the branch and
cleanliness of the working copy (`git status --porcelain`) and whether the directories are writable. Pelikan creates a
missing backup directory after your confirmation.

On the first test of a new server Pelikan shows its key fingerprint (SHA256) and saves the key to known_hosts only
after you confirm it — compare the fingerprint with the one from your administrator. Deployment to a server whose key
has not been confirmed is refused; a server with a changed key is always refused.

## Deployment

1. Open a project with a local Git repository (Pelikan compares it with the server). Without a project, deployment
   works, but without information about local commits.
2. Choose **Tools › Pro*C remote build › Deploy to target…** and a target. The window shows a **Summary**: the commit on
   the server and in the remote, the commits to deploy, `git diff --stat` and warnings — e.g. unpushed local commits, or
   deploying to PROD a commit that was not on UAT.
3. For a **PROD** target you must type the target's name to confirm the deployment.
4. Click **Deploy**.

On the server, Pelikan performs in turn:

1. takes a **lock** (only one deployment can run on a target at a time);
2. checks the branch and cleanliness of the working copy — manual changes on the server stop the deployment before
   `pull`;
3. `git pull --ff-only`;
4. a backup of the binaries (with the date and commit in the name, packed with `compress` or `gzip`, with a limit on the
   number of copies);
5. `make` (the build command);
6. installation of the new binaries (the previous version stays as `.prev`);
7. an entry in the deployment history on the server and in Pelikan.

## Deployment console

The **Deployment console** shows the steps with their time and result, and the live output. Pro*C compiler errors
(`PCC-…`, also `PLS-…`) and IBM XL C compiler errors (`1506-…`) are clickable — they open the file in the local
repository at the error line. The **Errors and warnings only** option filters the output, and **Save log…** saves it to
a file.

**Tools › Pro*C remote build › Stop deployment** (or **Stop** in the console) interrupts the build on the server
(including processes started by `make`) and always releases its own lock. You release a leftover lock of another
deployment manually with **Release target lock…** — only when you are sure that nobody is deploying right now (on PROD
after typing the target's name).

## Rollback and history

- **Roll back binary…** swaps the current binary with the previous version (`.prev`) or restores a chosen backup
  (unpacked, with the permissions of the current binary).
- **Deployment history** shows the deployments from Pelikan (with the full log) and the history stored on the server.
- **Git and deployment status** puts together: the local branch and unpushed commits, the remote state, the last
  deployment from the history and the commit (HEAD) on each server. **git fetch and refresh** fetches the remote state
  without prompts in the terminal.

## File encoding

Sources on older servers are often in ISO-8859-2. Pelikan detects the encoding of existing files and does not change it
silently: a character that cannot be saved in the file's encoding blocks saving, with the exact location indicated. You
change the encoding only explicitly (**File › File encoding…**); a project can also enforce the encoding of its files.

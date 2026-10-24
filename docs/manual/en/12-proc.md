# Pro*C: remote build over SSH

Pelikan builds Pro*C programs on a server (e.g. AIX) over SSH: it pulls changes from the Git repository into a working
copy on the server, runs `make`, installs the binaries and keeps a deployment history with the option to roll back.

## SSH targets

In **SSH targets** you define a server: host, port, user, authentication (key, SSH agent or password), encoding,
environment (ORACLE_HOME, LIBPATH, PATH), base directory, backup directory, branch and build command. The SSH password
or key passphrase goes to the Keychain, and target definitions are saved without secrets. You mark targets as UAT or
PROD.

**Test** checks the login, the system and SSH server versions, the availability of `make`, `git`, `compress`/`gzip`, the
branch and cleanliness of the working copy, and whether the directories are writable.

## Deployment

A deployment performs, in order: locking (one deployment at a time), a working copy check (manual changes on the server
stop the deployment), `git pull --ff-only`, a backup of the binaries, `make`, installation and a history entry. Pelikan
never performs a merge or reset on the server. Before deploying to PROD you must type the target's name.

The console shows the steps with their duration and result; Pro*C compiler errors (`PCC-…`) and IBM XL C errors
(`1506-…`) are clickable and open the file at the error location. **Stop** interrupts the deployment and always releases
the lock. **Rollback** restores the previous binaries or a selected backup.

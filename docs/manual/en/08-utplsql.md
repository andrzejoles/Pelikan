# utPLSQL tests

Pelikan has built-in support for utPLSQL — the unit testing library for PL/SQL: running tests with live results, code
coverage, generating test skeletons and navigating between a package and its tests. The commands are in the **Tools ›
utPLSQL** menu.

## Installing utPLSQL in the database

**Tools › utPLSQL › utPLSQL: version in database** checks whether utPLSQL is installed and in which version.

If it is not, **utPLSQL: install or upgrade…** downloads the official release from GitHub, verifies its checksum and
runs the installation scripts in a visible SQL*Plus Console. This command works only on development and test connections
and always asks for confirmation. The new utPLSQL owner gets a random password that nobody knows, and its account is
locked right away. On shared databases the installation is usually performed by an administrator.

## Writing tests

- **utPLSQL: generate test package** — when the cursor is in a package (or the package is selected in the Object
  Browser), opens a Program Window with the skeleton of a test package: a suite and one test for each procedure and
  function, with `ut.fail` to be filled in. The skeleton compiles and runs right away.
- The Template Window has a **utPLSQL** folder with templates of a test package, a test, an expected exception, a
  context, expectations and cursor comparison.
- Code completion knows the annotations (after `--%`) and the matchers (after `ut.expect(…).`).
- When compiling the specification of a test package, Pelikan warns about unknown annotations, procedures named in
  `--%beforeall`, `--%aftereach` etc. that are not in the specification, `--%test` without `--%suite`, and unpaired
  `--%context`/`--%endcontext`.
- **utPLSQL: go to test / package under test** (⌃⌘T) switches between a package and its test package (by the name
  `test_name` or by dependencies).

## Running tests

| Command | Shortcut (macOS) | What it runs |
|---|---|---|
| utPLSQL: run all tests | ⇧⌘U | all tests of the current user |
| utPLSQL: run test under cursor | ⌃⌘U | the test procedure under the cursor or the whole test package |
| utPLSQL: run tests from path… | — | paths `schema.package.procedure` or `schema:suite.path`, several separated by commas |
| utPLSQL: run with options… | — | paths, coverage, coverage schemas, included and excluded objects |
| utPLSQL: rerun failed | — | the tests that did not pass in the last run |
| utPLSQL: abort | — | the run in progress |

In the PL/SQL Developer profile the shortcuts are ⌃⇧U (all), ⌃⌥U (under cursor) and ⌃⇧T (go to test). You can also run
the tests of the selected package, procedure or user with **Tools › Object › Run utPLSQL tests**.

## Test explorer

**View › utPLSQL test explorer** shows the tree of suites, contexts and tests of the current user with the result of the
last run. The tree refreshes after compilation; double-clicking a test opens its annotation in the specification. You
run the selected tests with the **Run** or **Run with coverage** button.

## Results window

Results appear live: a progress bar, counters and the name of the current test. Tests run in separate sessions, so
Pelikan's windows stay available.

- The tree of suites, contexts and tests with times and states: **Success**, **Failures**, **Errors**, **Disabled**.
  **Show:** filters by state, **Sort:** changes the order (execution order, name, time, state).
- Test details: the expectation message, **Expected** and **Actual** side by side with the differences highlighted (also
  cursor rows), **Error stack** with a jump to the line, the test's DBMS_OUTPUT and **Open test source**.
- The test menu lets you run a single test again, and **Failed again** — all failed ones.
- **History** keeps the last 20 runs; **Changes** shows which tests changed state compared to the previous run.

## Code coverage

**utPLSQL: tests with code coverage** (or **Run with coverage**) collects coverage for the current schema; in the **run
with options…** window you specify other schemas and the included and excluded objects.

- In the Program Window, lines are marked in the margin: green — covered, yellow — partially, red — not covered.
- The status bar shows the coverage percentage of the object and the schema.
- **Coverage report** opens the utPLSQL HTML report in the browser.

Coverage uses profiler data — before the first such run in a session, Pelikan reminds you about the required privileges.

## Debugging a test

**Debug › utPLSQL: debug test under cursor** opens a Test Window with a `ut.run` call for this test, sets a
breakpoint in the test procedure and starts the debugger (see the *Test Window, debugger and profiler* chapter).

## Results for CI

- **utPLSQL: export results…** runs tests with the JUnit, Sonar, TeamCity or TAP reporter (or with a Cobertura, Sonar or
  HTML coverage report) and saves the result to a file.
- **utPLSQL: command-line script** creates an SQL*Plus/SQLcl script that runs the same tests with a JUnit result, and a
  shell script. The scripts do not contain the password — you provide it in CI from your own secret store.

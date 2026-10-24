# Test Window, debugger and utPLSQL

## Test Window

The Test Window runs a PL/SQL block with bind variables whose values you enter in the table below the block. After
execution the table shows the output values, and the tabs show DBMS_OUTPUT, statistics and the execution profile. Tests
are saved in `.tst` files.

## Debugger

**Start debugging** runs the test step by step: **Step into** (enter a subprogram), **Step Over** (next line), **Step out**
(return from a subprogram), breakpoints (including conditional ones), viewing and changing variable values, and the
call stack. The debugger requires the `DEBUG CONNECT SESSION` and `DEBUG ANY PROCEDURE` privileges (or `DEBUG` on the
object).

## Profiler

The profiler (DBMS_PROFILER or DBMS_HPROF) measures the execution time of each line and subprogram, and session
statistics show how counters changed during the test.

## utPLSQL

The test explorer shows utPLSQL test packages in the database. You can run tests for a package, a suite or the whole
schema; results with timings and error messages appear in the tree, and code coverage in the editor. The generator
creates a test package skeleton for the selected package. Pelikan can also install utPLSQL in a schema (after
confirmation).

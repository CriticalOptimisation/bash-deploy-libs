Command Guard Library
=====================

Location
--------

- `config/command_guard.sh`

Purpose
-------

This library provides a single entry point, `guard`, that defines a Bash function
named after an external command. The generated function shadows the external
command and dispatches to it by full path, ensuring command resolution is not
affected by untrusted PATH prefixes.

Quick Start
-----------

.. code-block:: bash

   # Source once in the main script of your library
   source "$(dirname "$0")/config/command_guard.sh"

   guard ls
   ls -l

Public API
----------

guard
~~~~~

Defines a function named `<command>` that forwards to the external command by
full path.

- Usage: `guard <command>`
- Returns:
  - `CG_ERR_MISSING_COMMAND` when no command name is provided.
  - `CG_ERR_INVALID_NAME` when the name is not a valid Bash identifier.
  - `CG_ERR_NOT_FOUND` when the command cannot be resolved to an executable path.

Error Codes
-----------

- `CG_ERR_MISSING_COMMAND=1`: missing command argument.
- `CG_ERR_INVALID_NAME=2`: invalid command name.
- `CG_ERR_NOT_FOUND=3`: command not found in the restricted PATH.

Behavior Details
----------------

Command resolution is performed with `command -pv` in a subshell that uses the
default builtin restricted PATH. The resolved path must be absolute and
executable.

It is an error to call guard on aliases and shell builtins. An error message 
will be printed on stderr and the script will be aborted. Subshells 

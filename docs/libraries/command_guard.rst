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

- Usage: `guard [-q] [--] [token ...]`
- Options:
  - `-q`: Quiet mode, suppresses warnings for zero commands.
  - `--`: End of options, start of token list.
- Tokens: each token is either a plain command name or a ``name=path`` pair:
  - **Plain name** (e.g. ``uname``): the command is resolved via the builtin
    restricted PATH using ``command -pv``.
  - **name=path** (e.g. ``uname=/usr/bin/uname``): the command function is
    pinned to the specified absolute path, bypassing PATH resolution entirely.
    The ``name`` must be a valid Bash identifier. The ``path`` must be absolute
    (start with ``/``) and point to an existing, executable file.
  - Both forms may be mixed freely in a single ``guard`` call.
  - Validation is all-or-nothing: no wrapper functions are created unless
    every token passes validation.
- Returns:
  - ``0`` on success, including when zero tokens are provided (with optional warning).
  - ``CG_ERR_INVALID_NAME`` when an option is invalid, a command name is not a
    valid Bash identifier, or the ``name`` part of a ``name=path`` token is not
    a valid Bash identifier.
  - ``CG_ERR_NOT_FOUND`` when a plain command cannot be resolved, or the ``path``
    part of a ``name=path`` token does not exist, is not executable, or is not
    an absolute path.

Error Codes
-----------

- ``CG_ERR_INVALID_NAME=2``: invalid command identifier or option.
- ``CG_ERR_NOT_FOUND=3``: command not found or path invalid/non-executable.

Behavior Details
----------------

Command resolution is performed with `command -pv` in a subshell that uses the
default builtin restricted PATH. The resolved path must be absolute and
executable.

It is an error to call guard on aliases and shell builtins. An error message 
will be printed on stderr and the script will be aborted. 

Subshells will be exited but the overall script may continue to run. Avoid
using constructs that generate subshells in favor of returning results by
out-variables.

.. code-block: bash
  myfunction() {
    local arg1=$1
    local -n out=$2

    # ... compute result ...
    out=$result
  }
  
  if myfunction "$arg" result; then
    : # use "$result"
  else
    : # handle failure. "$result" may not be set.
  fi


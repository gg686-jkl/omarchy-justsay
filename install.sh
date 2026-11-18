#!/bin/bash
# Just Say installer entry point. Safe to run again (repairs, never duplicates).
exec "$(dirname "$(readlink -f "$0")")/bin/justsay" install "$@"

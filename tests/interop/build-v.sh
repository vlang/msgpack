#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
export PYTHONDONTWRITEBYTECODE=1
export V_C_ERROR_BUG_REPORT_DISABLED=1
module_parent="${1:?usage: bash build-v.sh /parent/containing/msgpack [new|old]}"
compiler="${2:-new}"
case "$compiler" in
    new) compiler_flag=-new-compiler; export V_MACOS_V3_NO_FALLBACK=1 ;;
    old) compiler_flag=-old-compiler ;;
    *) echo 'compiler must be new or old' >&2; exit 1 ;;
esac
work_dir="$(python3 paths.py)"
mkdir -p "$work_dir/build"
"${V:-v}" "$compiler_flag" -path "$module_parent|@vlib" -o "$work_dir/build/v-adapter" native/v_adapter.v
"${V:-v}" "$compiler_flag" -path "$module_parent|@vlib" -o "$work_dir/build/generic-test" run native/generic_test.v

#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
export PYTHONDONTWRITEBYTECODE=1
work_dir="$(python3 paths.py)"
if [[ ! -x "$work_dir/build/go-adapter" || ! -x "$work_dir/build/c-adapter" || ! -x "$work_dir/rust-target/release/rust-adapter" || ! -d "$work_dir/native/node_modules/@msgpack/msgpack" ]]; then
    bash setup.sh
fi
exec python3 run.py "$@"

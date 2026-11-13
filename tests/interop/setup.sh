#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
root_dir="$PWD"
export PYTHONDONTWRITEBYTECODE=1
work_dir="$(python3 paths.py)"
export UV_CACHE_DIR="$work_dir/cache/uv"
export GOMODCACHE="$work_dir/cache/go-mod"
export GOCACHE="$work_dir/cache/go-build"
export CARGO_HOME="$work_dir/cache/cargo"
export CARGO_TARGET_DIR="$work_dir/rust-target"
export npm_config_cache="$work_dir/cache/npm"
mkdir -p "$work_dir/build" "$work_dir/deps" "$work_dir/native"
c_revision=dbc7bfbbff2a54c0b41a78187f92667e0ca6413f
if [[ ! -d "$work_dir/deps/msgpack-c/.git" ]]; then
    git clone --no-checkout https://github.com/msgpack/msgpack-c.git "$work_dir/deps/msgpack-c"
    git -C "$work_dir/deps/msgpack-c" checkout --detach "$c_revision"
fi
[[ "$(git -C "$work_dir/deps/msgpack-c" rev-parse HEAD)" == "$c_revision" ]] || { echo 'msgpack-c revision mismatch' >&2; exit 1; }
uv run native/python_adapter.py </dev/null
(
    cd native
    go mod download all
    go build -mod=readonly -o "$work_dir/build/go-adapter" go_adapter.go
    cargo build --locked --release
)
cp native/package.json native/package-lock.json native/js_adapter.mjs "$work_dir/native/"
npm ci --prefix "$work_dir/native" --ignore-scripts --no-audit --no-fund
cmake -S "$work_dir/deps/msgpack-c" -B "$work_dir/build/c" -DMSGPACK_BUILD_TESTS=OFF -DMSGPACK_BUILD_EXAMPLES=OFF -DBUILD_SHARED_LIBS=OFF
cmake --build "$work_dir/build/c" -j 4
cc -std=c11 -O2 -Wall -Wextra -I "$work_dir/deps/msgpack-c/include" -I "$work_dir/build/c/include" -I "$work_dir/build/c/include/msgpack" native/c_adapter.c "$work_dir/build/c/libmsgpack-c.a" -o "$work_dir/build/c-adapter"
{
    printf 'msgpack-c %s\n' "$c_revision"
    uv --version
    go version
    cargo --version
    node --version
    cc --version
} >"$work_dir/build/versions.txt"

#!/usr/bin/env bash
# Build BOTH adapter-das wheels from the single version source
# (sgl_kernel/version.py -- governance §7.4). One command, two artifacts:
#   dist/sgl_kernel-<version>+hcu.<stamp>-*.whl   (pure shadow kernel)
#   dist/hcu_adapter-<version>+hcu.<stamp>-*.whl  (adapter: bootstrap + bridges + hooks)
# Both wheels of one run carry the same hcu.<time>.g<commit> local version, and
# hcu-adapter pins the exact stamped kernel version (build-time interlock).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^__version__ = "\(.*\)"$/\1/p' "$ROOT/sgl_kernel/version.py")"
if [ -z "$VERSION" ]; then
    echo "build.sh: cannot read __version__ from sgl_kernel/version.py" >&2
    exit 1
fi

# the adapter dist carries its own independent version line (hand-edited
# single source: packaging/hcu-adapter/VERSION)
ADAPTER_VERSION="$(tr -d ' \t\r\n' < "$ROOT/packaging/hcu-adapter/VERSION")"
if [ -z "$ADAPTER_VERSION" ]; then
    echo "build.sh: packaging/hcu-adapter/VERSION is empty" >&2
    exit 1
fi

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
    # probe: some Windows boxes ship a Microsoft-Store python3 stub that
    # exists on PATH but cannot run
    for cand in python3 python; do
        if "$cand" -c "import sys" >/dev/null 2>&1; then PY="$cand"; break; fi
    done
fi
[ -n "$PY" ] || { echo "build.sh: no working python3/python on PATH" >&2; exit 1; }

# one stamp for both wheels: <YYMMDDHHMM>.g<commit6> (rendered as hcu.<stamp>),
# no dtk/torch parts
DAS_BUILD_STAMP="${DAS_BUILD_STAMP:-$(date +%y%m%d%H%M).g$(git -C "$ROOT" rev-parse --short=6 HEAD)}"
export DAS_BUILD_STAMP

# pin check: _pin.py is the build-time interlock source, ci/l0_gate re-checks
EXPECTED_PIN="sgl-kernel==${VERSION%%+*}"
ACTUAL_PIN="$(SGL_ADAPTER_ROOT="$ROOT" "$PY" -c '
import os, sys
sys.path.insert(0, os.path.join(os.environ["SGL_ADAPTER_ROOT"], "packaging", "hcu-adapter"))
import _pin
print(_pin.kernel_pin(stamp=""))
')"
if [ "$ACTUAL_PIN" != "$EXPECTED_PIN" ]; then
    echo "build.sh: hcu-adapter interlock pin ${ACTUAL_PIN}" \
         "does not match public version ${EXPECTED_PIN#sgl-kernel==} (governance §7.4)" >&2
    exit 1
fi

mkdir -p "$ROOT/dist"

echo "== build stamp: hcu.${DAS_BUILD_STAMP} =="
echo "== building sgl-kernel ${VERSION}+hcu.${DAS_BUILD_STAMP} (repo root) =="
"$PY" -m pip wheel --no-deps --no-build-isolation \
    --wheel-dir "$ROOT/dist" "$ROOT"

echo "== building hcu-adapter ${ADAPTER_VERSION%%+*}+hcu.${DAS_BUILD_STAMP} (packaging/hcu-adapter) =="
"$PY" -m pip wheel --no-deps --no-build-isolation \
    --wheel-dir "$ROOT/dist" "$ROOT/packaging/hcu-adapter"

ls -l "$ROOT/dist"/sgl_kernel-"${VERSION%%+*}"+*.whl "$ROOT/dist"/hcu_adapter-"${ADAPTER_VERSION%%+*}"+*.whl

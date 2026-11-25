#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LMCACHE_ROOT="/test/workdir/lmcache-io-metrics-0.5.3/lmcache-0.5.3"
PYTHON_BIN="/test/venv/bin/python3"

export PYTHONPATH="${LMCACHE_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"

verify_module_path() {
  local module_name="$1"
  local expected_path="$2"
  local actual_path

  actual_path="$(
    "${PYTHON_BIN}" -c \
      'import importlib.util, pathlib, sys; spec = importlib.util.find_spec(sys.argv[1]); print(pathlib.Path(spec.origin).resolve())' \
      "${module_name}"
  )"

  echo "[io-metrics] ${module_name}: ${actual_path}"
  if [[ "${actual_path}" != "${expected_path}" ]]; then
    echo "[io-metrics] ERROR: expected ${expected_path}, got ${actual_path}" >&2
    exit 1
  fi
}

verify_module_path "lmcache" "${LMCACHE_ROOT}/lmcache/__init__.py"
verify_module_path \
  "lmcache.integration.vllm.lmcache_mp_connector" \
  "${LMCACHE_ROOT}/lmcache/integration/vllm/lmcache_mp_connector.py"
verify_module_path \
  "lmcache.v1.mp_observability.subscribers.metrics.l2_io" \
  "${LMCACHE_ROOT}/lmcache/v1/mp_observability/subscribers/metrics/l2_io.py"

echo "[io-metrics] PYTHONPATH verified"

if [[ "${VERIFY_ONLY:-0}" == "1" ]]; then
  exit 0
fi

exec bash "${SCRIPT_DIR}/start_lmcache_vllm.sh"

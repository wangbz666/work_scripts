#!/usr/bin/env bash
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

YRCACHE_CONFIG_FILE="${SCRIPT_DIR}/yrcache.yaml" \
PROMETHEUS_MULTIPROC_DIR=/test/yrcache_export \
LLM_USE_MODELSCOPE=True \
YRCACHE_LOG_LEVEL=INFO \
CUDA_VISIBLE_DEVICES=0 \
vllm serve /workspaces/modelscope-yrcache/modelscope/deepseek-ai/DeepSeek-R1-Distill-Qwen-14B \
            --max-model-len auto  --port 8000 --tensor-parallel-size 1 \
	    --no-enable-prefix-caching \
            --kv-transfer-config '{"kv_connector": "YRCacheConnector", "kv_role": "kv_both", "kv_connector_module_path":"yrcache.integration.vllm.yrcache_connector"}' \
            --served-model-name deepseek-14b  --trust-remote-code \
	    > ./yrcache_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# Case 4 · 220G-DRAM · n64-16k-c3 local disk KV cache benchmark

English | [中文](README.zh-CN.md)

Compare LMCache and YRCache with a 220 GiB DRAM cache on each backend. Send 64 requests with 16,384 input tokens each, concurrency 3, an output length setting of 100 tokens and seed 42. Run each backend separately. The first pass populates the disk cache. Restart the services to release CPU and GPU cache state, then replay the same requests to measure local disk hits.

The workload represents about 193.17 GiB of KV data at 192 KiB/token. Check eviction counters for the no-eviction condition and disk hits after restart. Both backends use 16 workers: YRCache sets `nr_workers: 16` in `yrcache/yrcache.yaml`, and the LMCache L2 adapter sets `num_workers: 16` in `lmcache/start_lmcache.sh`. On host 85, the launchers invoke the virtual environment interpreter explicitly because its console scripts still reference the old installation path.

## Before you start

The reference setup uses LMCache 0.5.3 (custom build with I/O metrics), YRCache 1.9.0, vLLM 0.24.0, EvalScope 1.10.0, Python 3.12 and DeepSeek-R1-Distill-Qwen-14B. Supply the model, software, GPU and a dedicated local cache disk. The examples assume the case directory at `/workspaces/case4-dram220-n64-16k-c3-nr_workers16`. Adjust this path and the host-specific settings below.

| Setting | Where to check |
| --- | --- |
| Python environment | If the environment moves, update `/test/venv` in the launchers, EvalScope scripts and PATH commands. |
| Model and tokenizer | Match the model in both vLLM launchers to `TOKENIZER_PATH` in the EvalScope script. Match `--served-model-name` to `MODEL` (default `deepseek-14b`). |
| API and GPU | Update `WARMUP_URL`, `PRESTRESS_URL`, `TEST_URL` and the readiness checks. The launchers use GPU 0, port 8000 and tensor parallel size 1. |
| LMCache | In both metrics wrappers, set `LMCACHE_ROOT` to the custom source tree and `PYTHON_BIN` to its interpreter. The wrappers check the metrics modules and Python 3.12 native extension. In `lmcache/start_lmcache.sh`, check the numactl path, NUMA node and L2 adapter's disk path. Keep L1 at 220 GiB. Match server port 5555 to `lmcache.mp.port` in the vLLM launcher. Ensure the log and metrics directories are writable. |
| YRCache | In `yrcache/yrcache.yaml`, keep the CPU cache settings at 232 total and 12 reserved. Set `local_disk_cache_config.local_disks` for your disk. The suffix in `/test/data_disk_1/case4-yrcache:100` is a disk percentage (100%), not a GiB limit. Enable local disk caching and disable shared storage caching. Create a writable `PROMETHEUS_MULTIPROC_DIR` for the launcher. |

## LMCache

1. Stop any previous test instance. Clear **only the dedicated benchmark cache**, once before the fill pass.

```bash
mkdir -p /test/data_disk/case4-lmcache
rm -rf /test/data_disk/case4-lmcache/*
```

2. Start LMCache in terminal A. Keep it running.

```bash
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/lmcache
bash start_lmcache_io_metrics.sh
```

3. Wait for terminal A to report `LMCache ZMQ cache server is running on tcp://127.0.0.1:5555` (allocating 220 GiB can take over a minute). Start vLLM in terminal B. Keep it running.

```bash
export PATH="/test/venv/bin:$PATH"
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/lmcache
bash start_lmcache_vllm_io_metrics.sh
```

4. In terminal C, wait until the API lists `deepseek-14b`, then run the fill pass.

```bash
curl -f http://192.168.255.85:8000/v1/models
```

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/lmcache-fill
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/lmcache-fill
bash /workspaces/case4-dram220-n64-16k-c3-nr_workers16/evalscope/n64-16k-c3-prestress_test.sh
```

5. Confirm all 64 requests succeeded and disk writes finished without errors. Stop vLLM in B with Ctrl+C, then stop LMCache in A. Wait for their workers to exit. **Keep the disk data** and repeat steps 2–4 through the API readiness check only. Run the measurement below.

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/lmcache-disk-hit
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/lmcache-disk-hit
bash /workspaces/case4-dram220-n64-16k-c3-nr_workers16/evalscope/n64-16k-c3-prestress_test.sh
```

Save the results and corresponding cache logs, then stop both services before switching backends.

## YRCache

1. Stop the previous test instance. Clear only the dedicated cache before the fill pass.

```bash
mkdir -p /test/data_disk_1/case4-yrcache
rm -rf /test/data_disk_1/case4-yrcache/*
```

2. Start vLLM with YRCacheConnector. The launcher returns immediately. Check the timestamped log in the launch directory and wait for the model to appear.

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /test/yrcache_export
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/yrcache
bash start_yrcache_vllm_1_9.sh
```

```bash
curl -f http://192.168.255.85:8000/v1/models
```

3. Run the fill pass.

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/yrcache-fill
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/yrcache-fill
bash /workspaces/case4-dram220-n64-16k-c3-nr_workers16/evalscope/n64-16k-c3-prestress_test.sh
```

4. Confirm all 64 requests succeeded and checkpoint writes completed. Identify this instance's vLLM process.

```bash
ps -eo pid,ppid,args --forest | grep -E '[v]llm|[y]rcache'
```

Send `kill -TERM <PID>` to its main process and wait for its workers to exit. Check GPU usage with `nvidia-smi`. **Keep the disk data**, repeat step 2, then measure.

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/yrcache-disk-hit
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/yrcache-disk-hit
bash /workspaces/case4-dram220-n64-16k-c3-nr_workers16/evalscope/n64-16k-c3-prestress_test.sh
```

Save the logs and stop the instance.

## Reading the results

Compare average TTFT, average TPOT, output throughput and total throughput from the two `*-disk-hit` directories. Each run produces `kv_cache_result.csv` and detailed EvalScope reports under `results/`. Use fresh result directories for each repeat to avoid appending to an old CSV.

- Run the case script as shown for both passes. Its default skips the internal warmup and prestress stages. Adding `--only-prestress` can send zero requests. The other two EvalScope scripts are backups for different workloads.
- This case finishes after 64 requests. Keep the model, tokenizer, seed and workload identical. After restarting, check readiness through the models endpoint before replaying requests.
- Verify the successful request count, disk-tier hits, misses and reads together. A PASS result or disk traffic alone cannot establish a full disk hit. Restarting clears application caches while the OS page cache persists. Verify Direct I/O is active for both backends.
- Record hardware and backend settings alongside results. YRCache explicitly disables vLLM prefix caching. LMCache uses its configured default. Asynchronous loading policies can also affect comparisons. Keep generated results, logs, cached data and credentials out of Git.

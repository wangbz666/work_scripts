# Case 1 · 100G-DRAM · n64-16k-c3 local disk KV cache benchmark

English | [中文](README.zh-CN.md)

Compare LMCache and YRCache with a 100G DRAM cache on each backend. Send 64 requests with 16,384 input tokens each, concurrency 3, an output length setting of 100 tokens and seed 42. Run each backend separately. The first pass populates the disk cache. Restart the services to release CPU and GPU cache state, then replay the same requests to measure local disk hits.

## Before you start

The reference setup uses LMCache 0.5.3 (custom build with I/O metrics), YRCache 1.9.0, vLLM 0.24.0, EvalScope 1.10.0, Python 3.12 and DeepSeek-R1-Distill-Qwen-14B. Supply the model, software, GPU and a dedicated local cache disk. The examples assume a checkout at `/workspaces/work_scripts`. Adjust this path and the host-specific settings below.

| Setting | Where to check |
| --- | --- |
| Python environment | Replace `/test/venv` in the LMCache launchers and activation commands. Run vLLM and EvalScope in the intended environment. |
| Model and tokenizer | Match the model in both vLLM launchers to `TOKENIZER_PATH` in the EvalScope script. Match `--served-model-name` to `MODEL` (default `deepseek-14b`). |
| API and GPU | Update `WARMUP_URL`, `PRESTRESS_URL`, `TEST_URL` and the readiness checks. The launchers use GPU 0, port 8000 and tensor parallel size 1. |
| LMCache | In both metrics wrappers, set `LMCACHE_ROOT` to the custom source tree and `PYTHON_BIN` to its interpreter. The wrappers check the metrics modules and Python 3.12 native extension. In `lmcache/start_lmcache.sh`, check the numactl path, NUMA node and L2 adapter's disk path. Keep L1 at 100 GiB. Match server port 5555 to `lmcache.mp.port` in the vLLM launcher. Ensure the log and metrics directories are writable. |
| YRCache | In `yrcache/yrcache.yaml`, keep the CPU cache settings at 112 total and 12 reserved. Set `local_disk_cache_config.local_disks` for your disk. The suffix in `/test/data_disk_1/case1-yrcache:100` specifies capacity. Enable local disk caching and disable shared storage caching. Create a writable `PROMETHEUS_MULTIPROC_DIR` for the launcher. |

## LMCache

1. Stop any previous test instance. Clear **only the dedicated benchmark cache**, once before the fill pass.

```bash
mkdir -p /test/data_disk/case1-lmcache
rm -rf /test/data_disk/case1-lmcache/*
```

2. Start LMCache in terminal A. Keep it running.

```bash
cd /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/lmcache
bash start_lmcache_io_metrics.sh
```

3. Start vLLM in terminal B. Keep it running.

```bash
source /test/venv/bin/activate
cd /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/lmcache
bash start_lmcache_vllm_io_metrics.sh
```

4. In terminal C, wait until the API lists `deepseek-14b`, then run the fill pass.

```bash
curl -f http://192.168.255.85:8000/v1/models
```

```bash
source /test/venv/bin/activate
mkdir -p /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/results/lmcache-fill
cd /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/results/lmcache-fill
bash /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/evalscope/n64-16k-c3-prestress_test.sh
```

5. Confirm all 64 requests succeeded and disk writes finished without errors. Stop vLLM in B with Ctrl+C, then stop LMCache in A. Wait for their workers to exit. **Keep the disk data** and repeat steps 2–4 through the API readiness check only. Run the measurement below.

```bash
source /test/venv/bin/activate
mkdir -p /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/results/lmcache-disk-hit
cd /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/results/lmcache-disk-hit
bash /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/evalscope/n64-16k-c3-prestress_test.sh
```

Save the results and corresponding cache logs, then stop both services before switching backends.

## YRCache

1. Stop the previous test instance. Clear only the dedicated cache before the fill pass.

```bash
mkdir -p /test/data_disk_1/case1-yrcache
rm -rf /test/data_disk_1/case1-yrcache/*
```

2. Start vLLM with YRCacheConnector. The launcher returns immediately. Check the timestamped log in the launch directory and wait for the model to appear.

```bash
source /test/venv/bin/activate
mkdir -p /test/yrcache_export
cd /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/yrcache
bash start_yrcache_vllm_1_9.sh
```

```bash
curl -f http://192.168.255.85:8000/v1/models
```

3. Run the fill pass.

```bash
source /test/venv/bin/activate
mkdir -p /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/results/yrcache-fill
cd /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/results/yrcache-fill
bash /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/evalscope/n64-16k-c3-prestress_test.sh
```

4. Confirm all 64 requests succeeded and checkpoint writes completed. Identify this instance's vLLM process.

```bash
ps -eo pid,ppid,args --forest | grep -E '[v]llm|[y]rcache'
```

Send `kill -TERM <PID>` to its main process and wait for its workers to exit. Check GPU usage with `nvidia-smi`. **Keep the disk data**, repeat step 2, then measure.

```bash
source /test/venv/bin/activate
mkdir -p /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/results/yrcache-disk-hit
cd /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/results/yrcache-disk-hit
bash /workspaces/work_scripts/perf_test/case1-dram100-n64-16k-c3/evalscope/n64-16k-c3-prestress_test.sh
```

Save the logs and stop the instance.

## Reading the results

Compare average TTFT, average TPOT, output throughput and total throughput from the two `*-disk-hit` directories. Each run produces `kv_cache_result.csv` and detailed EvalScope reports under `results/`. Use fresh result directories for each repeat to avoid appending to an old CSV.

- Run the case script as shown for both passes. Its default skips the internal warmup and prestress stages. Adding `--only-prestress` can send zero requests. The other two EvalScope scripts are backups for different workloads.
- This case finishes after 64 requests. Keep the model, tokenizer, seed and workload identical. After restarting, check readiness through the models endpoint before replaying requests.
- Verify the successful request count, disk-tier hits, misses and reads together. A PASS result or disk traffic alone cannot establish a full disk hit. Restarting clears application caches while the OS page cache persists. Verify Direct I/O is active for both backends.
- Record hardware and backend settings alongside results. YRCache explicitly disables vLLM prefix caching. LMCache uses its configured default. Asynchronous loading policies can also affect comparisons. Keep generated results, logs, cached data and credentials out of Git.

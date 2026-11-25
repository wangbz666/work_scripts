# 220G-DRAM · case4-dram220-n64-16k-c3-nr_workers16：本地盘 KV 缓存命中性能测试

[English](README.md) | 中文

两种后端均配置 220 GiB 内存缓存。

测试 LMCache、YRCache 在 **64 个请求、每个请求输入 16K（16384）tokens、3 并发**场景下全部命中本地盘缓存的性能。输出长度参数为 100 tokens，随机种子为 42。

两种后端分别执行：**清空测试盘缓存 → 启动服务 → 第一轮填充缓存 → 停止服务 → 保留盘数据重启 → 第二轮正式测试**。

按每 token 192 KiB 估算，本用例 KV 数据约 193.17 GiB。用淘汰计数确认无内存淘汰，重启后核对本地盘命中。两种后端均配置 16 个 worker。YRCache 在 `yrcache/yrcache.yaml` 中设置 `nr_workers: 16`，LMCache L2 适配器在 `lmcache/start_lmcache.sh` 中设置 `num_workers: 16`。85 上已迁移的虚拟环境入口仍引用旧解释器路径，用例脚本显式调用 /test/venv/bin/python3。

## 1. 环境和目录

| 组件 | 原测试版本 |
| --- | --- |
| LMCache | 0.5.3，使用带 I/O metrics 的定制源码 |
| YRCache | 1.9.0 |
| vLLM | 0.24.0 |
| EvalScope | 1.10.0 |
| Python | 3.12 |
| 模型 | DeepSeek-R1-Distill-Qwen-14B |

需提前准备模型、上述软件环境、可用 GPU 和容量足够的本地缓存盘。本目录只备份了脚本与配置，不包含模型、软件安装包或 LMCache 定制源码。

```text
case4-dram220-n64-16k-c3-nr_workers16/
├── README.md
├── README.zh-CN.md
├── evalscope/
│   ├── n64-16k-c3-prestress_test.sh  # 本用例使用此脚本
│   ├── kv_prestress_test_90s.sh         # 其他场景备份
│   └── kv_prestress_test_90s_30k64.sh    # 其他场景备份
├── lmcache/
│   ├── start_lmcache.sh
│   ├── start_lmcache_io_metrics.sh
│   ├── start_lmcache_vllm.sh
│   └── start_lmcache_vllm_io_metrics.sh
└── yrcache/
    ├── start_yrcache_vllm_1_9.sh
    └── yrcache.yaml
```

## 2. 测试前需要修改的配置

直接修改上述脚本和 YAML 中对应的值即可。本文命令以 `/workspaces/case4-dram220-n64-16k-c3-nr_workers16` 为 case 目录；如果放在其他位置，替换下文命令中的 case 路径即可。

### 2.1 通用配置

| 需要核对的内容 | 修改位置 | 修改说明 |
| --- | --- | --- |
| Python 虚拟环境 | 启动脚本、EvalScope 脚本及本文 PATH 命令中的 `/test/venv` | 改为实际虚拟环境路径。vLLM 和 EvalScope 均由该环境的解释器启动 |
| 模型路径 | `lmcache/start_lmcache_vllm.sh`、`yrcache/start_yrcache_vllm_1_9.sh` 中的 `vllm serve` 参数；压测脚本中的 `TOKENIZER_PATH` | 默认 `/workspaces/modelscope-yrcache/modelscope/deepseek-ai/DeepSeek-R1-Distill-Qwen-14B`，三处必须使用匹配的模型和 tokenizer |
| API 地址 | 压测脚本中的 `WARMUP_URL`、`PRESTRESS_URL`、`TEST_URL` | 默认 `http://192.168.255.85:8000/v1/chat/completions`，改为实际服务 IP 和端口 |
| 服务模型名 | 两个 vLLM 启动脚本中的 `--served-model-name`，压测脚本中的 `MODEL` | 默认均为 `deepseek-14b`，如修改必须保持一致 |
| GPU、端口、并行度 | 启动脚本中的 `CUDA_VISIBLE_DEVICES`、`--port`、`--tensor-parallel-size` | 默认 GPU 0、API 端口 8000、TP=1；按机器资源调整，两种后端不要同时启动 |

### 2.2 LMCache 配置

| 文件 | 需要核对或修改的内容 |
| --- | --- |
| `lmcache/start_lmcache_io_metrics.sh`、`lmcache/start_lmcache_vllm_io_metrics.sh` | `LMCACHE_ROOT` 改为实际的 **LMCache 定制源码目录**；`PYTHON_BIN` 改为虚拟环境中的 `python3` 路径 |
| `lmcache/start_lmcache.sh` | `numactl` 可执行文件路径、NUMA node、`--l1-size-gb` 内存容量，以及 `--l2-adapter` 中的 `base_path` 本地缓存目录 |
| `lmcache/start_lmcache_vllm.sh` | 模型路径、虚拟环境路径；`PROMETHEUS_MULTIPROC_DIR` 和 `mkdir -p` 中的日志/指标目录应存在且可写 |

`LMCACHE_ROOT` 仍指向定制源码，不要改为本 case 的 `lmcache` 目录。包装脚本会校验 `l2_io.py` 等模块和 Python 3.12 的原生扩展；缺失时需补齐对应构建，不能仅用普通 LMCache 安装包替代。

原 LMCache 缓存目录为 `/test/data_disk/case4-lmcache`，L1 配置为 220 GiB。若修改 server 的 5555 端口，需同步修改 vLLM 脚本中 `lmcache.mp.port`。

### 2.3 YRCache 配置

| 文件 | 需要核对或修改的内容 |
| --- | --- |
| `yrcache/start_yrcache_vllm_1_9.sh` | `PROMETHEUS_MULTIPROC_DIR` 指向可写的指标目录；提前创建该目录 |
| `yrcache/yrcache.yaml` | `local_disk_cache_config.local_disks` 改为实际缓存目录和容量；原值为 `/test/data_disk_1/case4-yrcache:100`，其中 `:100` 表示磁盘百分比（100%），不是 100 GiB |
| 同上 | 按可用内存核对 `cpu_cache_config`；原值为 `max_cpu_memory_size: 232`、`reserve_memory_size: 12` |

本用例保持 `enable_local_disk_cache: true`、`enable_shared_storage_cache: false`。共享存储段里的 Redis 等配置不参与本次测试。

## 3. LMCache 测试步骤

以下路径如已在第 2 节修改，请同步替换命令中的路径。所有命令使用 Bash 执行。

### 3.1 首轮前清空测试缓存

先确认旧的 LMCache/vLLM 实例已停止。以下删除命令只用于专用测试缓存目录，**填充与正式测试之间不能再执行**。

```bash
mkdir -p /test/data_disk/case4-lmcache
rm -rf /test/data_disk/case4-lmcache/*
```

### 3.2 启动 LMCache 和 vLLM

终端 A 启动 LMCache，保持终端运行：

```bash
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/lmcache
bash start_lmcache_io_metrics.sh
```

等终端 A 显示 `LMCache ZMQ cache server is running on tcp://127.0.0.1:5555`（分配 220 GiB 可能超过一分钟）后，在终端 B 启动 vLLM，保持终端运行：

```bash
export PATH="/test/venv/bin:$PATH"
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/lmcache
bash start_lmcache_vllm_io_metrics.sh
```

在终端 C 检查 API。返回模型列表且包含 `deepseek-14b` 后再压测；如果未就绪，查看 A、B 终端的启动日志。

```bash
curl -f http://192.168.255.85:8000/v1/models
```

### 3.3 第一轮：填充缓存

在终端 C 执行，结果保存在 `results/lmcache-fill`：

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/lmcache-fill
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/lmcache-fill
bash /workspaces/case4-dram220-n64-16k-c3-nr_workers16/evalscope/n64-16k-c3-prestress_test.sh
```

### 3.4 停止并重启

1. 确认第一轮 64 个请求全部成功，缓存写入完成，日志无持久化错误。
2. 在终端 B 按 `Ctrl+C` 停止 vLLM，再在终端 A 按 `Ctrl+C` 停止 LMCache。
3. 确认本次实例的子进程和 GPU worker 已退出，以清除应用内存和 GPU KV 缓存。
4. **保留盘缓存，重新执行 3.2 的启动和就绪检查。不要执行 3.1。**

### 3.5 第二轮：正式测量

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/lmcache-disk-hit
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/lmcache-disk-hit
bash /workspaces/case4-dram220-n64-16k-c3-nr_workers16/evalscope/n64-16k-c3-prestress_test.sh
```

记录第二轮结果及同期缓存命中/磁盘读取日志。完成后停止 LMCache 和 vLLM，再测试 YRCache。

## 4. YRCache 测试步骤

### 4.1 首轮前清空测试缓存

确认旧实例已经停止。仅第一轮填充前清理，目录必须是专用测试目录。

```bash
mkdir -p /test/data_disk_1/case4-yrcache
rm -rf /test/data_disk_1/case4-yrcache/*
```

### 4.2 启动 YRCache + vLLM

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /test/yrcache_export
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/yrcache
bash start_yrcache_vllm_1_9.sh
```

此脚本通过 `YRCacheConnector` 启动集成 YRCache 的 vLLM，已自带后台运行。日志在当前目录的 `yrcache_时间戳.log`，命令返回不代表服务已就绪。检查日志，并确认以下命令返回包含 `deepseek-14b` 的模型列表：

```bash
curl -f http://192.168.255.85:8000/v1/models
```

### 4.3 第一轮：填充缓存

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/yrcache-fill
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/yrcache-fill
bash /workspaces/case4-dram220-n64-16k-c3-nr_workers16/evalscope/n64-16k-c3-prestress_test.sh
```

### 4.4 停止并重启

确认 64 个请求全部成功，缓存已完成写盘/checkpoint，日志无错误。然后停止 **YRCache 对应的 vLLM 主进程及其 worker**。

脚本是后台启动，不能仅在启动终端按 `Ctrl+C`。先查找本次实例的 PID：

```bash
ps -eo pid,ppid,args --forest | grep -E '[v]llm|[y]rcache'
```

核对后执行 `kill -TERM 实际主进程PID`，等待主进程及子进程退出，用 `nvidia-smi` 检查 GPU worker 是否已释放。不要终止其他任务的进程。

**保留盘缓存，重新执行 4.2 的启动和就绪检查。不要执行 4.1。**

### 4.5 第二轮：正式测量

```bash
export PATH="/test/venv/bin:$PATH"
mkdir -p /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/yrcache-disk-hit
cd /workspaces/case4-dram220-n64-16k-c3-nr_workers16/results/yrcache-disk-hit
bash /workspaces/case4-dram220-n64-16k-c3-nr_workers16/evalscope/n64-16k-c3-prestress_test.sh
```

记录第二轮结果及同期缓存命中/磁盘读取日志，测试结束后停止本次实例。

## 5. 结果与注意事项

每个结果目录下都有 `kv_cache_result.csv`，以及 `results/` 内的详细日志和 EvalScope 原始报告。比较 **`lmcache-disk-hit` 与 `yrcache-disk-hit`** 中的正式轮数据：平均 TTFT、平均 TPOT、输出吞吐、总吞吐。填充轮不计入性能对比。重新完整复测时使用新的结果目录名，避免 CSV 追加混入旧数据。

- 两轮都直接运行本用例脚本，不加 `--only-prestress`。当前默认跳过脚本内部的 warmup/prestress 阶段，第一轮依靠相同的 64 个测试请求填充缓存；加该选项反而可能不发送任何请求。
- 当前只启用 `16k:3`，完成 64 个请求即结束。部分旧注释和结果目录名仍包含其他场景，以实际执行参数为准。
- 两轮保持模型、tokenizer、seed、请求数和配置一致。重启后用 `/v1/models` 检查就绪，不要先发送这批目标请求预热。重复正式测量也要先完整重启服务。
- `PASS` 不等于“全部命中盘缓存”。需检查实际成功请求数，并结合后端命中统计、盘读取及 miss 日志确认；仅观察到磁盘 I/O 不足以证明全命中。重启清除的是应用内存/GPU 缓存，不会清空操作系统 page cache；两边配置了 Direct I/O，仍需确认生效。
- 原备份中 YRCache 显式关闭 vLLM prefix caching，LMCache 未显式设置；两边的异步加载等策略也不同。报告应保留实际配置及硬件信息，便于解释结果。
- 入库提交 README、`evalscope/`、`lmcache/`、`yrcache/` 中的脚本和配置；不要提交 `results/`、运行日志、缓存数据或真实凭据。

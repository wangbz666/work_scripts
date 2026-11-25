export CUDA_VISIBLE_DEVICES=0
export PYTHONHASHSEED=0
export OMP_NUM_THREADS=4

/test/workdir/.tools/usr/bin/numactl --cpunodebind=0 --membind=0 \
  /test/venv/bin/lmcache server \
  --host 127.0.0.1 \
  --port 5555 \
  --http-host 0.0.0.0 \
  --http-port 18080 \
  --supported-transfer-mode lmcache_driven \
  --chunk-size 256 \
  --max-gpu-workers 1 \
  --max-cpu-workers 4 \
  --l1-size-gb 100 \
  --no-l1-use-lazy \
  --l1-align-bytes 4096 \
  --eviction-policy LRU \
  --eviction-trigger-watermark 0.95 \
  --eviction-ratio 0.05 \
  --l2-store-policy default \
  --l2-prefetch-policy retain \
  --l2-prefetch-max-in-flight 8 \
  --l2-adapter '{
    "type": "fs_native",
    "base_path": "/test/data_disk/case1-lmcache",
    "num_workers": 8,
    "use_odirect": true,
    "max_capacity_gb": 0,
    "persist_enabled": true
  }' 


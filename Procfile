storage_broker: storage_broker --listen-addr=0.0.0.0:50051
pageserver: pageserver -D /data/.neon
safekeeper: safekeeper --listen-pg=0.0.0.0:5454 --listen-http='0.0.0.0:7676' --id=1 --broker-endpoint=http://localhost:50051 -D /data/.neon/safekeepers/sk1
compute: sleep 10 && neon_local endpoint create main && neon_local endpoint start main

groups:
  - name: mtproxy
    rules:
      - alert: MTProxyDown
        expr: up{job="mtproxy"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MTProxy is down"
          description: "MTProxy container has been down for more than 1 minute on {{ $labels.instance }}"
      
      - alert: HighMemoryUsage
        expr: container_memory_usage_bytes{container="mtproxy"} / container_spec_memory_limit_bytes{container="mtproxy"} > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MTProxy memory usage > 90%"
          description: "MTProxy memory usage is above 90% for more than 5 minutes"
      
      - alert: HighCPUUsage
        expr: rate(container_cpu_usage_seconds_total{container="mtproxy"}[5m]) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MTProxy CPU usage > 80%"
          description: "MTProxy CPU usage is above 80% for more than 5 minutes"
      
      - alert: TooManyConnections
        expr: sum(rate(node_netstat_Tcp_CurrEstab[5m])) > 1000
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High number of TCP connections"
          description: "More than 1000 active TCP connections detected"
      
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low"
          description: "Disk space is below 10% on {{ $labels.mountpoint }}"
      
      - alert: ServiceRestarted
        expr: changes(container_last_seen{container="mtproxy"}, 5m) > 1
        for: 0m
        labels:
          severity: info
        annotations:
          summary: "MTProxy container restarted"
          description: "MTProxy container has restarted multiple times in the last 5 minutes"

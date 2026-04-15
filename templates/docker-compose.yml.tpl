version: "3.9"

services:
  nginx:
    image: nginx:alpine
    container_name: mtproxy-nginx
    restart: unless-stopped
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./nginx/logs:/var/log/nginx
    networks:
      - mtproxy-net
    depends_on:
      - mtproxy
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.25'
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 10s
      retries: 3

  mtproxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproxy
    restart: unless-stopped
    expose:
      - "3128"
    env_file: .env
    environment:
      - PORT=3128
      - SECRET=${SECRET}
      - TAG=${TAG}
      - TLS_DOMAIN=${TLS_DOMAIN}
    volumes:
      - ./config:/config:ro
      - ./data:/data
    networks:
      - mtproxy-net
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=64m
    cap_drop:
      - ALL
    pids_limit: 50
    deploy:
      resources:
        limits:
          memory: ${MEMORY_LIMIT:-512M}
          cpus: '${CPU_LIMIT:-1.0}'
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "3128"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=9090"
      - "monitoring.enabled=true"

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared-tunnel
    restart: unless-stopped
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN:-}
    volumes:
      - ./cloudflared:/etc/cloudflared:ro
    networks:
      - mtproxy-net
    depends_on:
      - mtproxy
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: '0.1'
    profiles:
      - tunnel

volumes:
  prometheus_data:
  grafana_data:
  alertmanager_data:

networks:
  mtproxy-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16

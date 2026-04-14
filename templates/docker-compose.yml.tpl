version: "3.9"

services:
  mtproxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproxy
    restart: unless-stopped
    network_mode: host
    env_file: .env
    environment:
      - PORT=${PORT}
      - SECRET=${SECRET}
      - TAG=${TAG}
      - TLS_DOMAIN=${TLS_DOMAIN}
    volumes:
      - ./config:/config
      - ./data:/data
    deploy:
      resources:
        limits:
          memory: ${MEMORY_LIMIT:-512M}
          cpus: '${CPU_LIMIT:-1.0}'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "${PORT}"]
      interval: 30s
      timeout: 10s
      retries: 3

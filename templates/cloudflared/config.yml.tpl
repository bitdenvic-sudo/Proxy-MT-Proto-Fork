tunnel: mtproxy-tunnel
credentials-file: /etc/cloudflared/creds.json
protocol: quic

ingress:
  - hostname: ${PROXY_HOSTNAME}
    service: tcp://mtproxy:3128
  - service: http_status:404

#!/usr/bin/env bash
# Reinicia conc_mcp_nbs se o Docker o marcar unhealthy. Roda via cron a cada minuto.
ST=$(docker inspect -f '{{.State.Health.Status}}' conc_mcp_nbs 2>/dev/null)
if [ "$ST" = "unhealthy" ]; then
  echo "$(date '+%F %T') unhealthy -> docker restart" >> /home/thiago/projects/ebd-ia/logs/autoheal.log
  docker restart conc_mcp_nbs >> /home/thiago/projects/ebd-ia/logs/autoheal.log 2>&1
fi

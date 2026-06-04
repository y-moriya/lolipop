#!/bin/bash
# Fetch Apache error log from devcontainer-web-1
LINES=${1:-100}
docker exec devcontainer-web-1 tail -n "$LINES" /var/log/apache2/error.log

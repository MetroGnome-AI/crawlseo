#!/usr/bin/env bash
cd /home/eggers/crawlseo
exec node --env-file=/home/eggers/crawlseo/.env --import tsx mcp/server.ts

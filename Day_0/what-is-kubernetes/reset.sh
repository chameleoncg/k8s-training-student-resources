#!/bin/bash
set -x
docker compose down
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)

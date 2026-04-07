#!/bin/bash
set -x
kind delete cluster --name obscurity-cluster
docker compose down
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)
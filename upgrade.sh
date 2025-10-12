#!/bin/sh

sudo docker-compose pull && sudo docker-compose up -d
sudo docker image prune

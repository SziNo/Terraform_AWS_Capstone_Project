#!/bin/bash
dnf update -y
dnf install -y nginx
systemctl enable nginx
systemctl start nginx

# Kezdőlap az instance ID-vel, hogy látszódjon, melyik instance válaszol
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "Hello from $INSTANCE_ID" > /usr/share/nginx/html/index.html

# Health check végpont az ALB-hoz
echo "OK" > /usr/share/nginx/html/health
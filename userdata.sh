#!/bin/bash
dnf install -y nginx
systemctl enable nginx
systemctl start nginx

# Várj, amíg az IMDS elérhető (max 10 próbálkozás)
TOKEN=""
for i in $(seq 1 10); do
    TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    if [ -n "$TOKEN" ]; then break; fi
    sleep 2
done

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id)

echo "Hello from $INSTANCE_ID" > /usr/share/nginx/html/index.html
echo "OK" > /usr/share/nginx/html/health
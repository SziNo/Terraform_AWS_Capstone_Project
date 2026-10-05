#!/bin/bash
dnf install -y postgresql15-server
postgresql-setup --initdb
sed -i "s/^#listen_addresses = .*/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf
for CIDR in 10.0.4.0/24 10.0.5.0/24 10.0.6.0/24; do
    echo "host all all $CIDR scram-sha-256" >> /var/lib/pgsql/data/pg_hba.conf
done
systemctl enable --now postgresql
sudo -u postgres psql -c "CREATE USER appuser WITH PASSWORD '${db_password}';"
sudo -u postgres psql -c "CREATE DATABASE appdb OWNER appuser;"
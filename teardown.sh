#!/bin/bash
set -e

# Terraform erőforrások törlése
terraform destroy -auto-approve

# Remote state bucket törlése (ha létezik)
BUCKET="szino-terraform-state"
if aws s3 ls "s3://$BUCKET" 2>/dev/null; then
    echo "Törlöm a state bucketet: $BUCKET"
    aws s3 rb "s3://$BUCKET" --force
else
    echo "Nincs $BUCKET bucket, kihagyom."
fi

echo "Teardown kész."
#!/usr/bin/env bash
# Helper script to manage DynamoDB terraform locks

set -euo pipefail

OPERATION="${1:?Operation required: list|info|cleanup}"
ENVIRONMENT="${2:?Environment required: prod|staging}"
ORG="${ORG:-ffreis}"
REGION="${AWS_REGION:-us-east-1}"

TABLE="${ORG}-tf-locks-${ENVIRONMENT}"

case "$OPERATION" in
  list)
    echo "Listing locks in $TABLE..."
    aws dynamodb scan \
      --table-name "$TABLE" \
      --region "$REGION" \
      --output table
    ;;
  info)
    echo "Lock table information for $TABLE..."
    aws dynamodb describe-table \
      --table-name "$TABLE" \
      --region "$REGION" \
      --query 'Table.[TableName,TableStatus,ItemCount,BillingModeSummary.BillingMode]' \
      --output table
    ;;
  cleanup)
    echo "⚠ WARNING: This will remove locks older than specified age"
    read -p "Days old (default 1): " -r DAYS
    DAYS="${DAYS:-1}"
    CUTOFF=$(date -d "$DAYS days ago" +%s)
    
    # Get all locks and filter by timestamp
    aws dynamodb scan \
      --table-name "$TABLE" \
      --region "$REGION" \
      --output json | \
    jq -r '.Items[] | select(.Timestamp.N | tonumber < '$CUTOFF') | .ID.S' | \
    while read -r lock_id; do
      echo "Removing lock: $lock_id"
      aws dynamodb delete-item \
        --table-name "$TABLE" \
        --region "$REGION" \
        --key "{\"ID\": {\"S\": \"$lock_id\"}}"
    done
    echo "✓ Cleanup complete"
    ;;
  *)
    echo "Unknown operation: $OPERATION"
    echo "Usage: $0 {list|info|cleanup} {prod|staging}"
    exit 1
    ;;
esac

#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   export N8N_BASE_URL="https://your-n8n.example.com"
#   export N8N_API_KEY="<your n8n public api key>"
#   ./n8n/scripts/apply_via_n8n_api.sh

: "${N8N_BASE_URL:?N8N_BASE_URL is required}"
: "${N8N_API_KEY:?N8N_API_KEY is required}"

WORKFLOW_FILE="n8n/limbo-semi-auto-workflow.json"
NAME="Limbo Semi-Auto Session Manager"

if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "Workflow file not found: $WORKFLOW_FILE" >&2
  exit 1
fi

# 1) Find existing workflow by exact name
EXISTING_ID="$(curl -sS \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  "${N8N_BASE_URL%/}/api/v1/workflows" | \
  jq -r --arg NAME "$NAME" '.data[]? | select(.name==$NAME) | .id' | head -n1)"

# 2) Prepare payload from local export
PAYLOAD="$(jq -c '{name,nodes,connections,settings}' "$WORKFLOW_FILE")"

if [[ -n "${EXISTING_ID}" && "${EXISTING_ID}" != "null" ]]; then
  echo "Updating existing workflow id=${EXISTING_ID} ..."
  curl -sS -X PUT \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "$PAYLOAD" \
    "${N8N_BASE_URL%/}/api/v1/workflows/${EXISTING_ID}" | jq '{id,name,active}'
else
  echo "Creating new workflow ..."
  curl -sS -X POST \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "$PAYLOAD" \
    "${N8N_BASE_URL%/}/api/v1/workflows" | jq '{id,name,active}'
fi

echo "Done."

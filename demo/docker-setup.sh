#!/usr/bin/env bash
set -euo pipefail

# Setup script for DataStax Kafka Sink Connector with Astra
# This script prepares and deployes the connector via docker-compose

# Ensure we're in the project root directory
if [ ! -f "docker-compose.yml" ]; then
  echo "ERROR: Please run this script from the project root directory (where docker-compose.yml is located)"
  exit 1
fi

if [ ! -f "demo/.env" ]; then
  echo "ERROR: demo/.env file not found."
  echo "Please copy demo/.env.example to demo/.env and fill in your values:"
  echo "  cp demo/.env.example demo/.env"
  echo "  # Then edit demo/.env with your Confluent Cloud and Astra details"
  exit 1
fi

set -a
source demo/.env
set +a

: "${KAFKA_BOOTSTRAP_SERVERS:?Please set KAFKA_BOOTSTRAP_SERVERS in demo/.env (e.g., <bootstrap-server>)}"
: "${KAFKA_TOPIC:?Please set KAFKA_TOPIC in demo/.env}"
: "${CONNECT_CONFIG_STORAGE_TOPIC:?Please set CONNECT_CONFIG_STORAGE_TOPIC in demo/.env}"
: "${CONNECT_OFFSET_STORAGE_TOPIC:?Please set CONNECT_OFFSET_STORAGE_TOPIC in demo/.env}"
: "${CONNECT_STATUS_STORAGE_TOPIC:?Please set CONNECT_STATUS_STORAGE_TOPIC in demo/.env}"
: "${ASTRA_DB_ID:?Please set ASTRA_DB_ID in demo/.env}"
: "${ASTRA_DB_KEYSPACE:?Please set ASTRA_DB_KEYSPACE in demo/.env}"
: "${ASTRA_TOKEN:?Please set ASTRA_TOKEN in demo/.env}"
: "${ASTRA_SECURE_BUNDLE:?Please set ASTRA_SECURE_BUNDLE in demo/.env to your Astra secure bundle zip file path}"
: "${CONNECTOR_NAME:?Please set CONNECTOR_NAME in demo/.env}"
: "${CONNECTOR_CONFIG_FILE:?Please set CONNECTOR_CONFIG_FILE in demo/.env}"

CONNECT_GROUP_ID="${CONNECT_GROUP_ID:-compose-group}"
CONNECTOR_CONSUMER_GROUP_PREFIX="connect-${CONNECTOR_NAME}"
CONFLUENT_SERVICE_ACCOUNT_ID="${CONFLUENT_SERVICE_ACCOUNT_ID:-}"

printf "\n=== Checking prerequisites ===\n"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed. Install Docker and retry."
  exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker-compose or Docker Compose v2 is not installed."
  exit 1
fi

printf "\n=== Preparing Astra secure connect bundle ===\n"
if [ ! -f "$ASTRA_SECURE_BUNDLE" ]; then
  echo "ERROR: Astra secure connect bundle not found at '$ASTRA_SECURE_BUNDLE'"
  echo "Please set ASTRA_SECURE_BUNDLE in demo/.env to the path of your downloaded bundle zip file"
  exit 1
fi
BUNDLE_DIR="secure-connect-bundle"
mkdir -p "$BUNDLE_DIR"
cp -f "$ASTRA_SECURE_BUNDLE" "$BUNDLE_DIR/secure-connect-bundle.zip"
echo "Secure bundle copied to $BUNDLE_DIR/secure-connect-bundle.zip"

if command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  COMPOSE_CMD="docker compose"
fi

printf "\n=== Building Kafka Connect image with DataStax plugin ===\n"
$COMPOSE_CMD build kafka-connect

printf "\n=== Creating Kafka topics ===\n"
if command -v confluent >/dev/null 2>&1; then
  create_topic() {
    local topic_name="$1"
    echo "Ensuring topic $topic_name exists..."
    confluent kafka topic create "$topic_name" --partitions 1 --config retention.ms=604800000 || true
  }

  create_topic "$KAFKA_TOPIC"
  create_topic "$CONNECT_CONFIG_STORAGE_TOPIC"
  create_topic "$CONNECT_OFFSET_STORAGE_TOPIC"
  create_topic "$CONNECT_STATUS_STORAGE_TOPIC"

  printf "\n=== Creating Kafka ACLs ===\n"
  if [ -n "$CONFLUENT_SERVICE_ACCOUNT_ID" ] && [ "$CONFLUENT_SERVICE_ACCOUNT_ID" != "your-service-account-id" ]; then
    acl_exists_for_topic() {
      local topic_name="$1"
      local acl_output
      acl_output="$(confluent kafka acl list --service-account "$CONFLUENT_SERVICE_ACCOUNT_ID" --topic "$topic_name" 2>/dev/null || true)"
      printf '%s' "$acl_output" | grep -qi "read" && \
        printf '%s' "$acl_output" | grep -qi "write" && \
        printf '%s' "$acl_output" | grep -qi "describe"
    }

    acl_exists_for_group() {
      local group_name="$1"
      local prefix_flag="${2:-}"
      local acl_output
      acl_output="$(confluent kafka acl list --service-account "$CONFLUENT_SERVICE_ACCOUNT_ID" --consumer-group "$group_name" $prefix_flag 2>/dev/null || true)"
      printf '%s' "$acl_output" | grep -qi "read" && printf '%s' "$acl_output" | grep -qi "describe"
    }

    create_topic_acl() {
      local topic_name="$1"
      if acl_exists_for_topic "$topic_name"; then
        echo "ACL READ,WRITE,DESCRIBE on topic $topic_name already exists for service account $CONFLUENT_SERVICE_ACCOUNT_ID."
        return
      fi
      echo "Ensuring ACL READ,WRITE,DESCRIBE on topic $topic_name for service account $CONFLUENT_SERVICE_ACCOUNT_ID..."
      confluent kafka acl create \
        --allow \
        --service-account "$CONFLUENT_SERVICE_ACCOUNT_ID" \
        --operations read,write,describe \
        --topic "$topic_name" || true
    }

    create_group_acl() {
      local group_name="$1"
      local prefix_flag="${2:-}"
      local group_label="$group_name"
      if [ -n "$prefix_flag" ]; then
        group_label="$group_name*"
      fi
      if acl_exists_for_group "$group_name" "$prefix_flag"; then
        echo "ACL READ,DESCRIBE on consumer group $group_label already exists for service account $CONFLUENT_SERVICE_ACCOUNT_ID."
        return
      fi
      echo "Ensuring ACL READ,DESCRIBE on consumer group $group_label for service account $CONFLUENT_SERVICE_ACCOUNT_ID..."
      confluent kafka acl create \
        --allow \
        --service-account "$CONFLUENT_SERVICE_ACCOUNT_ID" \
        --operations read,describe \
        --consumer-group "$group_name" \
        $prefix_flag || true
    }

    create_topic_acl "$KAFKA_TOPIC"
    create_topic_acl "$CONNECT_CONFIG_STORAGE_TOPIC"
    create_topic_acl "$CONNECT_OFFSET_STORAGE_TOPIC"
    create_topic_acl "$CONNECT_STATUS_STORAGE_TOPIC"
    create_group_acl "$CONNECT_GROUP_ID"
    create_group_acl "$CONNECTOR_CONSUMER_GROUP_PREFIX" "--prefix"
  else
    echo "WARNING: CONFLUENT_SERVICE_ACCOUNT_ID is not set in demo/.env, skipping ACL creation."
    echo "Set CONFLUENT_SERVICE_ACCOUNT_ID to the service account used by your Kafka API key to create ACLs automatically."
  fi
else
  echo "WARNING: Confluent CLI not available, skipping topic creation."
  echo "Please create these topics manually if they do not already exist:"
  echo "  - $KAFKA_TOPIC"
  echo "  - $CONNECT_CONFIG_STORAGE_TOPIC"
  echo "  - $CONNECT_OFFSET_STORAGE_TOPIC"
  echo "  - $CONNECT_STATUS_STORAGE_TOPIC"
  echo "ACLs were also skipped."
fi

printf "\n=== Starting Docker Compose stack ===\n"
$COMPOSE_CMD up -d

printf "\n=== Waiting for Kafka Connect to start ===\n"
for _ in $(seq 1 30); do
  if curl -fsS http://localhost:8083/connector-plugins >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

printf "\n=== Verifying DataStax Kafka Connector plugin availability ===\n"
curl -s -X PUT -H "Content-Type: application/json" \
  http://localhost:8083/connector-plugins/com.datastax.oss.kafka.sink.CassandraSinkConnector/config/validate \
  -d '{}' | head -20 || echo "Connector plugin not yet available, but image build should contain it."

printf "\n=== Deploying Astra sink connector ===\n"
RENDERED_CONNECTOR_CONFIG="$(mktemp)"
RENDERED_CONNECTOR_PAYLOAD="$(mktemp)"
CONNECTOR_NAME_FILE="$(mktemp)"
trap 'rm -f "$RENDERED_CONNECTOR_CONFIG" "$RENDERED_CONNECTOR_PAYLOAD" "$CONNECTOR_NAME_FILE"' EXIT
python3 - <<'PY' > "$RENDERED_CONNECTOR_CONFIG"
import os
from pathlib import Path
from string import Template

template_path = Path(os.environ["CONNECTOR_CONFIG_FILE"])
template = Template(template_path.read_text())
print(template.substitute(os.environ))
PY

python3 - <<'PY' "$RENDERED_CONNECTOR_CONFIG" "$RENDERED_CONNECTOR_PAYLOAD" "$CONNECTOR_NAME_FILE"
import json
import sys
from pathlib import Path

rendered_path = Path(sys.argv[1])
payload_path = Path(sys.argv[2])
name_path = Path(sys.argv[3])

doc = json.loads(rendered_path.read_text())
name_path.write_text(doc["name"])
payload_path.write_text(json.dumps(doc["config"]))
PY

CONNECTOR_DEPLOY_NAME="$(cat "$CONNECTOR_NAME_FILE")"
echo "Deploying connector $CONNECTOR_DEPLOY_NAME"

CONNECT_RESPONSE_FILE="$(mktemp)"
CONNECT_HTTP_CODE="$(
  curl -sS -o "$CONNECT_RESPONSE_FILE" -w "%{http_code}" \
    -X PUT \
    -H "Content-Type: application/json" \
    --data @"$RENDERED_CONNECTOR_PAYLOAD" \
    "http://localhost:8083/connectors/$CONNECTOR_DEPLOY_NAME/config"
)"

cat "$CONNECT_RESPONSE_FILE" | jq . 2>/dev/null || cat "$CONNECT_RESPONSE_FILE"

if [ "$CONNECT_HTTP_CODE" -lt 200 ] || [ "$CONNECT_HTTP_CODE" -ge 300 ]; then
  echo "ERROR: Failed to deploy connector $CONNECTOR_DEPLOY_NAME (HTTP $CONNECT_HTTP_CODE)"
  exit 1
fi

printf "\n=== Setup complete ===\n"
printf "Kafka Connect REST API: http://localhost:8083\n"
printf "Check connector status with: curl http://localhost:8083/connectors/%s/status\n" "$CONNECTOR_NAME"

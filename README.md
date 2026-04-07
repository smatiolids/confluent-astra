# Kafka → DataStax AstraDB Demo

This demo shows how to connect Kafka to DataStax AstraDB using the DataStax Kafka Sink Connector. It includes guidance for installing the connector, creating topics and tables, and choosing the best deployment method for each resource.

## What this demo covers

- Deploying an AstraDB keyspace and table
- Creating Kafka topics for sink ingestion
- Installing the DataStax Cassandra Sink Connector
- Configuring the connector for AstraDB
- Recommended deployment patterns: Terraform, CLI, API

## Prerequisites

- A running Kafka Connect cluster (self-managed Confluent Platform, Confluent Cloud, or Kafka Connect standalone)
- A DataStax AstraDB database and token
- `confluent` CLI installed for topic and connector management
- `astra` CLI installed for Astra database and schema management
- Python 3.8+ with virtual environment support
- Optionally: `terraform` for repeatable infrastructure deployment

### Install the Confluent CLI

macOS (Homebrew):

```bash
brew install confluentinc/tap/cli
```

After installation, log in to your Confluent environment:

```bash
confluent login
```

If you use Confluent Cloud, select the correct environment and Kafka cluster before creating topics or deploying connectors:

```bash
confluent environment list
confluent environment use <environment-id>
confluent kafka cluster list
confluent kafka cluster use <kafka-cluster-id>
```

Use the selected Kafka cluster ID as `CONFLUENT_CLUSTER_ID` in `demo/.env`.

### Install the Astra CLI

Astra CLI install guide: [https://docs.datastax.com/en/astra-cli/install.html]

macOS:

```bash
curl -sSL https://ibm.biz/astra-cli | sh
echo 'eval "$(~/.astra/cli/astra shellenv)"' >> ~/.zprofile
```
Renew your terminal and test:

```bash
astra
```

Generate a  token on the Astra Dashboard

Authenticate the Astra CLI with your token from the Astra web console with:

```bash
astra setup
```

## 1. Create AstraDB keyspace and table

### Option A: Use the Astra CLI / web console

1. Log in to AstraDB.
2. Create a database.
3. Open the database's CQL console or use the `cqlsh` workflow.
4. Create the keyspace and table.

Example CQL:

```sql
CREATE KEYSPACE IF NOT EXISTS astra_demo 
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};

CREATE TABLE IF NOT EXISTS astra_demo.messages (
  id uuid PRIMARY KEY,
  event_time timestamp,
  payload text
);
```

### Option B: Use Terraform for Astra resources

For production and repeatable deployments, Terraform is the preferred option. Use Terraform to manage:

- Astra database and keyspace
- Kafka topics
- Connector configuration artifacts (where supported)

Terraform reduces manual drift and makes the demo reproducible.

> Note: The exact Terraform provider names may change over time. Use the official DataStax/Astra and Confluent providers for your environment.

### Option C: Use Astra REST / API

Astra provides REST/GraphQL APIs to create and manage resources programmatically. Use this approach if you want automation from a service or CI pipeline.

## 2. Deploy Kafka topics

### Option A: Confluent CLI

```bash
confluent kafka topic create <topic-name> --partitions 1
```

### Option B: Kafka CLI

```bash
kafka-topics.sh --bootstrap-server <bootstrap-server> \
  --create --topic astra_demo_topic --partitions 3 --replication-factor 3
```

### Option C: Terraform for Kafka topics

Use Terraform when you want topic creation to be versioned and repeatable. This is the best choice for production or demo environments that should be reconstructed reliably.

## 3. Install the DataStax Kafka Sink Connector

### Confluent Platform / Kafka Connect standalone

Install the connector with the Confluent CLI plugin installer:

```bash
confluent connect plugin install datastax/kafka-connect-cassandra-sink:1.4.0
```

If you are using a connector package manager or a custom Connect image, install the DataStax connector plugin into the `plugins` directory used by Connect.

### Confluent Cloud

If you are using Confluent Cloud, install the connector from the Confluent Cloud UI or use the connector catalog.

### Use Docker Compose (Recommended for demo)

You have two options:

#### Option 1: Lightweight - Kafka Connect only (connects to Confluent Cloud)

Run Kafka Connect as a single container connecting to your Confluent Cloud Kafka cluster.

**Prerequisites:**
- Docker installed
- Confluent Cloud Kafka bootstrap servers and API credentials
- Astra secure connect bundle

**Setup:**

1. Download the Astra secure connect bundle from your Astra console.

2. **Create and configure your environment file:**
   ```bash
   cp demo/.env.example demo/.env
   # Edit demo/.env with your actual values
   ```

3. Set these variables in `demo/.env`:
   ```bash
   CONFLUENT_CLUSTER_ID=<your-kafka-cluster-id>
   KAFKA_BOOTSTRAP_SERVERS=pkc-xxx.region.provider.confluent.cloud:9092
   CONFLUENT_API_KEY=your-api-key
   CONFLUENT_API_SECRET=your-api-secret
   ASTRA_SECURE_BUNDLE=/path/to/secure-connect-database.zip
   ASTRA_TOKEN=your-astra-token
   ```

4. Log in to Confluent Cloud and select the target environment and Kafka cluster:
   ```bash
   confluent login
   confluent environment use <environment-id>
   confluent kafka cluster use <kafka-cluster-id>
   ```

5. Start Kafka Connect only:
   ```bash
   docker-compose up -d kafka-connect
   ```

6. Install and deploy the DataStax connector:
   ```bash
   bash demo/docker-setup.sh
   ```

7. Produce test messages (uses your Confluent Cloud cluster):
   ```bash
   source venv/bin/activate
   python demo/produce_messages.py
   ```

#### Option 2: Full local stack - Zookeeper + Kafka + Connect

For testing with a completely local Kafka cluster, uncomment the `zookeeper` and `kafka` services in `docker-compose.yml`:

```bash
# In docker-compose.yml, uncomment the zookeeper and kafka sections
docker-compose up -d
bash demo/docker-setup.sh
```

Then produce messages to the local topic from the Python producer.

**Key difference:**
- **Option 1 (recommended)**: Only Connect runs in Docker. Your Kafka and topics are in Confluent Cloud.
- **Option 2**: Everything (Zookeeper, Kafka, Connect) runs locally. Good for isolated testing.

**Cleanup:**
```bash
# Stop and remove volumes (keep secure bundle for reuse)
docker-compose down -v

# Full cleanup including bundle
bash demo/docker-cleanup.sh
```

### Use the CLI-based install script

For integration with Confluent Cloud or self-managed Kafka:



## 4. Configure the connector for AstraDB

Create a connector configuration file such as `demo/connector-astra-sink.json`.

### Basic connector configuration example

```json
{
  "name": "astra-sink-connector",
  "config": {
    "connector.class": "com.datastax.oss.kafka.sink.CassandraSinkConnector",
    "tasks.max": "1",
    "topics": "astra_demo_topic",
    "keyspace": "astra_demo",
    "table.name": "messages",
    "contactPoints": "<astra-cql-endpoint>:29042",
    "auth.username": "token",
    "auth.password": "<astra-token>",
    "ssl": "true",
    "ssl.hostname.verification": "true",
    "ssl.truststore.location": "/path/to/truststore.jks",
    "ssl.truststore.password": "<truststore-password>",
    "loadBalancing.localDc": "<your-dc>",
    "insert.mode": "insert",
    "consistency.level": "LOCAL_QUORUM"
  }
}
```

### Astra secure connect bundle option

If Astra provides a secure connect bundle, use the bundle instead of raw contact points:

```json
{
  "connector.class": "com.datastax.oss.kafka.sink.CassandraSinkConnector",
  "tasks.max": "1",
  "topics": "astra_demo_topic",
  "keyspace": "astra_demo",
  "table.name": "messages",
  "cloud.secureConnectBundle": "/path/to/secure-connect-database.zip",
  "auth.username": "token",
  "auth.password": "<astra-token>",
    "insert.mode": "insert",
  "consistency.level": "LOCAL_QUORUM"
}
```

> Replace placeholders with your Astra connection details and token.

## 5. Start the connector

If you are running standalone Connect:

```bash
curl -X POST -H "Content-Type: application/json" \
  --data @demo/connector-astra-sink.json \
  http://localhost:8083/connectors
```

For distributed Connect, use the same REST endpoint on the cluster.

## 6. Produce test data to Kafka

Use the Kafka console producer to send sample records.

```bash
kafka-console-producer.sh --broker-list <bootstrap-server> --topic astra_demo_topic
{"id":"9f0f0e9a-8d5e-4f7a-9f19-df4002c38359","event_time":"2026-04-06T12:00:00Z","payload":"hello astra"}
```


### Use the Python producer script

This repo includes a Python script for producing test messages using the kafka-python library.

1. Activate the virtual environment:
   ```bash
   source venv/bin/activate
   ```
2. Run the producer script:
   ```bash
   python demo/produce_messages.py
   ```

The script reads environment variables from `demo/.env` and produces sample JSON messages to the configured Kafka topic.
If the connector uses a JSON or AVRO converter, adapt the producer accordingly.

## 7. Verify data in AstraDB

Query the table using the Astra CQL console, `cqlsh` with secure bundle, or the Astra web console.

```sql
SELECT * FROM astra_demo.messages LIMIT 10;
```

## Best practice: topics and tables deployment

- `Terraform`: Best for repeatable, reliable deployment in production or shared demo environments.
- `CLI`: Best for quick validation, local development, and interactive debugging.
- `API`: Best for automation and integration with CI/CD pipelines.

### Recommended approach
- `demo/produce_messages.py` — Python script to produce test messages to Kafka
- `venv/` — Python virtual environment (created by `python3 -m venv venv`)
- `requirements.txt` — Python dependencies (generated by pip freeze)

1. Use Terraform to define and version:
   - Astra keyspace/table
   - Kafka topics
   - Connector deployment where supported
2. Use CLI for fast iterative work during development.
3. Use API calls when you need to embed setup into a service or automation script.

## Files in this demo

- `README.md` — this guide
- `docker-compose.yml` — Docker Compose setup for Kafka, Zookeeper, and Kafka Connect
- `demo/create-table.cql` — sample Astra CQL for keyspace and table creation
- `demo/connector-astra-sink.json` — sample connector configuration file for Astra
- `demo/install-astra-sink.sh` — install script for Confluent and Astra CLI-based deployment
- `demo/docker-setup.sh` — setup script for Docker Compose deployment
- `demo/docker-cleanup.sh` — cleanup script to stop Docker Compose and remove volumes
- `demo/.env.example` — environment variable template for the install scripts
- `demo/produce_messages.py` — Python script to produce test messages to Kafka
- `venv/` — Python virtual environment
- `requirements.txt` — Python dependencies
- `.gitignore` — ignore sensitive files and generated artifacts

## Notes

- Always keep Astra tokens secret and avoid committing them into source control.
- If you need a fully managed demo, combine Confluent Cloud with Astra and use Terraform for both sides.
- For production, deploy Kafka topics and Astra schema through infrastructure as code, and use the connector config as code or template files.

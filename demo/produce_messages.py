#!/usr/bin/env python3
"""
Kafka Producer Script for Astra Demo

This script produces sample messages to the Kafka topic defined in demo/.env.
It uses the kafka-python library to connect to Confluent Cloud.

Prerequisites:
- demo/.env file with required variables
- Kafka topic created (use demo/install-astra-sink.sh)
- Python venv activated (source venv/bin/activate)

Usage:
    python demo/produce_messages.py
"""

import json
import os
import uuid
from datetime import datetime
from dotenv import load_dotenv
from kafka import KafkaProducer

# Load environment variables from demo/.env
load_dotenv(dotenv_path='demo/.env')

# Required environment variables
CONFLUENT_CLUSTER_ID = os.getenv('CONFLUENT_CLUSTER_ID')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC')
CONFLUENT_API_KEY = os.getenv('CONFLUENT_API_KEY')
CONFLUENT_API_SECRET = os.getenv('CONFLUENT_API_SECRET')
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS') or os.getenv('CONFLUENT_BOOTSTRAP_SERVERS')

if not all([KAFKA_TOPIC, CONFLUENT_API_KEY, CONFLUENT_API_SECRET, KAFKA_BOOTSTRAP_SERVERS]):
    print("ERROR: Missing required environment variables. Check demo/.env")
    exit(1)

# Kafka producer configuration for Confluent Cloud
producer = KafkaProducer(
    bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS.split(','),
    security_protocol="SASL_SSL",
    sasl_mechanism="PLAIN",
    sasl_plain_username=CONFLUENT_API_KEY,
    sasl_plain_password=CONFLUENT_API_SECRET,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

def produce_sample_messages(count=5):
    """Produce sample messages to the Kafka topic."""
    for i in range(count):
        message = {
            "id": str(uuid.uuid4()),
            "event_time": datetime.utcnow().isoformat() + "Z",
            "payload": f"Sample message {i+1} from Python producer"
        }

        try:
            future = producer.send(KAFKA_TOPIC, value=message)
            record_metadata = future.get(timeout=10)
            print(f"Sent message {i+1}: {message['id']} to topic {record_metadata.topic} partition {record_metadata.partition}")
        except Exception as e:
            print(f"Failed to send message {i+1}: {e}")

    producer.flush()
    producer.close()
    print(f"\nProduced {count} messages to topic '{KAFKA_TOPIC}'")

if __name__ == "__main__":
    print("Starting Kafka producer...")
    produce_sample_messages()
    print("Done.")

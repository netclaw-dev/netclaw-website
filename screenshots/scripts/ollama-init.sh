#!/bin/sh
set -eu

MODEL="${OLLAMA_MODEL:-qwen2:0.5b}"
# Runs in the stack's shared network namespace, so Ollama is on loopback.
OLLAMA="http://127.0.0.1:11434"

echo "Waiting for Ollama API to become available..."
for i in $(seq 1 30); do
  if curl -fsS "$OLLAMA/api/tags" >/dev/null; then
    echo "Ollama is ready."
    break
  fi
  echo "Ollama not ready yet (attempt $i/30)."
  sleep 5
done

echo "Pulling model: $MODEL"
curl -fsS -X POST "$OLLAMA/api/pull" -d "{\"name\":\"$MODEL\"}"

echo "Verifying model is available..."
curl -fsS "$OLLAMA/api/tags"

echo "Model init completed."

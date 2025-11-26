# Cerebros Setup Guide

Complete guide for setting up and configuring the Cerebros Neural Architecture Search (NAS) integration.

## 🎯 Overview

Cerebros is a Python microservice that provides Neural Architecture Search capabilities to Thunderline. It enables automated neural network architecture discovery through evolutionary algorithms and reinforcement learning approaches.

## 📋 Prerequisites

- Python 3.11+
- Elixir 1.18+
- PostgreSQL 14+ (for storing NAS results)
- Thunderline application running

## 🚀 Installation

### 1. Python Service Setup

```bash
# Navigate to the Cerebros service directory
cd thunderhelm/cerebros_service

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Environment Configuration

Add the following to your `.env` file:

```bash
# Cerebros Service Configuration
CEREBROS_SERVICE_URL=http://localhost:5000
CEREBROS_TIMEOUT_MS=30000
CEREBROS_MAX_RETRIES=3
CEREBROS_CACHE_TTL_MS=300000

# Python Service Settings
CEREBROS_LOG_LEVEL=INFO
CEREBROS_WORKERS=4
```

### 3. Feature Flag Activation

The Cerebros integration is controlled by the `CEREBROS_ENABLED` feature flag in `config/config.exs`:

```elixir
config :thunderline, :features,
  CEREBROS_ENABLED: true
```

## 🔧 Configuration Options

### Elixir Configuration

Located in `config/config.exs`:

```elixir
config :thunderline, :cerebros,
  enabled: true,                    # Enable/disable Cerebros integration
  service_url: "http://localhost:5000",  # Python service URL
  timeout_ms: 30_000,              # Request timeout in milliseconds
  max_retries: 3,                  # Max retry attempts for failed requests
  cache_ttl_ms: 300_000            # Cache TTL for NAS results (5 minutes)
```

### Python Service Configuration

The Python service can be configured via environment variables:

- `CEREBROS_SERVICE_URL` - Service URL (default: http://localhost:5000)
- `CEREBROS_LOG_LEVEL` - Logging level (DEBUG, INFO, WARNING, ERROR)
- `CEREBROS_WORKERS` - Number of worker processes (default: 4)

## 🏃 Running the Service

### Development Mode

```bash
# Terminal 1: Start Cerebros Python service
cd thunderhelm/cerebros_service
source .venv/bin/activate
python app.py

# Terminal 2: Start Thunderline
cd /home/mo/DEV/Thunderline
mix phx.server
```

### Production Mode

```bash
# Start Cerebros service with Gunicorn
cd thunderhelm/cerebros_service
gunicorn -w 4 -b 0.0.0.0:5000 app:app

# Start Thunderline in production
cd /home/mo/DEV/Thunderline
MIX_ENV=prod mix phx.server
```

## 🧪 Testing the Connection

Run the connectivity test script:

```bash
mix run scripts/test_cerebros_connection.exs
```

Expected output:
```
🧪 Testing Cerebros Connection
==================================================
Service URL: http://localhost:5000

Test 1: Health Check Endpoint
✅ Health check passed

Test 2: API Version Endpoint
✅ Version check passed

Test 3: Simple NAS Query
✅ NAS query test passed
```

## 🎮 Using the Cerebros Dashboard

Access the Cerebros LiveView dashboard at:

```
http://localhost:4000/cerebros
```

Features:
- Launch NAS runs with custom specifications
- Monitor run status and progress
- View results and metrics
- Download detailed reports
- Cancel running jobs

## 📡 API Endpoints

### Health Check
```
GET /health
```

### API Version
```
GET /api/version
```

### Queue NAS Run
```
POST /api/nas/run
Body: {
  "spec": {...},
  "budget": {...},
  "parameters": {...}
}
```

### Get Run Results
```
GET /api/nas/run/:run_id
```

### Cancel Run
```
DELETE /api/nas/run/:run_id
```

## 🔍 Troubleshooting

### Service Not Responding

1. Check if Python service is running:
   ```bash
   curl http://localhost:5000/health
   ```

2. Check Python service logs:
   ```bash
   tail -f thunderhelm/cerebros_service/logs/cerebros.log
   ```

3. Verify environment variables:
   ```bash
   echo $CEREBROS_SERVICE_URL
   ```

### Connection Timeouts

- Increase `CEREBROS_TIMEOUT_MS` in `.env`
- Check network connectivity between Elixir and Python processes
- Verify no firewall blocking localhost:5000

### NAS Runs Failing

1. Check Oban queue status:
   ```elixir
   Oban.check_queue(queue: :ml)
   ```

2. Review run worker logs:
   ```bash
   grep "RunWorker" _build/dev/logs/*.log
   ```

3. Verify database connection for persistence

## 📊 Monitoring

### Telemetry Events

Cerebros emits telemetry events for:
- `[:thunderline, :cerebros, :run_queued]` - Run queued in Oban
- `[:thunderline, :cerebros, :run_started]` - NAS run started
- `[:thunderline, :cerebros, :run_stopped]` - Run completed successfully
- `[:thunderline, :cerebros, :run_failed]` - Run failed
- `[:thunderline, :cerebros, :trial_started]` - Individual trial started
- `[:thunderline, :cerebros, :trial_stopped]` - Trial completed

### Metrics to Monitor

- Average run duration
- Trial success rate
- Queue processing time
- Cache hit rate
- Error rates by type

## 🔐 Security Considerations

1. **Network Security**: In production, use HTTPS for Cerebros service communication
2. **Authentication**: Add API key authentication for production deployments
3. **Rate Limiting**: Configure rate limits to prevent abuse
4. **Input Validation**: All NAS specifications are validated before processing
5. **Resource Limits**: Set appropriate budget constraints to prevent resource exhaustion

## 📚 Additional Resources

- [Cerebros Architecture Documentation](../THUNDERLINE_DOMAIN_CATALOG.md)
- [Event System Guide](./EVENT_FLOWS.md)
- [Testing Guide](../test/README.md)
- [Deployment Guide](../DEPLOY_DEMO.md)

## 🆘 Support

For issues or questions:
- Check the [Troubleshooting](#troubleshooting) section
- Review logs in `_build/dev/logs/`
- Open an issue in the repository
- Contact the Thunderline team

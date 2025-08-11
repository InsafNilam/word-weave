# Media Service (Python, gRPC)

## Overview

This Media Service is a production-ready gRPC server built in Python. It handles media-related operations and integrates with ImageKit for media storage and delivery.

Key features:

- gRPC server with interceptors for logging and error handling
- Reflection enabled for development environment
- Configurable concurrency and connection options
- Graceful shutdown with signal handling
- Structured logging with `structlog`

---

## Prerequisites

- Python 3.8+
- `pip` package manager
- Protobuf compiler (`protoc`) for generating gRPC code if needed
- Virtual environment tool (`venv`)

---

## Setup

### 1. Create and activate virtual environment

Linux/macOS:

```bash
python3 -m venv venv
source venv/bin/activate
```

Windows PowerShell:

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
```

If you face execution policy errors on Windows, run PowerShell as Administrator and execute:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then reactivate the virtual environment.

---

### 2. Install dependencies

```bash
pip install -r requirements.txt
```

---

### 3. Environment Variables

Configure your environment variables via `.env` file or environment directly.

Important variables:

- `GRPC_HOST` - gRPC server host (e.g., `0.0.0.0`)
- `GRPC_PORT` - gRPC server port (e.g., `50051`)
- `MAX_WORKERS` - Maximum number of worker threads for the server
- `ENVIRONMENT` - Service environment (`development`, `production`, etc.)
- `IMAGEKIT_URL_ENDPOINT` - Endpoint URL for ImageKit integration

---

## Running the Service

Run the main server script:

```bash
python main.py
```

The server starts and listens on the configured host and port. It supports graceful shutdown on SIGINT/SIGTERM.

---

## gRPC Reflection

Reflection is enabled automatically in development mode to allow clients like `grpcurl` to query service metadata.

---

## Logging

Uses `structlog` for structured and human-friendly logs. Logs include startup info, shutdown signals, errors, and important lifecycle events.

---

## Signal Handling and Graceful Shutdown

The server listens to termination signals and shuts down cleanly within a grace period to finish ongoing requests.

---

## Project Structure

```
.
├── main.py                # Entry point for the server
├── requirements.txt       # Python dependencies
├── src/
│   ├── generated/         # Generated protobuf Python files
│   ├── grpc/              # gRPC interceptors
│   ├── services/          # Business logic implementations
│   ├── config/            # Configuration loader and settings
│   └── utils/             # Utility functions (e.g., logging)
└── README.md
```

---

## Troubleshooting

- If you have issues with Python version conflicts (e.g., MSYS interfering on Windows), verify Python version by running:

```bash
python -V
python3 -V
```

- Ensure your virtual environment is properly activated before running.

- If you get permission errors activating venv on Windows, adjust execution policy as shown above.

---

## Useful Commands

```bash
# Activate virtual environment (Linux/macOS)
source venv/bin/activate

# Activate virtual environment (Windows PowerShell)
.\venv\Scripts\Activate.ps1

# Install packages
pip install -r requirements.txt

# Run server
python main.py

# Deactivate environment
deactivate
```

---

## Dependencies

Key dependencies (see `requirements.txt`):

- `grpcio`, `grpcio-tools`, `grpcio-reflection`
- `python-dotenv`
- `pydantic` and `pydantic-settings`
- `structlog`
- `colorama` (for colored logs)
- `flake8`, `mypy` for linting and type checking

---

## Contact

Your Name — [insafnilam.2000@gmail.com](mailto:insafnilam.2000@gmail.com)

---

## License

MIT License

```

```

python -m grpc_tools.protoc \
 -Iproto \
 --python_out=src/generated \
 --grpc_python_out=src/generated \
 proto/media.proto

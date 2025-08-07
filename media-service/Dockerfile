# Build stage for gRPC code generation
FROM python:3.11-slim AS builder

WORKDIR /build

# Install grpcio-tools for protoc
RUN pip install --no-cache-dir grpcio-tools

# Copy proto files and generate gRPC code
COPY proto/ ./proto/
RUN mkdir -p generated \
    && python -m grpc_tools.protoc \
    -I./proto \
    --python_out=./generated \
    --grpc_python_out=./generated \
    ./proto/media.proto \
    && sed -i 's/import media_pb2/from . import media_pb2/g' generated/media_pb2_grpc.py

# Production stage
FROM python:3.11-slim AS production

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

# Install system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Set work directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Copy generated gRPC code from builder
COPY --from=builder /build/generated ./src/generated

# Copy application code
COPY --chown=appuser:appuser . .

# Create necessary directories
RUN mkdir -p /app/logs \
    && chown -R appuser:appuser /app

# Switch to app user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import grpc; channel = grpc.insecure_channel('localhost:50051'); channel.close()" || exit 1

# Expose port
EXPOSE 50051

# Run the application
CMD ["python", "-m", "src.grpc.server"]
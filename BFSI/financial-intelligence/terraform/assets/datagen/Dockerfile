FROM python:3.11-slim

# Install system libraries + ca-certificates for TLS verification
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    librdkafka-dev \
    libpq-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Update the container's trusted root certificate store
RUN update-ca-certificates

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY payments.py .
COPY config.ini .

CMD ["python", "payments.py"]
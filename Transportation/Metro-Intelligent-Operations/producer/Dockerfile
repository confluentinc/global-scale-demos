# Build context is the repo root, not this directory (see docker_image.producer
# in terraform/docker.tf) -- python-producer.py reuses ../metro_network.py at
# runtime, so that file has to land one directory above python-producer.py
# inside the image too, same reasoning as live-map/Dockerfile.
FROM python:3.11-slim

WORKDIR /app

COPY metro_network.py .

COPY producer/requirements.txt producer/requirements.txt
RUN pip install --no-cache-dir -r producer/requirements.txt

COPY producer/ producer/

WORKDIR /app/producer

CMD ["python3", "-u", "python-producer.py"]

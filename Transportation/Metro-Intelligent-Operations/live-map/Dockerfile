# Build context is the repo root, not this directory (see docker_image.live_map
# in terraform/docker.tf) -- server.py reuses YELLOW_LINE/BLUE_LINE/SEGMENT_TIMES
# from ../metro_network.py at runtime, so that file has to land one directory
# above server.py inside the image too. metro_network.py has no Kafka/Schema-
# Registry dependency, unlike python-producer.py, so that's all we need here.
FROM python:3.11-slim

WORKDIR /app

COPY metro_network.py .

COPY live-map/requirements.txt live-map/requirements.txt
RUN pip install --no-cache-dir -r live-map/requirements.txt

COPY live-map/ live-map/

WORKDIR /app/live-map
EXPOSE 8765

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8765"]

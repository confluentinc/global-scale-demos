FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --trusted-host pypi.python.org -r requirements.txt
COPY shopfloor_dashboard.py .
EXPOSE 8050
ENV FLASK_RUN_PORT=8050
ENV FLASK_RUN_HOST=0.0.0.0
CMD ["python", "-u", "shopfloor_dashboard.py"]
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --trusted-host pypi.python.org -r requirements.txt
COPY generate_products.py .
CMD ["python", "-u", "generate_products.py"]
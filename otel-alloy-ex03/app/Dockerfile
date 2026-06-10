FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    opentelemetry-bootstrap -a install

COPY app.py .

# opentelemetry-instrument lance l'app avec l'auto-instrumentation activée
CMD ["opentelemetry-instrument", "python", "app.py"]

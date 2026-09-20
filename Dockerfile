FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

ENV PYTHONUNBUFFERED=1
ENV ADMIN_TOKEN=demo-secret-token
ENV FAULT_MODE=none

EXPOSE 8000

CMD ["python", "-m", "app.main"]

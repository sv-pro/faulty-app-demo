FROM python:3.12-slim

RUN useradd --uid 10001 --no-create-home app
WORKDIR /app
COPY server.py .

USER 10001
EXPOSE 8080
ENV PYTHONDONTWRITEBYTECODE=1
CMD ["python", "-u", "server.py"]

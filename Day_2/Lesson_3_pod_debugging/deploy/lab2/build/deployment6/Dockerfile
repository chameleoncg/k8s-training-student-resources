FROM python:3.12-slim

WORKDIR /app
COPY src/app.py /app/app.py
COPY src/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]

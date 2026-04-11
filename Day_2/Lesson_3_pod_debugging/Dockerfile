FROM gcr.io/distroless/python3-debian12:nonroot

WORKDIR /app
COPY src/app.py /app/app.py

ENTRYPOINT ["/usr/bin/python3.11", "/app/app.py"]

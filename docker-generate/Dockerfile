FROM python:3.12-slim

WORKDIR /work

# Copy the generator script into the image; the host project will be mounted on /work at runtime
COPY scripts/generate_compose.py /usr/local/bin/generate_compose.py
RUN chmod +x /usr/local/bin/generate_compose.py

ENTRYPOINT ["python3", "/usr/local/bin/generate_compose.py"]

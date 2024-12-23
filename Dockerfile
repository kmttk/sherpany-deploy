FROM python:3.9-slim

# Create virtual environment and install curl
ENV VIRTUAL_ENV=/opt/venv
RUN apt-get update && \
    apt-get install -y curl && \
    python -m venv $VIRTUAL_ENV && \
    rm -rf /var/lib/apt/lists/*
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /app

COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY source/ .

RUN groupadd -g 1000 customgroup && \
    useradd -m -u 1000 -g customgroup -s /bin/bash customuser && \
    chown -R customuser:customgroup /app

USER customuser

HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:5000/health || exit 1

EXPOSE 5000

CMD ["python", "app.py"]
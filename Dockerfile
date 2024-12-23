FROM python:3.9-slim as builder

# Set working directory for build
WORKDIR /build

# Create and activate virtual environment
ENV VIRTUAL_ENV=/build/venv
RUN python -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Final stage
FROM python:3.9-slim

# Install curl for healthcheck
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Copy virtual environment from builder
ENV VIRTUAL_ENV=/opt/venv
COPY --from=builder /build/venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Set working directory
WORKDIR /app

# Copy application code
COPY source/ .

# Create non-root user
RUN groupadd -g 1000 customgroup && \
    useradd -m -u 1000 -g customgroup -s /bin/bash customuser && \
    chown -R customuser:customgroup /app

USER customuser

HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:5000/health || exit 1

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
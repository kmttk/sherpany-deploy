FROM python:3.9-slim as builder

WORKDIR /build
COPY requirements.txt .

# Create and activate virtual environment
RUN python -m venv /build/venv && \
    /build/venv/bin/pip install --no-cache-dir -r requirements.txt && \
    /build/venv/bin/pip install --no-cache-dir gunicorn

FROM python:3.9-slim

WORKDIR /app

# Copy venv from builder
COPY --from=builder /build/venv /app/venv
ENV PATH="/app/venv/bin:$PATH"

# Copy application code
COPY . .

# Create non-root user
RUN groupadd -g 1000 appgroup && \
    useradd -u 1000 -g appgroup -s /bin/bash appuser && \
    chown -R appuser:appgroup /app

USER appuser

HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:5000/health || exit 1

EXPOSE 5000

CMD ["/app/venv/bin/gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
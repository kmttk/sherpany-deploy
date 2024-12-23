FROM python:3.9-slim

WORKDIR /app

COPY source/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY source/ .

RUN groupadd -g 1000 customgroup && \
    useradd -m -u 1000 -g customgroup -s /bin/bash customuser && \
    chown -R customuser:customgroup /app

USER customuser

EXPOSE 8080

CMD ["python", "app.py"]
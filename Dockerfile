FROM python:3.9-slim

WORKDIR /source

COPY requirements.txt .

RUN pip install --no-cache-dir -r /source/requirements.txt

COPY . .

RUN groupadd -g 1000 customgroup && \
    useradd -m -u 1000 -g customgroup -s /bin/bash customuser && \
    chown -R customuser:customgroup /source

USER customuser

EXPOSE 5000

CMD ["python", "app.py"]
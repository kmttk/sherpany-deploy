from flask import Flask, Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import psycopg2
import os
import time

app = Flask(__name__)

# Prometheus metrics
http_requests_total = Counter('http_requests_total', 'Total HTTP requests')
http_request_duration = Histogram('http_request_duration_seconds', 'HTTP request duration')
db_query_duration = Histogram('db_query_duration_seconds', 'Database query duration')

def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        database=os.environ.get('DB_NAME', 'postgres'),
        user=os.environ.get('DB_USER', 'postgres'),
        password=os.environ.get('DB_PASSWORD', 'postgres')
    )

@app.route('/')
@http_request_duration.time()
def hello():
    http_requests_total.inc()
    start_time = time.time()
    
    try:
        with db_query_duration.time():
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute('SELECT 1')
            cur.close()
            conn.close()
    except Exception as e:
        print(f"Database error: {e}")
        
    return 'Hello World!'

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
from flask import Flask, jsonify
import os
import psycopg2
from psycopg2.extras import RealDictCursor
from prometheus_client import Counter, Histogram, generate_latest
import time
import ssl

app = Flask(__name__)

# Prometheus metrics
http_requests_total = Counter('http_requests_total', 'Total HTTP requests')
http_request_duration_seconds = Histogram('http_request_duration_seconds', 'HTTP request duration')
db_query_duration_seconds = Histogram('db_query_duration_seconds', 'Database query duration')

def get_db_connection():
    # Create SSL context for Azure PostgreSQL
    ssl_context = ssl.create_default_context()
    ssl_context.verify_mode = ssl.CERT_REQUIRED

    conn = psycopg2.connect(
        host=os.getenv('DB_HOST'),
        port=os.getenv('DB_PORT', '5432'),
        dbname=os.getenv('DB_NAME'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD'),
        sslmode='require',
        sslcert=None
    )
    return conn

@app.route('/users')
def get_users():
    http_requests_total.inc()
    start_time = time.time()
    
    conn = get_db_connection()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            query_start = time.time()
            cur.execute('SELECT id, name, email FROM users')
            users = cur.fetchall()
            db_query_duration_seconds.observe(time.time() - query_start)
            
            http_request_duration_seconds.observe(time.time() - start_time)
            return jsonify([dict(user) for user in users])
    finally:
        conn.close()

@app.route('/health')
def health_check():
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({"status": "healthy"})
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 500

@app.route('/metrics')
def metrics():
    return generate_latest()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
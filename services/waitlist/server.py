"""Write It Down waitlist collector. Serve only behind the writeitdown.app reverse proxy."""
import argparse
import ipaddress
import json
import re
import sqlite3
import threading
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

EMAIL = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
OUTCOMES = {'joined', 'invalid', 'limited', 'error'}


class Collector(ThreadingHTTPServer):
    def __init__(self, address, db_path, origin):
        super().__init__(address, Handler)
        self.db_path = db_path
        self.origin = origin
        self.attempts = defaultdict(deque)
        self.lock = threading.Lock()
        with self.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS subscribers (email TEXT PRIMARY KEY, joined_at INTEGER NOT NULL)')

    def connect(self):
        return sqlite3.connect(self.db_path, timeout=5)

    def limited(self, address):
        now = time.monotonic()
        with self.lock:
            for key, bucket in list(self.attempts.items()):
                while bucket and bucket[0] <= now - 600:
                    bucket.popleft()
                if not bucket:
                    del self.attempts[key]
            attempts = self.attempts[address]
            if len(attempts) >= 5:
                return True
            attempts.append(now)
            return False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, content, kind='text/plain; charset=utf-8', headers=None):
        data = content.encode()
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path != '/api/waitlist/health':
            return self.reply(404, 'Not found')
        try:
            with self.server.connect() as db:
                db.execute('BEGIN IMMEDIATE')
                db.execute('SELECT 1 FROM subscribers LIMIT 1').fetchone()
                db.execute('ROLLBACK')
            self.reply(200, 'ok')
        except sqlite3.Error:
            self.reply(503, 'Unavailable')

    def client_ip(self):
        peer = ipaddress.ip_address(self.client_address[0])
        if peer.is_loopback and self.headers.get('X-Forwarded-For'):
            try:
                return str(ipaddress.ip_address(self.headers['X-Forwarded-For'].split(',')[0].strip()))
            except ValueError:
                pass
        return str(peer)

    def do_POST(self):
        if self.path != '/api/waitlist':
            return self.reply(404, 'Not found')
        wants_json = 'application/json' in self.headers.get('Accept', '')
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            length = 0
        if self.headers.get('Origin') not in (None, self.server.origin):
            return self.result('invalid', wants_json)
        if self.headers.get('Content-Type', '').split(';')[0] != 'application/x-www-form-urlencoded' or not 0 < length <= 4096:
            return self.result('invalid', wants_json)
        fields = parse_qs(self.rfile.read(length).decode('utf-8', errors='replace'), keep_blank_values=True)
        email = fields.get('email', [''])[0].strip().lower()
        if len(fields.get('email', [])) != 1 or len(email) > 254 or not EMAIL.fullmatch(email) or fields.get('consent') != ['yes']:
            return self.result('invalid', wants_json)
        if self.server.limited(self.client_ip()):
            return self.result('limited', wants_json)
        if any(fields.get('website', [])):
            return self.result('joined', wants_json)
        try:
            with self.server.connect() as db:
                db.execute('INSERT OR IGNORE INTO subscribers (email, joined_at) VALUES (?, ?)', (email, int(time.time())))
        except sqlite3.Error:
            return self.result('error', wants_json)
        self.result('joined', wants_json)

    def result(self, outcome, wants_json):
        assert outcome in OUTCOMES
        if wants_json:
            status = {'joined': 200, 'invalid': 400, 'limited': 429, 'error': 500}[outcome]
            return self.reply(status, json.dumps({'status': outcome}), 'application/json; charset=utf-8')
        self.reply(303, '', headers={'Location': '/mac.html#waitlist-' + outcome})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', required=True)
    parser.add_argument('--listen', default='127.0.0.1:8090')
    parser.add_argument('--origin', default='https://writeitdown.app')
    args = parser.parse_args()
    host, port = args.listen.rsplit(':', 1)
    Collector((host, int(port)), args.db, args.origin).serve_forever()

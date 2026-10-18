import http.client
import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.parse import urlencode

from server import Collector


class CollectorTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = str(Path(self.temp.name) / 'waitlist.sqlite')
        self.server = Collector(('127.0.0.1', 0), self.db, 'https://writeitdown.app')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, method, path, fields=None, accept=None, **headers):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port)
        if fields is not None:
            headers['Content-Type'] = 'application/x-www-form-urlencoded'
            fields = urlencode(fields)
        if accept:
            headers['Accept'] = accept
        connection.request(method, path, body=fields, headers=headers)
        response = connection.getresponse()
        status, location, body = response.status, response.getheader('Location'), response.read().decode()
        connection.close()
        return status, location, body

    def rows(self):
        with sqlite3.connect(self.db) as db:
            return db.execute('SELECT email, joined_at FROM subscribers').fetchall()

    def test_json_consent_duplicate_and_honeypot(self):
        fields = {'email': ' Reader@Example.com ', 'consent': 'yes', 'website': ''}
        status, _, body = self.request('POST', '/api/waitlist', fields, 'application/json')
        self.assertEqual((status, json.loads(body)), (200, {'status': 'joined'}))
        first = self.rows()
        self.assertEqual(first[0][0], 'reader@example.com')
        self.request('POST', '/api/waitlist', fields, 'application/json')
        self.assertEqual(self.rows(), first)
        self.request('POST', '/api/waitlist', {**fields, 'email': 'bot@example.com', 'website': 'spam'}, 'application/json')
        self.assertEqual(self.rows(), first)

    def test_no_js_fragments_validation_and_health(self):
        self.assertEqual(self.request('GET', '/api/waitlist/health'), (200, None, 'ok'))
        self.assertEqual(self.request('POST', '/api/waitlist', {'email': 'a@example.com', 'consent': 'yes'})[:2],
                         (303, '/mac.html#waitlist-joined'))
        self.assertEqual(self.request('POST', '/api/waitlist', {'email': 'b@example.com'})[:2],
                         (303, '/mac.html#waitlist-invalid'))
        self.assertEqual(self.request('POST', '/api/waitlist', {'email': 'bad', 'consent': 'yes'}, 'application/json')[0], 400)
        self.assertEqual(len(self.rows()), 1)

    def test_limit_and_cross_origin(self):
        fields = {'email': 'a@example.com', 'consent': 'yes'}
        status, _, body = self.request('POST', '/api/waitlist', fields, 'application/json', Origin='https://elsewhere.test')
        self.assertEqual((status, json.loads(body)['status']), (400, 'invalid'))
        for n in range(5):
            self.request('POST', '/api/waitlist', {**fields, 'email': f'{n}@example.com'})
        self.assertEqual(self.request('POST', '/api/waitlist', fields)[:2], (303, '/mac.html#waitlist-limited'))
        self.assertEqual(len(self.rows()), 5)

    def test_failure_does_not_claim_signup(self):
        self.server.db_path = str(Path(self.temp.name) / 'missing' / 'db')
        fields = {'email': 'a@example.com', 'consent': 'yes'}
        status, _, body = self.request('POST', '/api/waitlist', fields, 'application/json')
        self.assertEqual((status, json.loads(body)['status']), (500, 'error'))
        self.assertEqual(self.request('GET', '/api/waitlist/health')[0], 503)
        self.assertEqual(self.request('POST', '/api/waitlist', fields)[:2], (303, '/mac.html#waitlist-error'))


if __name__ == '__main__':
    unittest.main()

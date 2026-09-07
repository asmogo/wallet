import json
import unittest

import httpx
from bolt11 import decode
from fastapi.testclient import TestClient
import server
from nostr_client import encode_event


class PaymentFixtureTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(server.app)
        self.client.__enter__()
        self.key = self.client.post('/sessions').json()['id']
        self.root = '/sessions/' + self.key
        self.forwarded = []

        async def upstream(request):
            self.forwarded.append(request)
            return httpx.Response(200, json={'state': 'PAID'})
        self.upstream = httpx.AsyncClient(transport=httpx.MockTransport(upstream))
        server.app.state.client = self.upstream

    def tearDown(self):
        self.client.delete(self.root)
        self.client.__exit__(None, None, None)

    def test_reject_does_not_forward_then_expires(self):
        self.client.post(self.root + '/faults', json={'action': 'reject', 'method': 'POST', 'path': '/v1/melt/bolt11'})
        url = self.root + '/mint/cdk/v1/melt/bolt11'
        self.assertEqual(self.client.post(url, json={}).status_code, 503)
        self.assertEqual(len(self.forwarded), 0)
        self.assertEqual(self.client.post(url, json={}).status_code, 200)
        self.assertEqual(len(self.forwarded), 1)

    def test_lost_response_occurs_after_upstream_commit(self):
        self.client.post(self.root + '/faults', json={'action': 'lose_response', 'method': 'POST', 'path': '/v1/melt/bolt11'})
        with self.assertRaises(Exception):
            self.client.post(self.root + '/mint/cdk/v1/melt/bolt11', json={})
        self.assertEqual(len(self.forwarded), 1)
        record = self.client.get(self.root).json()['requests'][0]
        self.assertTrue(record['forwarded'])
        self.assertEqual(record['status'], 200)

    def test_faults_are_isolated_and_match_method(self):
        other = self.client.post('/sessions').json()['id']
        try:
            self.client.post(self.root + '/faults', json={'action': 'reject', 'method': 'POST', 'path': '/v1/melt'})
            self.assertEqual(self.client.get(self.root + '/mint/cdk/v1/melt/quote/bolt11/one').status_code, 200)
            self.assertEqual(self.client.post('/sessions/' + other + '/mint/cdk/v1/melt/bolt11', json={}).status_code, 200)
        finally:
            self.client.delete('/sessions/' + other)

    def test_invoice_amount_expiry_and_script_are_encoded(self):
        script = json.dumps({'pay_invoice_state': 'PAID', 'check_payment_state': 'PAID', 'pay_err': True, 'check_err': False})
        value = self.client.post(self.root + '/invoice', json={'amount': 21, 'description': script, 'expiry': 1, 'age': 60}).json()['invoice']
        decoded = decode(value)
        self.assertEqual(decoded.amount_msat, 21000)
        self.assertEqual(decoded.description, script)
        self.assertTrue(decoded.has_expired())

    def test_relay_replays_only_matching_session_events(self):
        event = encode_event('0' * 63 + '1', 1059, [['p', 'recipient']], 'ciphertext')
        with self.client.websocket_connect(self.root + '/relay') as ws:
            invalid = dict(event, sig='0' * 128)
            ws.send_json(['EVENT', invalid])
            self.assertFalse(ws.receive_json()[2])
            ws.send_json(['EVENT', event])
            self.assertEqual(ws.receive_json(), ['OK', event['id'], True, ''])
            ws.send_json(['REQ', 'matching', {'kinds': [1059], '#p': ['recipient']}])
            self.assertEqual(ws.receive_json(), ['EVENT', 'matching', event])
            self.assertEqual(ws.receive_json(), ['EOSE', 'matching'])
            ws.send_json(['REQ', 'other', {'#p': ['other']}])
            self.assertEqual(ws.receive_json(), ['EOSE', 'other'])


if __name__ == '__main__':
    unittest.main()

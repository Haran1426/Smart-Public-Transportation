import json
import unittest
from unittest.mock import patch
from urllib.parse import urlencode

import transit_api as relay


class RelayTest(unittest.TestCase):
    def setUp(self):
        env = patch.dict(relay.os.environ, {
            "SEOUL_BUS_KEY": "fixture-bus-private-token",
            "SEOUL_SUBWAY_KEY": "fixture-subway-private-token",
        }, clear=True)
        env.start()
        self.addCleanup(env.stop)
        relay.responses.clear()

    def request(self, path, query="", method="GET"):
        status = []
        reply = relay.app(
            {"PATH_INFO": path, "QUERY_STRING": query, "REQUEST_METHOD": method},
            lambda code, headers: status.append(code),
        )
        return status[0], json.loads(b"".join(reply))

    def test_metro_response_keeps_only_arrival_fields_and_caches(self):
        query = urlencode({"station": "녹사평"})
        upstream = json.dumps({
            "errorMessage": {"code": "INFO-000"},
            "realtimeArrivalList": [{"subwayId": "1006", "extra": "fixture-subway-private-token"}],
        }).encode()
        with patch.object(relay, "read_upstream", return_value=upstream) as fetch:
            status, body = self.request("/v1/subway", query)
            self.assertEqual(status, "200 OK")
            self.assertEqual(body["arrivals"][0]["subwayId"], "1006")
            self.assertNotIn("extra", body["arrivals"][0])
            self.assertEqual(self.request("/v1/subway", query), (status, body))
            fetch.assert_called_once()

    def test_bus_response_is_normalized_and_non_arrival_data_omitted(self):
        upstream = """<ServiceResult><msgHeader><headerCd>0</headerCd></msgHeader>
            <msgBody><itemList><arrmsg1>4분 후</arrmsg1><exps1>240</exps1>
            <vehicleNo>hidden</vehicleNo></itemList></msgBody></ServiceResult>""".encode()
        query = "stopId=102900058&routeId=102900004&order=22"
        with patch.object(relay, "read_upstream", return_value=upstream):
            status, body = self.request("/v1/bus", query)
        self.assertEqual(status, "200 OK")
        self.assertEqual(body["arrival"]["arrmsg1"], "4분 후")
        self.assertNotIn("vehicleNo", body["arrival"])

    def test_bad_query_and_provider_errors_do_not_leak_credentials(self):
        with patch.object(relay, "read_upstream") as fetch:
            status, _ = self.request("/v1/subway", "station=..")
            self.assertTrue(status.startswith("400"))
            fetch.assert_not_called()
        fake_error = b'{"errorMessage":{"code":"INFO-100","message":"fixture-subway-private-token"}}'
        with patch.object(relay, "read_upstream", return_value=fake_error):
            status, body = self.request("/v1/subway", urlencode({"station": "녹사평"}))
        self.assertTrue(status.startswith("503"))
        self.assertEqual(body, {"error": "unavailable"})

    def test_no_service_credential_is_reported_as_unavailable(self):
        with patch.dict(relay.os.environ, clear=True), patch.object(relay, "read_upstream") as fetch:
            status, body = self.request("/v1/subway", urlencode({"station": "녹사평"}))
            self.assertTrue(status.startswith("503"))
            self.assertEqual(body, {"error": "unavailable"})
            fetch.assert_not_called()

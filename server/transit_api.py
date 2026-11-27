"""Public arrivals relay. Provider credentials are supplied by the host."""
from collections import OrderedDict
import json
import os
import re
from socketserver import ThreadingMixIn
from threading import Lock, Semaphore
from time import monotonic
from urllib.parse import parse_qs, quote, urlencode
from urllib.request import HTTPRedirectHandler, build_opener
from wsgiref.simple_server import WSGIServer, make_server
from xml.etree import ElementTree

BODY_LIMIT = 512 * 1024
SUBWAY_FIELDS = (
    "subwayId", "updnLine", "ordkey", "btrainNo", "recptnDt",
    "arvlCd", "arvlMsg2", "barvlDt", "bstatnNm",
)
BUS_FIELDS = ("mkTm", "arrmsg1", "arrmsg2", "exps1", "exps2")
CACHE_LIMIT = 512
CACHE_SECONDS = 12
responses = OrderedDict()
waiting = Lock()
upstream_slots = Semaphore(8)


class UpstreamError(Exception):
    """The provider did not supply a usable arrival response."""


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def read_upstream(url):
    with build_opener(NoRedirects()).open(url, timeout=3) as response:
        data = response.read(BODY_LIMIT + 1)
    if len(data) > BODY_LIMIT:
        raise UpstreamError()
    return data


def subway_arrivals(station, key):
    url = (
        f"http://swopenapi.seoul.go.kr/api/subway/{quote(key, safe='')}"
        f"/json/realtimeStationArrival/0/40/{quote(station, safe='')}"
    )
    data = json.loads(read_upstream(url))
    error = data.get("errorMessage") or data
    code = error.get("code")
    if code == "INFO-200":
        return {"arrivals": []}
    if code != "INFO-000":
        raise UpstreamError()
    rows = data.get("realtimeArrivalList") or []
    return {
        "arrivals": [
            {name: row.get(name) for name in SUBWAY_FIELDS}
            for row in rows[:40]
        ]
    }


def bus_arrivals(stop_id, route_id, order, key):
    query = urlencode({
        "serviceKey": key, "stId": stop_id,
        "busRouteId": route_id, "ord": order,
    })
    raw = read_upstream(f"http://ws.bus.go.kr/api/rest/arrive/getArrInfoByRoute?{query}")
    if b"<!DOCTYPE" in raw.upper():
        raise UpstreamError()
    root = ElementTree.fromstring(raw)
    code = root.findtext("msgHeader/headerCd", "").strip()
    if code == "4":
        return {"arrival": None}
    if code != "0":
        raise UpstreamError()
    row = root.find("msgBody/itemList")
    return {"arrival": None if row is None else
            {name: row.findtext(name, "").strip() for name in BUS_FIELDS}}


def request_arguments(query, rules):
    if len(query) > 1024:
        raise ValueError()
    values = parse_qs(query, strict_parsing=True, max_num_fields=len(rules))
    if values.keys() != rules.keys():
        raise ValueError()
    arguments = []
    for name, pattern in rules.items():
        entries = values[name]
        if len(entries) != 1:
            raise ValueError()
        value = entries[0].strip()
        if value in {".", ".."} or not re.fullmatch(pattern, value):
            raise ValueError()
        arguments.append(value)
    return tuple(arguments)


def encoded(data):
    return json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def response(start_response, status, body):
    start_response(status, [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store"),
    ])
    return [body]


def cached_arrivals(cache_key, lookup, arguments, secret):
    with waiting:
        prior = responses.get(cache_key)
        if prior is not None and prior[0] > monotonic():
            responses.move_to_end(cache_key)
            return prior[1]
    if not upstream_slots.acquire(blocking=False):
        raise UpstreamError()
    try:
        body = encoded(lookup(*arguments, secret))
    finally:
        upstream_slots.release()
    if secret.encode() in body or quote(secret, safe="").encode() in body:
        raise UpstreamError()
    with waiting:
        responses[cache_key] = (monotonic() + CACHE_SECONDS, body)
        responses.move_to_end(cache_key)
        while len(responses) > CACHE_LIMIT:
            responses.popitem(last=False)
    return body


def app(environ, start_response):
    if environ.get("REQUEST_METHOD") != "GET":
        return response(start_response, "405 Method Not Allowed", b'{"error":"method"}')
    path = environ.get("PATH_INFO")
    if path == "/v1/subway":
        lookup, env_name = subway_arrivals, "SEOUL_SUBWAY_KEY"
        rules = {"station": r"[\w .()·,\-]{1,50}"}
    elif path == "/v1/bus":
        lookup, env_name = bus_arrivals, "SEOUL_BUS_KEY"
        rules = {"stopId": r"[0-9]{9}", "routeId": r"[0-9]{9}", "order": r"[0-9]{1,10}"}
    else:
        return response(start_response, "404 Not Found", b'{"error":"not_found"}')
    try:
        args = request_arguments(environ.get("QUERY_STRING", ""), rules)
    except ValueError:
        return response(start_response, "400 Bad Request", b'{"error":"invalid_query"}')
    secret = os.environ.get(env_name, "").strip()
    if not secret:
        return response(start_response, "503 Service Unavailable", b'{"error":"unavailable"}')
    try:
        body = cached_arrivals((path, args), lookup, args, secret)
    except (UpstreamError, OSError, ValueError, TypeError, AttributeError, ElementTree.ParseError):
        return response(start_response, "503 Service Unavailable", b'{"error":"unavailable"}')
    return response(start_response, "200 OK", body)


class DevelopmentServer(ThreadingMixIn, WSGIServer):
    daemon_threads = True


if __name__ == "__main__":
    with make_server(
        "127.0.0.1", int(os.environ.get("PORT", "8765")), app,
        server_class=DevelopmentServer,
    ) as server:
        server.serve_forever()

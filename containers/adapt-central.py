"""Adapt the pinned Central images to the shared NS8 pod and Traefik."""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
frontend = sys.argv[2]


def replace(path, old, new):
    file = root / path
    source = file.read_text()
    if source.count(old) != 1:
        raise ValueError(f"Expected one match for {old!r} in {path}")
    file.write_text(source.replace(old, new))


replace("files/service/config.json.template", '"host": "pyxform",\n      "port": 80',
        '"host": "127.0.0.1",\n      "port": 8081')
replace("files/service/config.json.template", "http://enketo:8005/-", "http://127.0.0.1:8005/-")
replace("service.dockerfile", "WORKDIR /client\nRUN git describe --tags --dirty --always > /tmp/sentry-versions/client",
        f"RUN printf '%s\\n' '{frontend}' > /tmp/sentry-versions/client")
replace("service.dockerfile", "EXPOSE 8383", 'EXPOSE 8383\nCMD ["./start-odk.sh"]')

for name in ("enketo_redis_main", "enketo_redis_cache"):
    replace("files/enketo/config.json.template", f'"host": "{name}"', '"host": "127.0.0.1"')

nginx = "files/nginx/odk.conf.template"
replace(nginx, "listen 443 default_server ssl;", "listen 8080 default_server;")
replace(nginx, "listen 443 ssl;\n  http2 on;", "listen 8080;\n  absolute_redirect off;")
replace(nginx, "http://enketo:8005", "http://127.0.0.1:8005")
replace(nginx, "http://service:8383", "http://127.0.0.1:8383")
replace(nginx, "proxy_set_header X-Forwarded-Proto $scheme;",
        "proxy_set_header X-Forwarded-Proto https;\n    proxy_set_header Host $host;")
replace(nginx, 'proxy_pass https://${SENTRY_ORG_SUBDOMAIN}.ingest.sentry.io/api/${SENTRY_PROJECT}/security/?sentry_key=${SENTRY_KEY};\n    proxy_ssl_server_name on;', "return 204;")
file = root / nginx
file.write_text(re.sub(r"^  ssl_.*\n", "", file.read_text(), flags=re.MULTILINE))
replace("nginx.dockerfile", 'ENTRYPOINT [ "/scripts/setup-odk.sh" ]',
        """COPY files/nginx/odk.conf.template files/nginx/client-config.json.template /usr/share/odk/nginx/
COPY files/nginx/start-ns8.sh /scripts/
ENTRYPOINT ["/scripts/start-ns8.sh"]""")

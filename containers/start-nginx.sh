#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
/scripts/envsub.awk < /usr/share/odk/nginx/client-config.json.template > /usr/share/nginx/html/client-config.json
/scripts/envsub.awk < /usr/share/odk/nginx/odk.conf.template > /etc/nginx/conf.d/odk.conf
rm -f /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'

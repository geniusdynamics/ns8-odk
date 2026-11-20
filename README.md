# ODK Central for NethServer 8

ODK Central hosts forms, field submissions and Entity Lists for ODK Collect and web browsers. The module packages Central, Enketo and the XLSForm converter together with PostgreSQL and two Redis instances. NS8 Traefik handles HTTPS and exposes one route. The database, cache and conversion services are internal to the rootless pod.

## Install

Use an NS8 node running core **3.20.1 or later**. Choose a DNS name for Central and point it at the node. Install a published module image from a cluster shell, replacing the example node ID if needed.

```bash
add-module ghcr.io/geniusdynamics/odk:latest 1
```

The command returns the instance ID, for example `odk1`. In the instance's **Settings**, enter the hostname and the administrator contact email, then choose whether to request a Let's Encrypt certificate. If you leave that option off, configure a trusted certificate in NS8 Traefik before connecting field devices. The module always redirects HTTP to HTTPS.

The equivalent CLI configuration is:

```bash
api-cli run module/odk1/configure-module --data '{
  "host": "odk.example.org",
  "sysadmin_email": "admin@example.org",
  "lets_encrypt": true
}'
```

Use the same canonical hostname on field devices and in web browsers. Enketo must be able to resolve and reach this hostname over HTTPS from the NS8 node. Pick the permanent hostname before distributing Collect settings or public form links.

## Create the first administrator

The email in module Settings is a contact address. Create the first Central account interactively on the instance's node:

```bash
runagent -m odk1 create-admin admin@example.org
```

Enter the initial password at the hidden prompt, then sign in at the Central URL. If the account already exists, grant it administrator access with `runagent -m odk1 podman exec central-app odk-cmd --email admin@example.org user-promote`.

Configure the **NS8 cluster smarthost** for Central's invitation and password-reset email. Use a relay that accepts mail from `no-reply@<Central hostname>`. The CLI can create or reset an administrator password independently of email delivery. See the [ODK user management guide](https://docs.getodk.org/central-users/).

## OpenID Connect sign-in

In NS8 **Settings**, enable **OpenID Connect**. Under **Choose an NS8 provider**, select an identity provider and user domain. NS8 registers the application and its callback. For an external provider, choose **Enter an external provider** and use **Advanced manual OIDC settings**.

For manual setup, enter the HTTPS issuer URL, client ID and client secret. Register the callback shown in Settings, `https://<Central hostname>/v1/oidc/callback`.

Central uses the authorization-code flow with S256 PKCE, RS256, `client_secret_basic` and the `openid email` scopes. The provider must advertise and return the `email` and `email_verified` claims. Each user must already have a Central account with the same verified email. Confirm an existing administrator matches before enabling the switch.

With OIDC enabled, Central uses it for browser sign-in instead of local passwords. Keep access to NS8 Settings. If sign-in fails, turn OIDC off there and sign in with the existing local administrator password. Test a fresh sign-in in a separate browser session before closing your current session.

A blank secret keeps the saved secret for the same issuer and client ID. Changing either requires a new secret. Configure a matching client and callback again if the hostname changes on restore.

## Backup, restore and updates

- An NS8 module backup includes a logical PostgreSQL dump, the Enketo keys and its persistent Redis store. Central keeps submissions and attachments in PostgreSQL in this deployment. The separate Redis cache rebuilds automatically.
- Schedule backups during low activity. PostgreSQL and Enketo are backed up separately. For a controlled maintenance window, stop client submissions and administrative writes before starting the backup.
- For recovery, restore through NS8 and keep the original hostname. Once DNS reaches the destination node, enable certificate issuance there if needed. Verify web login, a Collect project connection, and an existing form link on the restored instance.
- Before updating, run an NS8 backup. Review the [upstream Central release notes](https://github.com/getodk/central/releases) and the module's release notes first. Use the NS8 update action with the published module tag and test existing forms and submissions after updating.

## Build and test

`build-images.sh` builds Central's service, frontend proxy and Enketo images from the pinned [Central release](https://github.com/getodk/central/releases/tag/v2026.3.2), its [backend submodule](https://github.com/getodk/central-backend), and the matching [frontend bundle](https://github.com/getodk/central-frontend/releases/tag/v2026.3.1). It uses the published Pyxform image. Review `containers/adapt-central.py` when bumping the upstream release. It adapts the shared pod's internal addresses and Traefik TLS termination while retaining Central's upstream routes.

The QEMU workflow installs the built image, checks the HTTPS redirect, frontend and API, verifies all supporting containers and checks the logical database export before removing the instance.

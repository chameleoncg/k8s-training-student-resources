# OIDC Lab With An Upstream SAML IdP

Create a local `kind` cluster with:

* Cilium as the CNI and Gateway API controller
* a broker Keycloak running in HTTP dev mode for the app-facing OIDC flow
* a second Keycloak acting as the upstream SAML Identity Provider
* a tiny upstream app (`hashicorp/http-echo`)
* `oauth2-proxy` acting as the OIDC client in front of that app

The broker realm starts with no local end users. To make the sample app login work, students must:

1. create the OIDC client in the broker Keycloak
2. configure the broker Keycloak to trust the upstream SAML IdP
3. configure the upstream Keycloak with the broker Keycloak's SAML Service Provider metadata
4. wire the generated OIDC client secret into the Kubernetes deployment

## Hostnames

This lab always uses `nip.io`.

* Leave it as `127.0.0.1` for local use on the same machine (requires a browser or port forwarder)
* Change it to your server's public IP if using a browser external to the server

With the default `PUBLIC_IP=127.0.0.1`, the local URLs are:

* Broker Keycloak admin console: `http://keycloak.127.0.0.1.nip.io:8080`
* Upstream SAML Keycloak admin console: `http://upstream.127.0.0.1.nip.io:8080`
* Sample protected app: `http://app.127.0.0.1.nip.io:8080`

After updating `PUBLIC_IP`, print the exact URLs the lab will use with:

```bash
export PUBLIC_IP=1.2.3.4
make urls
```

## Deploy The Base Lab

```bash
make deploy
```

That creates the `kind` cluster, installs the Gateway API CRDs, installs Cilium with Gateway API enabled, and deploys Keycloak plus the upstream echo app.

When `PUBLIC_IP` points at a public EC2 address, `make deploy` also relaxes Keycloak's realm SSL requirement for this training setup. Without that, Keycloak allows plain HTTP for localhost-style access but shows `HTTPS required` for external browser access.

The seeded credentials and starting state are:

* Broker Keycloak admin: `admin / admin123admin`
* Upstream Keycloak admin: `admin / admin123admin`
* Upstream SAML user in the `upstream` realm: `student / studentpassword`
* The broker `training` realm intentionally has no local users

## Create The Broker OIDC Client

1. Run `make urls` and use the printed `KEYCLOAK_URL`.
2. Open that broker Keycloak URL and sign in as `admin`.
3. Switch from the `master` realm to the `training` realm.
4. Create a new client with these settings:
   * Client type: `OpenID Connect`
   * Client ID: `training-app`
   * Client authentication: `On`
   * Authorization: `Off`
   * Standard flow: `On`
   * Direct access grants: `Off`
5. In the client settings, set the values printed by `make urls`:
   * Valid redirect URIs: `REDIRECT_URI`
   * Valid post logout redirect URIs: `POST_LOGOUT_REDIRECT_URI`
   * Web origins: `APP_URL`
6. Save the client and copy the generated client secret from the `Credentials` tab.

If you later change `PUBLIC_IP`, come back and update these client settings to the new values from `make urls`.

## Configure The Broker To Use The Upstream SAML IdP

Run `make urls` and keep these values handy:

* `BROKER_ALIAS`
* `UPSTREAM_SAML_METADATA_URL`
* `BROKER_SP_METADATA_URL`

### In The Broker Keycloak

1. Stay in the `training` realm on `KEYCLOAK_URL`.
2. Open `Identity Providers`.
3. Add a new provider of type `SAML v2.0`.
4. Set the alias to the exact value printed as `BROKER_ALIAS`.
5. Import the upstream IdP metadata from `UPSTREAM_SAML_METADATA_URL`.
6. Save the provider.

At this point the broker knows about the upstream IdP, but the upstream IdP does not yet trust the broker as a SAML Service Provider.

### In The Upstream Keycloak

1. Open `UPSTREAM_KEYCLOAK_URL` and sign in as `admin`.
2. Switch from the `master` realm to the `upstream` realm.
3. Create a new client with type `SAML`.
4. Import the broker's SAML Service Provider metadata from `BROKER_SP_METADATA_URL`.
5. Save the imported client.

This gives the upstream IdP a SAML client entry for the broker realm.

### Optional But Recommended Mapper Check

For a smoother first-broker-login experience, make sure the upstream SAML assertions include user profile attributes such as username and email. If your imported SAML client does not already expose them, add protocol mappers in the upstream Keycloak before testing the flow.

## Non-Interactive Validation Script

To run the full setup without UI clicks (OIDC client, broker SAML IdP, upstream SAML client import, mapper wiring, client secret injection, and app deploy), run:

```bash
./setup-saml-and-client.sh
```

You can override defaults with environment variables, for example:

```bash
PUBLIC_IP=1.2.3.4 DEPLOY_APP=false ./setup-saml-and-client.sh
```

## Configure And Launch The Protected App

```bash
make configure-client CLIENT_SECRET='paste-the-secret-here'
make deploy-app
```

Then open the printed `APP_URL`.

`oauth2-proxy` sends the browser to the broker realm with `kc_idp_hint=upstream-saml`, so once the SAML IdP is configured the login flow should jump straight to the upstream Keycloak.

Sign in there as `student / studentpassword`, and then land on the echo app behind `oauth2-proxy`.

If login drops you back on the broker with an account-linking or missing-profile error, inspect the upstream SAML client and broker IdP mapper settings first. The app-facing broker realm still has no local password users, so the intended path is always through the upstream SAML IdP.

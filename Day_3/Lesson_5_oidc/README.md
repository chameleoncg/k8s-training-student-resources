# OIDC Lab

Create a local `kind` cluster with:

* Cilium as the CNI and Gateway API controller
* Keycloak running in HTTP dev mode
* a tiny upstream app (`hashicorp/http-echo`)
* `oauth2-proxy` acting as the OIDC client in front of that app

Creates the Keycloak client manually, then wire the generated client secret into the Kubernetes deployment.

## Hostnames

This lab always uses `nip.io`.

* Leave it as `127.0.0.1` for local use on the same machine (requires a browser or port forwarder)
* Change it to your server's public IP if using a browser external to the server

With the default `PUBLIC_IP=127.0.0.1`, the local URLs are:

* Keycloak admin console: `http://keycloak.127.0.0.1.nip.io:8080`
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

The seeded credentials are:

* Keycloak admin: `admin / admin123admin`
* Training realm user: `student / studentpassword`

## Create The Keycloak Client

1. Run `make urls` and use the printed `KEYCLOAK_URL`.
2. Open that Keycloak URL and sign in as `admin`.
2. Switch from the `master` realm to the `training` realm.
3. Create a new client with these settings:
   * Client type: `OpenID Connect`
   * Client ID: `training-app`
   * Client authentication: `On`
   * Authorization: `Off`
   * Standard flow: `On`
   * Direct access grants: `Off`
4. In the client settings, set the values printed by `make urls`:
   * Valid redirect URIs: `REDIRECT_URI`
   * Valid post logout redirect URIs: `POST_LOGOUT_REDIRECT_URI`
   * Web origins: `APP_URL`
5. Save the client and copy the generated client secret from the `Credentials` tab.

If you later change `PUBLIC_IP`, come back and update these client settings to the new values from `make urls`.

## Configure And Launch The Protected App

```bash
make configure-client CLIENT_SECRET='paste-the-secret-here'
make deploy-app
```

Then open the printed `APP_URL`.

You should be redirected to Keycloak, log in as `student / studentpassword`, and then land on the echo app behind `oauth2-proxy`.

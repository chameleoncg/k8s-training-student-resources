# OIDC Lab With An Upstream SAML IdP

```mermaid
flowchart LR
   U[User] --> D
   A[Broker Keycloak] --> B["Upstream Keycloak<br/>(User Authority)"]
   C[OAuth2-Proxy] --> A
   D[Hashicorp HTTP Echo] --> C[OAuth2-Proxy]
   B --Maps Users--> A
   U -.Authenticates.-> B
```

Create a local `kind` cluster with:

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

When `PUBLIC_IP` points at a public address, `make deploy` also relaxes Keycloak's realm SSL requirement for this training setup. Without that, Keycloak allows plain HTTP for localhost-style access but shows `HTTPS required` for external browser access.

The credentials are:

* Broker Keycloak admin: `admin / admin123admin`
* Upstream Keycloak admin: `admin / admin123admin`
* Upstream SAML user in the `upstream` realm: `student / studentpassword`
* The broker `training` realm intentionally has no local users

## Create The Broker OIDC Client

1. Run `make urls` and use the printed `KEYCLOAK_URL`.
2. Open that broker Keycloak URL and sign in as `admin / admin123admin`.
3. Switch realms by clicking `Manage realms` and selecting the `training` realm.
4. Create a new client with these settings:
   * Client type: `OpenID Connect`
   * Client ID: `training-app` and click Next
   * Client authentication: `On`
   * Standard flow: `On`
   * Leave the rest unchecked
5. Click Next
6. In the client settings, set the values printed by `make urls`:
   * Valid redirect URIs: `REDIRECT_URI`
   * Valid post logout redirect URIs: `POST_LOGOUT_REDIRECT_URI`
   * Web origins: `APP_URL`
7. Save the client and copy the generated client secret from the `Credentials` tab.
   * Note: it is not https, so your brower may prevent the copy button from working, highlight and ctl + c

## Deploy the Protected App

Use this Client Secret to wire into the application. It will use this secret when performing the OIDC flow.

```bash
make configure-client CLIENT_SECRET='paste-the-secret-here'
make deploy-app
```

Now an application is deploying and being fronted by `oauth2-proxy`. While this deploys, lets get users from the upstream SAML IdP setup.

## Configure The Broker To Use The Upstream SAML IdP

### In The Broker Keycloak

1. Stay in the `training` realm on `KEYCLOAK_URL`.
2. Open `Identity Providers`.
3. Add a new provider of type `SAML v2.0`.
4. Set the alias to the exact value printed as `upstream-saml`.
5. Set the SAML entity descriptor to `UPSTREAM_SAML_METADATA_URL` (make sure this turns green and `Show metadata` fills out information from the metadata)
6. Save the provider.
7. In the settings for the new IdP, make sure you check `Trust Email` and click `Save`

Add some mappers for accepting the upstream credentials and mapping them into our broker realm.

1. Within the `Identity Providers` page, click the `upstream-saml` provider.
2. Click `Mappers`.
3. Click `Add mapper`
4. Create and save a username entry
   Name: `username-template`
   Mapper type: `User Template Importer`
   Template: `${ATTRIBUTE.username}`
5. For each of {`email`, `firstName`, `lastName`} create a new mapper
   Name: `email`
   Mapper type: `Attribute Importer`
   Attribute name: `email` 
   Name Format: `Attritube_FORMAT_BASIC`
   User Attribute Name: `email`

At this point the broker knows about the upstream IdP, but the upstream IdP does not yet trust the broker as a SAML Service Provider.

### In The Upstream Keycloak

1. Open your browser or curl to `BROKER_SP_METADATA_URL` to retrieve the SAML metadata for the broker realm. Save the XML to a file.
2. Open `UPSTREAM_KEYCLOAK_URL` and sign in as `admin`.
3. Switch from the `master` realm to the `upstream` realm.
4. Click on `Clients` and click `Import client`.
5. Upload the XML as the `Resource File` and `Save`.
3. Navigate to `Client Scopes` and click the keycloak entry.
4. Verify that mappers are created in the attribute mappings. There are likely 3 (lastName, firstName, email)
5. Click `Add mapper` and `By Configuration` and `User Property`
6. Fill out all blank fields with `username` and save (mapper type is User Property, and Basic nameformat)
6. Set the name to `kc_idp_hint`
5. Save the imported client.

This gives the upstream IdP a SAML client entry for the broker realm.

## Test a Login

Navigate to `APP_URL`. You should see a keycloak login page. Login with the `student / studentpassword` credentials.

You are succeful if you see a `You made it through the Keycloak OIDC login flow.` message and a redirect back to the app URL.

You might be interested to look at the `Users` section of the keycloak UI and observe the mapped user in Keycloak.
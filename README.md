Docker image for theportalwiki.com's Matrix.org server.

# WTF is this?

See [Matrix.org].

# What is this repo?

* A `pwiki-synapse` docker image, which runs a [Synapse] server. Synapse is a [Matrix.org] server implementation.
* Soon: Another thing to run a web client?
* A guide to set this all up.

# How do I use it?

## Host setup

### Checkout the repo

```bash
$ git clone https://github.com/ThePortalWiki/pwiki-matrix
$ cd pwiki-matrix
```

Make sure to back these up.

### Host user

You should create a new user on the host with a unique UID/GID. Reusing the port number of the Synapse server can be helpful here. The rest of this README assumes that the UID/GID are both `8449`.

```bash
$ PWIKI_SYNAPSE_UID=8449
$ PWIKI_SYNAPSE_GID=8449
$ useradd --uid="$PWIKI_SYNAPSE_UID" --gid="$PWIKI_SYNAPSE_GID" -s /bin/false -d / -M pwiki-synapse
```

### TLS volume

The Synapse server requires a valid TLS key and certificate in order to work. These are exposed to the container inside a `/tls` volume, which is expected to contain the following:

```
/tls
├── tls.key  # TLS private key.
└── tls.crt  # Complete TLS certificate chain.
```

The rest of this README assumes that this lives on the host in the `/etc/pwiki-synapse/tls` directory, and it is group-readable by the host group with GID 9001.
This GID will be used such that the non-root user inside the Docker container can share the same GID so that it is able to read the TLS files from the `/tls` volume. It is differentiated from `SYNAPSE_GID` so that it remains possible to have certs for a single domain owned by a shared group on the host, rather than having to maintain separate copies.

```bash
$ PWIKI_SYNAPSE_TLS=/etc/pwiki-synapse/tls
$ stat $PWIKI_SYNAPSE_TLS
  File: /etc/pwiki-synapse/tls
  Size: 4096            Blocks: 8          IO Block: 4096   directory
Device: 800h/2048d      Inode: 690709      Links: 2
Access: (0750/drwxr-x---)  Uid: (    0/    root)   Gid: ( 9001/     tls)
Access: 2016-12-30 17:59:09.120460354 -0500
Modify: 2016-12-30 17:59:09.120460354 -0500
Change: 2016-12-30 17:59:22.193321816 -0500
 Birth: -
$ PWIKI_TLS_GID="$(stat -c '%g' "$(readlink -e "$PWIKI_SYNAPSE_TLS")")"
```

### Media volume

Synapse requires persistent filesystem storage to store files uploaded by users. Pick some directory on the host to store them. The rest of this README assumes that this lives inside `/var/lib/pwiki-synapse/media`. It is mounted as `/synapse-media` in the Docker container. It needs to be writable by the synapse user.

Might want to set up backup for that directory as well, although it is not as critical.

```bash
$ PWIKI_SYNAPSE_MEDIA=/var/lib/pwiki-synapse/media
$ chown -R "$PWIKI_SYNAPSE_UID:$PWIKI_SYNAPSE_GID" "$PWIKI_SYNAPSE_MEDIA"
```

## Build the Docker images

### TURN server image

Synapse requires a TURN server for establishing VoIP connections. This runs in a separate container running a [coturn](https://github.com/coturn/coturn) server. Synapse communicates to coturn using a shared secret key in order to set up credentials that users can then use on the TURN server.

Like the Synapse server, it supports TLS, so it also requires access to the TLS cert and key file.

```bash
$ COTURN_UID=3478
$ COTURN_GID=3478
$ COTURN_DOMAIN=theportalwiki.com
$ COTURN_PORT=3478
$ docker build                                 \
    --build-arg="COTURN_UID=$COTURN_UID"       \
    --build-arg="COTURN_GID=$COTURN_GID"       \
    --build-arg="TLS_GID=$PWIKI_TLS_GID"       \
    --build-arg="COTURN_DOMAIN=$COTURN_DOMAIN" \
    --build-arg="COTURN_PORT=$COTURN_PORT"     \
    --tag=pwiki-synapse-coturn                 \
    images/pwiki-synapse-coturn
```

#### Build arguments

* `COTURN_UID`: The UID to create the internal user. Optional, default `3478`.
* `COTURN_UID`: The GID to create the internal user. Optional, default `3478`.
* `TLS_GID`: The group ID of the TLS mount. Required.
* `COTURN_DOMAIN`: The external domain name to advertise. Required.
* `COTURN_PORT`: The port number for TCP and UDP TURN requests. Optional. Default `3478`.
* `REBUILD`: You can set `--build-arg=REBUILD=$(date)` to force a rebuild and update all packages within.

### Synapse image

```bash
$ SYNAPSE_DOMAIN=theportalwiki.com
$ SYNAPSE_PORT=8449
$ docker build                                   \
    --build-arg="SYNAPSE_UID=$PWIKI_SYNAPSE_UID" \
    --build-arg="SYNAPSE_GID=$PWIKI_SYNAPSE_GID" \
    --build-arg="TLS_GID=$PWIKI_TLS_GID"         \
    --build-arg="SYNAPSE_DOMAIN=$SYNAPSE_DOMAIN" \
    --build-arg="SYNAPSE_PORT=$SYNAPSE_PORT"     \
    --build-arg="COTURN_DOMAIN=$COTURN_DOMAIN"   \
    --build-arg="COTURN_PORT=$COTURN_PORT"       \
    --tag=pwiki-synapse                          \
    images/pwiki-synapse
```

#### Build arguments

* `TLS_GID`: The group ID of the TLS mount. Required.
* `SYNAPSE_UID`: The UID to create the internal user. Optional, default `8449`. Should match `$PWIKI_SYNAPSE_UID`.
* `SYNAPSE_GID`: The GID to create the internal user. Optional, default `8449`. Should match `$PWIKI_SYNAPSE_GID`.
* `SYNAPSE_DOMAIN`: The domain name for the Synapse server. You can change this to reuse the image for non-pwiki purposes.
* `SYNAPSE_PORT`: The *external* port number that will be forwarded to the Synapse server. `8448` by default. It should either be the default, either be whatever is set as Matrix SRV record for `SYNAPSE_DOMAIN`. Synapse needs this in order to advertise the correct prot externally.
* `COTURN_DOMAIN`: The external domain name to advertise for TURN. Optional. Defaults to `$SYNAPSE_DOMAIN`.
* `COTURN_PORT`: The port number for TCP and UDP TURN requests. Optional. Default `3478`.
* `REBUILD`: You can set `--build-arg=REBUILD=$(date)` to force a rebuild and update all packages within.

### PostgreSQL image

```bash
$ docker build                 \
    --tag=pwiki-synapse-pgsql  \
    images/pwiki-synapse-pgsql
```

## Generate Synapse secrets volume

You need to generate a bunch of secrets for Synapse to work. The rest of this README assumes that you will be storing them in `/etc/pwiki-synapse/secrets`. These will be mounted into the Synapse container as a volume under `/secrets`. They should only be readable by `root`, both inside and outside the container.

Part of the secrets generation involves generating an `ed25519` signing key using a [special format](https://github.com/matrix-org/python-signedjson), so we use a script bundled within the pwiki-synapse image to generate it.

This only needs to be done once but may be safely re-ran as needed if new types of secrets are added. Existing secrets will not be overwritten.

```bash
$ PWIKI_SYNAPSE_SECRETS=/etc/pwiki-synapse/secrets
$ docker run --rm                              \
    --name=pwiki-synapse-secrets               \
    --volume="$PWIKI_SYNAPSE_SECRETS:/secrets" \
    pwiki-synapse /generate-secrets.sh
$ tree "$PWIKI_SYNAPSE_SECRETS"
/etc/pwiki-synapse/secrets
├── macaroon.key
├── pepper.key
├── postgresql_superuser.password
├── postgresql_synapse.password
├── registration.key
├── signing.key
├── signing_key_id.pub
├── tls.dh
└── turn_shared_secret.key
```

Back up all of these files immediately.

## Run the PostgreSQL container

$ docker run --detach                              \
    --name=pwiki-synapse-pgsql                     \
    --volume="$PWIKI_SYNAPSE_SECRETS:/secrets"     \
    --log-driver=journald                          \
    pwiki-synapse-pgsql

## Run the coturn container

```bash
$ docker run --detach                              \
    --name=pwiki-synapse-coturn                    \
    --volume="$PWIKI_SYNAPSE_SECRETS:/secrets"     \
    --volume="$PWIKI_SYNAPSE_TLS:/tls"             \
    --publish="$COTURN_PORT:$COTURN_PORT/tcp"      \
    --publish="$COTURN_PORT:$COTURN_PORT/udp"      \
    --log-driver=journald                          \
    pwiki-synapse-coturn
```

## Run the Synapse container

```bash
$ docker run --detach                              \
    --name=pwiki-synapse                           \
    --link=pwiki-synapse-pgsql:postgres            \
    --volume="$PWIKI_SYNAPSE_SECRETS:/secrets"     \
    --volume="$PWIKI_SYNAPSE_TLS:/tls"             \
    --volume="$PWIKI_SYNAPSE_MEDIA:/synapse-media" \
    --publish="$SYNAPSE_PORT:8448"                 \
    --log-driver=journald                          \
    pwiki-synapse
```

This binds to the port `$SYNAPSE_PORT` on the host. Note that the Docker-side port should always be `8448`.

Your Matrix server should now be running. Logs can be read with

```bash
$ journalctl CONTAINER_NAME=pwiki-synapse
```

## Save all these variables for future use

By this point you have a lot of `IMPORTANT_UPPERCASE_VARIABLES` in your shell. Here's how to save them for the next time to run some `docker run` commands or the like.

```bash
$ ( set -o posix ; set ) | ./resources/save-important-variables.sh > /etc/pwiki-synapse/sourceme.sh
```

## More to come...

# TODO

* Trust other domains for identity purposes (e.g. `perot.me`, `lagg.me`, `colinjstevens.com` etc.)
* Allow new channel creation by users
* Set up Synapse client port w/ reverse proxying
* Set up other container that shows a fancy web client thing
* Allow guest registration (requirs ReCaptcha)? Or at least guest viewing
* Enable URL preview API
* Set up PostgreSQL backups
* Add LetsEncrypt auto cert renewal details
* Add script to generate systemd units for building and running the containers with the correct arguments

[Matrix.org]: https://matrix.org/
[Synapse]: https://github.com/matrix-org/synapse

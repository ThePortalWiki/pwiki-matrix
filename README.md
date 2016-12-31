Docker image for theportalwiki.com's Matrix.org server.

# WTF is this?

See [Matrix.org].

# What is this repo?

* A `pwiki-synapse` docker image, which runs a [Synapse] server. Synapse is a [Matrix.org] server implementation.
* Soon: Another thing to run a web client?
* A guide to set this all up.

# How do I use it?

## Host setup

### Host user

You should create a new user on the host with a unique UID/GID. Reusing the port number of the Synapse server can be helpful here. The rest of this README assumes that the UID/GID are both 8449.

```bash
$ PWIKI_SYNAPSE_UID=8449
$ PWIKI_SYNAPSE_GID=8449
$ useradd --uid="$PWIKI_SYNAPSE_UID" --gid="$PWIKI_SYNAPSE_GID" -s /bin/false -d / -M pwiki-synapse
```

### TLS volume

The Synapse server requires a valid TLS key and certificate in order to work. These are exposed to the container inside a `/tls` volume, which is expected to contain the following:

```
/tls
├── /tls/tls.key  # TLS private key.
└── /tls/tls.crt  # Complete TLS certificate chain.
```

The rest of this README assumes that this lives on the host in the `/etc/pwiki-synapse/tls` directory, and it is group-readable by the host group with GID 9001.
This GID will be used such that the non-root user inside the Docker container can share the same GID so that it is able to read the TLS files from the `/tls` volume. It is differentiated from `SYNAPSE_GID` so that it remains possible to have certs for a single domain owned by a common `tls` group on the host, rather than having to maintain separate copies.

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
$ PWIKI_TLS_GID=$(stat -c '%g' $PWIKI_SYNAPSE_TLS)
```

### Synapse config volume

Synapse requires a persistent storage volume to hold configuration data. This is unfortunate, and the reasons why are documented in another section. The rest of this README assumes that this lives inside `/etc/pwiki-synapse/synapse`. It is mounted as `/synapse` in the Docker container.

It is imperative to backup the contents of this volume.

```bash
$ PWIKI_SYNAPSE_CONFIG=/etc/pwiki-synapse/synapse
```

### Media volume

Synapse requires persistent filesystem storage to store files uploaded by users. Pick some directory on the host to store them. The rest of this README assumes that this lives inside `/var/lib/pwiki-synapse/media`. It is mounted as `/synapse-media` in the Docker container. It needs to be writable by the synapse user.

Might want to set up backup for that directory as well, although it is not as critical.

```bash
$ PWIKI_SYNAPSE_MEDIA=/var/lib/pwiki-synapse/media
$ chown -R "$PWIKI_SYNAPSE_UID:$PWIKI_SYNAPSE_GID" "$PWIKI_SYNAPSE_MEDIA"
```

## Build the Synapse Docker image

```bash
$ git clone https://github.com/ThePortalWiki/pwiki-matrix
$ docker build                               \
    --build-arg="TLS_GID=$PWIKI_TLS_GID" \
    --tag=pwiki-synapse                      \
    pwiki-matrix/images/pwiki-synapse
```

### Build arguments

* `TLS_GID`: The group ID of the TLS mount. Required.
* `SYNAPSE_UID`: The UID to create the internal user. Optional, default `8449`. Should match `$PWIKI_SYNAPSE_UID`.
* `SYNAPSE_GID`: The GID to create the internal user. Optional, default `8449`. Should match `$PWIKI_SYNAPSE_GID`.
* `SYNAPSE_DOMAIN`: The domain name for the Synapse server. You can change this to reuse the image for non-pwiki purposes.
* `SYNAPSE_PORT`: The *external* port number that will be forwarded to the Synapse server. `8448` by default. It should either be the default, either be whatever is set as Matrix SRV record for `SYNAPSE_DOMAIN`.
* `REBUILD`: You can set `--build-arg=REBUILD=$(date)` to force a rebuild and update all packages within.

## Initialize server config (do this only once, ever)

Synapse requires a one-time setup step which does a few one-time things, such as:

* Creating a outgoing message signing key.
* Generating Diffie-Hellman parameters.
* Initializing the SQLite database tables.
* Generating the pepper string to use for password hashing.

The output of all of these things needs to remain unchanged even as the Synapse server gets upgraded. To this end, you should do this step only once, ever. Unfortunately, the Synapse configuration file is poorly designed. There is no way to separate these unchanging secret configuration options from the rest. This is why the configuration file is stored in persistent storage, rather than in the image itself. This means that the configuration file might get out of date as new Synapse versions get released, and needs to be manually maintained.

```bash
$ docker run                                   \
    --volume="$PWIKI_SYNAPSE_CONFIG:/synapse"  \
    pwiki-synapse /initialize-synapse-onetime.sh
```

This will initialize the `$PWIKI_SYNAPSE_CONFIG` volume with the Synapse-generated content: the initial configuration file, and some secrets necessary to run the Synapse server.

```
/synapse
├── /synapse/synapse.yaml  # Config file generated during initialization.
├── /synapse/logging.yaml  # Another config file generated during initialization.
├── /synapse/pepper        # Pepper for passwords. Must never change. Backup.
├── /synapse/signing.key   # Private key for signing outgoing messages. Backup.
├── /synapse/tls.dh        # Diffie-Hellman parameters for ephemeral keys. Regeneratable.
└── /synapse/db.sqlite     # Main SQLite database. This will eventually change to PostgreSQL.
```

Make sure to set up backup for the contents of this Docker volume on the host.

## Run the Synapse container

There is

```bash
$ docker run                                       \
    --name=pwiki-synapse                           \
    --volume="$PWIKI_SYNAPSE_CONFIG:/synapse"      \
    --volume="$PWIKI_SYNAPSE_TLS:/tls"             \
    --volume="$PWIKI_SYNAPSE_MEDIA:/synapse-media" \
    --publish="$SYNAPSE_PORT:8448"                 \
    pwiki-synapse
```

This binds to the port `$SYNAPSE_PORT` on the host. Note that the Docker-side port should always be `8448`.

Your Matrix server should now be running.

## More to come...

# TODO

* Make config persistence more robust (e.g. rewrite known fields on regular startup) rather than write-once
* Trust other domains for identity purposes (e.g. `perot.me`, `lagg.me`, `colinjstevens.com` etc.)
* Allow new channel creation by users
* Turn down local file logging (it's useless in a container).
* Set up persistent PostgreSQL database
* Set up Synapse client port w/ reverse proxying
* Set up Synapse TURN server
* Set up other container that shows a fancy web client thing
* Allow guest registration (requirs ReCaptcha)? Or at least guest viewing
* Enable URL preview API
* Set up PostgreSQL backups

[Matrix.org]: https://matrix.org/
[Synapse]: https://github.com/matrix-org/synapse

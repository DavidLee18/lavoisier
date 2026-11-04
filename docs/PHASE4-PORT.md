# Lattice Phase 4 — Port

Lavoisier runs as a **lattice workload** that speaks the Matrix client-server API to the
in-cluster wasmCloud homeserver `matrix-cs`. This is the existing `lav` process (`--serve-matrix`),
not a new gateway and not a wasm guest.

## Locked

- **G4 is `lav --matrix-probe`.** It sends one `m.text` and `/sync`s until that event is read back. `--serve-matrix` is the resident client. It is not G4.
- **G4 registration is `m.login.registration_token`.** The secret is `MATRIX_REGISTRATION_TOKEN`. On a lattice dial, `MATRIX_REGISTER` without that secret is refused. `m.login.dummy` is not the G4 path. It remains only for a non-lattice lab that sets `MATRIX_REGISTER` without the lattice markers.

**HOLD APPLY.** Do not apply Terraform. Do not push an image. Do not change Continuwuity, Phase D,
ECS desired counts, or EFS. Path A stays off (no Continuwuity-on-GKE). Publishing stays with Sir.

The ECS task stays desired 1 on `MATRIX_HOMESERVER=https://matrix.spider42.com` as
`@lav:matrix.spider42.com`. Nothing in this contract retargets that path. Leave the lattice
variables unset there.

## Dial

| | Lattice | ECS (unchanged) |
|---|---|---|
| Base URL | `http://matrix-cs.wasmcloud.svc.cluster.local:80` | `https://matrix.spider42.com` |
| HTTP `Host` | `matrix-cs.wasmcloud.svc` | the URL host |
| Server name | `davidlee18.dev` | `matrix.spider42.com` |
| User | `@localpart:davidlee18.dev` issued by `matrix-cs` | `@lav:matrix.spider42.com` |

The dial address and the `Host` header are different. Kubernetes resolves
`matrix-cs.wasmcloud.svc.cluster.local`. The component's `hostInterfaces` host (from
`components/matrix-cs/wadm.yaml` in `lvz-matrix-infra`) is `matrix-cs.wasmcloud.svc`. The client
resolves the dial host and sends requests whose authority is the `Host` name, with the default
port omitted, so the header is `matrix-cs.wasmcloud.svc` and not `:80`.

`session.json` records the dial URL (`MATRIX_HOMESERVER`), so a restart does not mix a spider42
token into this plane.

Setting any one of the lattice markers (that homeserver host, that `Host` value, or server name
`davidlee18.dev`) requires the full pin. A half-configured lattice dial fails closed rather than
talking to spider42.

## Config contract

Precedence is the usual one: environment, then `[gateway]` in `lavoisier.toml`, then built-in
default. Secrets are environment-only. They are not toml keys.

| Env | Toml (if env unset) | Required on lattice | Notes |
|---|---|---|---|
| `MATRIX_HOMESERVER` | `matrix_homeserver` | yes | `http://matrix-cs.wasmcloud.svc.cluster.local:80` |
| `MATRIX_HTTP_HOST` | `matrix_http_host` | yes | `matrix-cs.wasmcloud.svc` |
| `MATRIX_SERVER_NAME` | `matrix_server_name` | yes | `davidlee18.dev` |
| `MATRIX_USER` | `matrix_user` | yes, unless only a token is used | `@localpart:davidlee18.dev` or the localpart |
| `MATRIX_DEVICE_ID` | `matrix_device_id` | yes | Pinned device. Password login and registration send it. If `whoami` reports another id, that id wins and a warning is logged. |
| `MATRIX_ACCESS_TOKEN` | — | one of token or password | Skips `/login` and registration. Identity from `/account/whoami`. |
| `MATRIX_PASSWORD` | — | one of token or password | `m.login.password` |
| `MATRIX_REGISTER` | `matrix_register` | no (default off) | `true`/`1`/`yes`/`on` tries `POST /_matrix/client/v3/register` before login. `M_USER_IN_USE` falls through to login. On a lattice dial this requires `MATRIX_REGISTRATION_TOKEN`. |
| `MATRIX_REGISTRATION_TOKEN` | — | when `MATRIX_REGISTER` is on | G4 auth type `m.login.registration_token`. A lattice register without it is refused. A 401 that carries a UIA `session` is retried once with that session. |
| `MATRIX_STATE_DIR` | `matrix_state_dir` | no | See state below. |
| `MATRIX_CRYPTO_STORE_KEY` | — | no | E2EE at-rest passphrase. Not required for G4. |
| `MATRIX_PROBE_ROOM` | — | for `--matrix-probe` | Room id to send into. |
| `MATRIX_PROBE_BODY` | — | no | Defaults to `lavoisier lattice probe <nanos>`. |

Auth order: access token, then a persisted session, then registration when enabled, then password
login. Resolved user ids must match `MATRIX_SERVER_NAME` when it is set.

`MATRIX_REGISTER` needs `MATRIX_USER`, `MATRIX_PASSWORD`, and, on a lattice dial,
`MATRIX_REGISTRATION_TOKEN`. The username sent to `/register` is the localpart
(`@lav:davidlee18.dev` → `lav`). The device display name is `Lavoisier lattice`. The auth object
is `{"type":"m.login.registration_token","token":…}`.

## State without the ECS volume

`MATRIX_STATE_DIR` is a directory the process can create. Layout is unchanged: `session.json` in
that directory, and `<dir>/crypto` for the E2EE store when the `e2ee` feature is on.

The lattice workload **must not** mount `fs-0966896c7d24d7b20`. A lattice dial whose state path
contains that id is refused. The ECS task may keep using it.

This repository does not define a volume. An empty directory (an `emptyDir` the latch adds later,
or a fresh container filesystem) is a valid G4 state:

- Identity comes from the secrets and `MATRIX_DEVICE_ID` on every boot.
- `session.json` is a cache. If the directory is wiped, the next boot logs in again with the same
  device id (or reuses `MATRIX_ACCESS_TOKEN`).
- E2EE keys in `<dir>/crypto` do not survive an ephemeral directory. G4 is plaintext send + sync.
  Durable crypto is a later latch decision, not a mount of the ECS filesystem.

## Gate G4

G4 is this command. It prints the event id on stdout and exits. It does not start a model provider.

An account that already exists logs in with the password (registration stays off):

```sh
MATRIX_HOMESERVER=http://matrix-cs.wasmcloud.svc.cluster.local:80 \
MATRIX_HTTP_HOST=matrix-cs.wasmcloud.svc \
MATRIX_SERVER_NAME=davidlee18.dev \
MATRIX_USER='@lav:davidlee18.dev' \
MATRIX_PASSWORD='…' \
MATRIX_DEVICE_ID=LAVOISIER_LATTICE \
MATRIX_PROBE_ROOM='!room:davidlee18.dev' \
lav --matrix-probe
```

First boot registers with `m.login.registration_token`, then sends and reads back. `M_USER_IN_USE`
on a later boot falls through to password login. Omitting the registration token with
`MATRIX_REGISTER` set is a startup failure.

```sh
MATRIX_HOMESERVER=http://matrix-cs.wasmcloud.svc.cluster.local:80 \
MATRIX_HTTP_HOST=matrix-cs.wasmcloud.svc \
MATRIX_SERVER_NAME=davidlee18.dev \
MATRIX_USER='@lav:davidlee18.dev' \
MATRIX_PASSWORD='…' \
MATRIX_DEVICE_ID=LAVOISIER_LATTICE \
MATRIX_REGISTER=true \
MATRIX_REGISTRATION_TOKEN='…' \
MATRIX_PROBE_ROOM='!room:davidlee18.dev' \
lav --matrix-probe
```

A resident workload uses `lav --serve-matrix` with the same identity variables. That is not G4.

## What `lvz-extra-tools` / `deploy_lavoisier_lattice` must pin

This repo does not build or push an image.

| Pin | Value |
|---|---|
| Artefact | OCI image from [`Containerfile`](../Containerfile). Entrypoint `/usr/local/bin/lav`. |
| Arch | The Containerfile is `linux/arm64` because the ECS/Fargate task is arm64. A GKE node may be amd64. The latch chooses the arch and the digest. Do not reuse the ECS task definition. |
| Command | `["--serve-matrix"]` for the resident client. `["--matrix-probe"]` for G4. |
| Network | Outbound TCP to `matrix-cs.wasmcloud.svc.cluster.local:80`. Model-provider egress only if `--serve-matrix` actually runs turns. |
| Secrets | The env vars above, injected at run time, not baked into the image. |
| Volume | Writable directory for `MATRIX_STATE_DIR`, or none. Not `fs-0966896c7d24d7b20`. |

Guest interfaces: **none in this artefact.** `lav` is a native Linux binary (tokio, reqwest,
tree-sitter, and optionally `matrix-sdk-crypto`). It is not a `wasm32-wasip2` component. The host
interface it consumes is the one `matrix-cs` already exposes: HTTP on host
`matrix-cs.wasmcloud.svc`. The latch does not need a new WIT world to place this process in the
cluster and let it dial that ClusterIP.

If a later latch insists on a wasm guest, that is a follow-up, not this Port. The minimum guest
would import `wasi:http/outgoing-handler` (client-server calls) and a filesystem for the state
directory. It is not scaffolded here: a second, partial client would drift from the gateway the
ECS path already runs.

## Hold

- Do not `terraform apply`.
- Do not `podman push` / `--push`.
- Do not tag a release. Crate versions are unchanged.
- Do not edit `lvz-matrix-infra` wadm, Continuwuity, or ECS desired count.

# MCS Modpack (June 2026)

This repository builds and publishes a Packwiz-compatible Minecraft modpack. CurseForge and Modrinth packs are installed by `mc-image-helper`; Packwiz is only used to create Packwiz metadata and refresh the Packwiz index.

## Flow

```text
0-bootstrap.sh
    ↓ installs mc-image-helper and packwiz
1-modpack-initialize.sh
    ↓ uses mc-image-helper to install CurseForge/Modrinth/local source files into publish/
    ↓ uses packwiz init to create pack.toml
2-modpack-finalize.sh
    ↓ packwiz refresh creates/updates index.toml
3-modpack-publish.sh
    ↓ wipes Cloudflare R2 destination and uploads publish/
```

## Repository layout

```text
.
├── bin/                         # generated tools, ignored by Git
├── publish/                     # generated Packwiz pack
├── 0-bootstrap.sh
├── 1-modpack-initialize.sh
├── 2-modpack-finalize.sh
├── 3-modpack-publish.sh
├── .env.example
└── README.md
```

`bootstrap.sh` remains as a compatibility wrapper for `0-bootstrap.sh`. The legacy `packwiz-importer.sh` and `packwiz-patches.sh` scripts have been removed from the standard pipeline.

## Bootstrap

```bash
cp .env.example .env
./0-bootstrap.sh
```

The bootstrap script installs:

* `bin/packwiz`
* `bin/mc-image-helper` wrapper
* `.tools/mc-image-helper-<version>/` with the full mc-image-helper `bin/` and `lib/` distribution

`rclone` is used for publishing. If it is already installed, bootstrap links it into `bin/rclone`; otherwise install it separately or set `RCLONE=/path/to/rclone` before publishing.

## Initialize from CurseForge

Set `.env` with one of these CurseForge inputs:

```bash
CF_PAGE_URL="https://www.curseforge.com/minecraft/modpacks/example-pack"
# or
CF_SLUG="example-pack"
# or
CF_MODPACK_ZIP="./downloads/example-pack.zip"
# or legacy remote zip input, still downloaded by mc-image-helper:
MODPACK_ZIP_URL="https://example.com/example-pack.zip"
```

Then run:

```bash
./1-modpack-initialize.sh
```

CurseForge downloads and installation are handled by:

```bash
mc-image-helper install-curseforge
```

Packwiz does not import the CurseForge modpack. After the source files are installed, the script runs `packwiz init` to generate `pack.toml`.

## Initialize from Modrinth

```bash
MODPACK_SOURCE="modrinth"
MODRINTH_PROJECT="example-pack"
MODRINTH_VERSION=""
MODRINTH_GAME_VERSION="1.21.1"
MODRINTH_LOADER="neoforge"
```

Then run:

```bash
./1-modpack-initialize.sh
```

Modrinth installation is handled by:

```bash
mc-image-helper install-modrinth-modpack
```

## Local customizations

Make repeatable local changes directly in `publish/` after initialization and before finalization, or keep a project-specific script outside the standard pipeline. The standard pipeline no longer calls `packwiz-patches.sh`.

## Finalize

```bash
./2-modpack-finalize.sh
```

This runs:

```bash
packwiz refresh
```

`packwiz refresh` updates `publish/index.toml` and the hash in `publish/pack.toml`.

## Publish to Cloudflare R2

Set either a direct rclone destination:

```bash
RCLONE_DEST="r2:my-bucket/path"
```

or configure the R2 variables:

```bash
RCLONE_REMOTE="r2"
R2_BUCKET="my-bucket"
R2_PREFIX="modpack"
R2_ACCOUNT_ID="..."
R2_ACCESS_KEY_ID="..."
R2_SECRET_ACCESS_KEY="..."
```

Then run:

```bash
./3-modpack-publish.sh
```

The publish script first wipes the destination with `rclone delete --rmdirs`, then uploads `publish/` with `rclone sync --delete-before`. This keeps repeated publishes idempotent and prevents stale objects from previous modpack versions from remaining in R2.

## Typical full run

```bash
./0-bootstrap.sh
./1-modpack-initialize.sh
./2-modpack-finalize.sh
./3-modpack-publish.sh
```

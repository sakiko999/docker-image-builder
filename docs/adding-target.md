# Adding a target

A target is a self-contained description of how to build and publish one upstream project's image. The central engine (`scripts/build-target.sh`) and the workflows do not change when you add a target; only the new `targets/<id>/` directory is required.

## Steps

1. Create `targets/<id>/target.json`. The target ID contains only lowercase letters, digits, and hyphens.

   ```json
   {
     "schemaVersion": 1,
     "id": "<id>",
     "upstream": {
       "repository": "owner/project",
       "tagPattern": "^v[0-9]+(\\.[0-9]+)+(\\.post[0-9]+)?$"
     },
     "image": {
       "repository": "ghcr.io/<owner>/<id>",
       "platform": "linux/amd64"
     },
     "build": {
       "adapter": "build.sh",
       "dockerfile": "Dockerfile"
     }
   }
   ```

2. Add `targets/<id>/build.sh`, an executable adapter that reads `SOURCE_DIR`, `TARGET_DIR`, `IMAGE_REPOSITORY`, `IMAGE_TAG`, `UPSTREAM_TAG`, `UPSTREAM_SHA`, `OVERLAY_SHA`, and `REPO_ROOT` (all exported by the engine) and produces the final image. It may build an upstream base image and a final overlay.

3. Add `targets/<id>/Dockerfile` (the final overlay) plus optional `patches/` and `config/`.

4. Never commit upstream source. The engine clones upstream into a temporary directory and never writes it into this repository. The image build context must not include persistent copies of upstream source.

5. Add fixture-driven tests under `tests/` that exercise your target's contract.

6. Validate locally:

   ```bash
   ./scripts/validate-target.sh <id>
   ./scripts/build-local.sh <id>
   ```

## Rules

- The image repository must use `ghcr.io/`.
- A target must not commit upstream source, generated build context, or tokens.
- `build.sh` must be an executable regular file; `Dockerfile` must exist.
- The engine always selects the latest matching upstream tag; adapters never accept a historical tag.

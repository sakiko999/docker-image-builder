# Multi-Upstream Docker Image Builder Design

**Status:** Approved for implementation on 2026-07-19

## Purpose

Turn this repository into a reusable Docker image delivery layer for external projects. It must not fork or retain upstream source code. Instead, it tracks the latest accepted upstream Git tag for each configured target, builds that exact source revision with target-specific overlays, and publishes the result to GitHub Container Registry (GHCR).

The first implemented target is nanobot. The repository architecture must make a future target a self-contained addition rather than a copy of a GitHub Actions workflow.

## Scope and non-goals

The first release implements:

- A configuration-driven target registry with one real target: nanobot.
- Scheduled and manual checks that always choose the latest accepted upstream tag; neither interface accepts a historical version.
- A reproducible linux/amd64 image build and GHCR publication flow.
- Target-specific patches, configuration templates, entrypoint, and health check without storing credentials in the image or repository.
- A committed state record for the latest successful build of each target.
- Local validation and local build commands that use the same target contract as CI.

The first release deliberately excludes:

- Building a second real upstream target.
- Historical tag selection, rollback, or rebuilding an old release on demand.
- Multi-platform images, image signing, SBOM generation, security scanning, release-note generation, and automatic deletion of older GHCR versions.
- Persistent copies of upstream source code inside this repository.

Leaving a release-tagged GHCR image available is traceability, not a supported historical-version maintenance workflow. The workflow only ever selects and builds the latest matching upstream tag.

## Architecture

    targets/<target>/target.json       declarative target metadata
    targets/<target>/build.sh          project-specific build adapter
    targets/<target>/Dockerfile        final image overlay
    targets/<target>/patches/          optional ordered source patches
    targets/<target>/config/           non-secret configuration templates
              |
              v
    scripts/build-target.sh            generic orchestration engine
      - resolve latest upstream tag
      - clone that tag to a temporary directory
      - resolve the exact commit
      - apply patches
      - call the target build adapter
      - tag and push the resulting image
      - write state/<target>.json after a successful push
              |
              v
    .github/workflows/build-images.yml GitHub Actions scheduling and GHCR login

The generic engine owns lifecycle, validation, state comparison, source checkout, publication, and errors. A target owns the facts that differ from project to project: source layout, Docker build method, final runtime behavior, patches, and configuration templates. This boundary prevents a future target with a different language or build tool from turning the central workflow into a large conditional script.

Targets run sequentially in the first release. This avoids concurrent commits to the state directory and is sufficient while only nanobot exists. A later matrix implementation may parallelize independent targets after it has a separate, conflict-free state-update design.

## Target contract

Every target resides below targets/<id>/. Target IDs contain only lowercase letters, digits, and hyphens, and scripts reject any value that could become a path traversal.

The initial targets/nanobot/target.json has this logical schema:

    {
      "schemaVersion": 1,
      "id": "nanobot",
      "upstream": {
        "repository": "HKUDS/nanobot",
        "tagPattern": "^v[0-9]+(\\.[0-9]+)+(\\.post[0-9]+)?$"
      },
      "image": {
        "repository": "ghcr.io/sakiko999/nanobot",
        "platform": "linux/amd64"
      },
      "build": {
        "adapter": "build.sh",
        "dockerfile": "Dockerfile"
      }
    }

An image reference is explicit rather than inferred from a GitHub owner. This makes a target portable to a repository transfer and makes publication intent auditable in review. A repository fork can change its target configuration without changing generic scripts.

scripts/validate-target.sh validates required JSON fields with jq, checks the target ID, confirms the adapter and Dockerfile exist under the target directory, and rejects image references outside ghcr.io/ in the first release. Validation happens before an upstream checkout or Docker command.

scripts/resolve-latest-tag.sh obtains refs using git ls-remote --tags --refs, removes refs/tags/, filters with tagPattern, and uses version sorting to select one tag. It intentionally ignores prerelease-looking tags that do not match the configured pattern. After checkout, the engine resolves <tag>^{commit} so annotated tags and lightweight tags both yield an exact source commit.

## nanobot image build

nanobot has an upstream-maintained Dockerfile. Copying its current Python, Node, WebUI, and WhatsApp bridge build logic into this repository would couple the overlay to details that can change with every upstream tag. The first target therefore uses a two-layer build:

    temporary checkout of HKUDS/nanobot@tag
      |
      |- docker build of source/Dockerfile -> local nanobot upstream base image
      |
      |- docker build of targets/nanobot/Dockerfile, FROM that local base image
           -> final GHCR image

targets/nanobot/build.sh receives these environment variables from the generic engine:

    REPO_ROOT        absolute overlay repository path
    TARGET_DIR       absolute targets/nanobot path
    SOURCE_DIR       temporary, checked-out upstream source path
    UPSTREAM_TAG     selected upstream tag
    UPSTREAM_SHA     resolved source commit SHA
    IMAGE_REPOSITORY final image repository without a tag
    IMAGE_TAG        selected upstream tag
    OVERLAY_SHA      current overlay commit SHA, or "local" for a local build

It creates a local upstream base image from SOURCE_DIR/Dockerfile, then builds the final overlay image. The final Dockerfile receives the base image, upstream tag, upstream SHA, and overlay SHA as build arguments and writes these standard OCI labels:

- org.opencontainers.image.source
- org.opencontainers.image.version
- org.opencontainers.image.revision
- org.opencontainers.image.created
- org.opencontainers.image.vendor

The final image is tagged with both latest and the selected upstream tag, such as v0.2.2. The upstream commit SHA is retained in OCI labels and state, not as an additional image tag.

The final overlay Dockerfile does not switch the inherited runtime user. It adds executable overlay scripts and read-only configuration templates, then sets an overlay entrypoint. This preserves the upstream non-root runtime model while allowing a stable container contract.

The entrypoint validates that the runtime ~/.nanobot directory is writable, then executes nanobot "$@". The default command is gateway; callers may override it with a normal nanobot subcommand. The image exposes ports 18790 and 8765. Its healthcheck calls http://127.0.0.1:18790/health by default, and permits an environment override when a user has configured a different gateway health URL.

targets/nanobot/config/ may contain example configuration and documentation only. It never contains API keys, bot tokens, OAuth credentials, or a default runtime configuration that overwrites a user-mounted ~/.nanobot directory. Users who expose WebUI or WebSocket access must explicitly configure the upstream listener address and token protection themselves.

## Patch and configuration behavior

scripts/apply-patches.sh applies targets/<id>/patches/*.patch in lexicographic filename order with patch -p1. It succeeds immediately when no patch files exist. A malformed or conflicting patch exits non-zero and stops the build before an image can be published. The workflow never silently skips a patch.

The target configuration directory is copied only into an image documentation or template location. It is not treated as a source-code fork and is not used to mutate an existing mounted configuration at startup.

## State, idempotency, and publication

Each target has state/<id>.json. The initial state file is created only after the first successful publication and has this shape:

    {
      "schemaVersion": 1,
      "target": "nanobot",
      "upstream": {
        "repository": "HKUDS/nanobot",
        "tag": "v0.2.2",
        "commit": "<resolved-source-commit>"
      },
      "image": {
        "repository": "ghcr.io/sakiko999/nanobot",
        "tags": ["latest", "v0.2.2"]
      },
      "overlayCommit": "<overlay-commit>",
      "builtAt": "<UTC RFC 3339 timestamp>"
    }

The engine skips a target only when both its latest matching tag and resolved source commit equal the recorded state. It rebuilds if either changes, which also handles an upstream tag that is unexpectedly moved. It writes state via a temporary file and atomic rename after all image tags have been pushed.

If publishing succeeds but committing the state update fails, the next run may rebuild the same image. This is safe and preferable to recording an image that was never published. The workflow logs this condition explicitly. It does not attempt automatic cleanup or deletion of existing GHCR versions.

## GitHub Actions workflow

.github/workflows/build-images.yml has only these triggers:

    schedule:
      - cron: "0 */6 * * *"
    workflow_dispatch:

Manual dispatch accepts a target input with default all. It accepts a target ID or all; it never accepts an upstream tag. Scheduled runs select all. With the initial repository state, both paths build or skip only nanobot.

The workflow performs these ordered actions:

1. Check out the overlay repository and configure the bot identity used only for state commits.
2. Validate requested target IDs and each target configuration.
3. Use the GitHub runner's Docker Engine and authenticate to ghcr.io with the workflow GITHUB_TOKEN.
4. Run the generic engine once per selected target. The engine resolves the latest tag, clones upstream into a mktemp directory, applies patches, invokes the target adapter, and publishes latest plus the upstream tag.
5. Commit and push changed state/*.json files only after every selected target finished successfully.

The workflow uses a repository-wide concurrency group with cancel-in-progress: false. A later scheduled run waits for an active build rather than racing it or overwriting its state update.

Required permissions are:

    permissions:
      contents: write
      packages: write

contents: write is necessary only because the successful workflow records the current build state in the repository. The workflow is not triggered by pushes, so its state commit cannot create a build loop.

The workflow uses GITHUB_TOKEN for GHCR. The user-provided personal access token is not written to Actions secrets, target files, shell history, Docker build arguments, labels, or image layers. It is relevant only to authenticating the local GitHub client for the initial repository push or other explicitly requested GitHub operations.

## Local development

scripts/build-local.sh <target> is the supported local entry point. It requires exactly one target ID and always resolves that target's latest matching upstream tag. It does not accept a version argument. It runs the generic target engine with publication disabled, prints the resolved tag and SHA, and leaves a local image tagged as <image>:latest and <image>:<upstream-tag>.

The engine clones upstream into a mktemp directory and registers cleanup with trap, so no source/ directory is ever written to the repository. A .gitignore entry covers any intentionally retained local Docker artifacts, but build inputs themselves remain outside the checkout.

## Validation and test strategy

Implementation follows test-driven development. Production shell logic is split so deterministic parts can run without GitHub, Docker, or network access.

The test suite covers at least these observable behaviors:

- Selecting the highest accepted stable and .postN tag from fixture output.
- Rejecting an invalid target ID, missing target file, invalid JSON, unsupported registry, and a target outside the requested selection.
- Skipping only when both the selected tag and resolved SHA match state.
- Rebuilding when the tag changes or when the same tag resolves to a different SHA.
- Applying patches in deterministic order and failing on a bad patch.
- Ensuring local builds reject an explicit historical-tag argument.
- Checking JSON configuration and shell syntax in CI before a scheduled image publication is needed.

Tests use temporary directories and fixture data, never a real GitHub token or GHCR package. Docker build verification is available through the local build script and the publication workflow; it is not faked by unit tests.

## Failure behavior and observability

The scripts use strict shell options, clear error messages, and non-zero exit statuses. They report the target ID, selected tag, and resolved upstream SHA before building. They fail safely in these cases:

- no tag matches the configured pattern;
- upstream checkout or commit resolution fails;
- a patch does not apply;
- the target adapter fails to produce its expected image;
- GHCR authentication or image publication fails; or
- state cannot be committed after publication.

State remains unchanged for every failure before its atomic write. Workflows log enough context to rerun the latest build but never log credentials.

## Future extension path

To add a new upstream project, create targets/<new-id>/target.json, its adapter, Dockerfile, optional patches, configuration templates, and tests. The central engine and workflow remain unchanged if the new target fits the same adapter contract. A genuinely different build class adds a narrowly scoped adapter capability rather than changing nanobot behavior or copying the workflow.

Multi-architecture builds, SBOMs, signing, scanning, release notes, retention policies, and GitHub Releases can be layered on this contract later. None are required for the first working nanobot image builder.

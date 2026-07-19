# Multi-Upstream Docker Image Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build a configuration-driven, GitHub Actions-backed GHCR image builder that currently publishes the latest HKUDS/nanobot image while allowing future upstreams to be added as isolated targets.

**Architecture:** Bash scripts provide a generic target engine for validation, latest-tag resolution, state comparison, patching, source checkout, and publication. Each target owns a compact JSON declaration plus an adapter and final Docker overlay. GitHub Actions only orchestrates the engine, authenticates GHCR with GITHUB_TOKEN, and commits successful state changes.

**Tech Stack:** Bash 5+, jq 1.6+, Git, Docker Engine with BuildKit, GitHub Actions, GHCR, POSIX shell inside the final image.

---

## Execution decisions

- Execute this plan inline in the current session because the requester explicitly authorized continued execution without per-step approval.
- Use the configured Git identity only for local commits. Never stage credentials, generated upstream source, Docker daemon state, or a user configuration directory.
- Use the user-provided PAT only through GitHub CLI's credential store when publishing to the existing remote. It must never appear in source files, workflow YAML, Docker arguments, images, logs, or remote URLs.
- The first target always builds the newest matching tag. No command accepts an upstream tag as an input.

## Planned file structure

| Path | Responsibility |
|---|---|
| .gitignore | Exclude local build artifacts without excluding state records. |
| README.md | Explain the repository model, first target, local usage, GHCR usage, and how to add a target. |
| docs/adding-target.md | Define the target contract and exact future-target onboarding steps. |
| targets/nanobot/target.json | Declare the upstream repository, stable-tag filter, GHCR image, platform, and adapter. |
| targets/nanobot/build.sh | Build the upstream source image and then the nanobot final overlay. |
| targets/nanobot/Dockerfile | Add OCI metadata, entrypoint, healthcheck, and safe templates to the upstream image. |
| targets/nanobot/entrypoint.sh | Validate writable runtime state and execute nanobot. |
| targets/nanobot/healthcheck.sh | Probe the local gateway health endpoint without requiring curl. |
| targets/nanobot/patches/README.md | Describe ordered patch semantics. |
| targets/nanobot/config/README.md | Describe safe configuration-template semantics. |
| scripts/lib/common.sh | Shared path, JSON, target, tag-selection, state, and error helpers. |
| scripts/list-targets.sh | Expand all or one validated target ID. |
| scripts/validate-target.sh | Validate target JSON and local target assets. |
| scripts/resolve-latest-tag.sh | Resolve the newest accepted upstream tag. |
| scripts/apply-patches.sh | Apply target patches deterministically. |
| scripts/build-target.sh | Clone, compare state, call the adapter, push, and record a successful build. |
| scripts/build-local.sh | Run one target's current-latest build without publishing or mutating state. |
| state/.gitkeep | Keep the empty state directory under version control until the first publication. |
| tests/lib/assert.sh | Small dependency-free Bash assertions. |
| tests/fixtures/tags.txt | Deterministic upstream-ref fixture data. |
| tests/test_*.sh | Focused behavior tests for each script contract. |
| tests/run.sh | Execute every focused test in a deterministic order. |
| .github/workflows/test.yml | Run script/configuration tests on pushes and pull requests. |
| .github/workflows/build-images.yml | Scheduled/manual build, GHCR login, and state commit workflow. |

The existing plan.md remains as the original request artifact. The new design and this implementation plan supersede its nanobot-only directory layout with a target-directory model.

## Prerequisite command

The repository scripts intentionally use jq for safe JSON parsing. GitHub-hosted Ubuntu runners include jq. For this local NixOS environment, run tests in an ephemeral jq shell:

    nix shell nixpkgs#jq -c bash tests/run.sh

Expected result after the relevant tasks: every test prints PASS and the command exits 0.

### Task 1: Establish a dependency-free Bash test harness

**Files:**

- Create: tests/lib/assert.sh
- Create: tests/run.sh
- Create: tests/test_harness.sh
- Create: .gitignore

- [ ] **Step 1: Write the failing harness test**

Create tests/test_harness.sh before the assertion helper exists:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    [ -f "$ROOT/tests/lib/assert.sh" ] || {
      printf 'FAIL: assertion helper is missing\n' >&2
      exit 1
    }
    source "$ROOT/tests/lib/assert.sh"

    assert_eq "same strings compare" "nanobot" "nanobot"
    assert_contains "contains finds substring" "nanobot-image-builder" "image"
    assert_status "status comparison succeeds" 0 bash -c 'exit 0'

Run:

    bash tests/test_harness.sh

Expected: FAIL because tests/lib/assert.sh does not exist.

- [ ] **Step 2: Add the assertion helper and runner**

Create tests/lib/assert.sh:

    #!/usr/bin/env bash
    set -euo pipefail

    fail() {
      printf 'FAIL: %s\n' "$1" >&2
      exit 1
    }

    assert_eq() {
      local message="$1"
      local expected="$2"
      local actual="$3"
      [ "$expected" = "$actual" ] || fail "$message: expected [$expected], got [$actual]"
    }

    assert_contains() {
      local message="$1"
      local haystack="$2"
      local needle="$3"
      case "$haystack" in
        *"$needle"*) ;;
        *) fail "$message: missing [$needle]" ;;
      esac
    }

    assert_status() {
      local message="$1"
      local expected="$2"
      shift 2
      set +e
      "$@"
      local actual=$?
      set -e
      [ "$expected" -eq "$actual" ] || fail "$message: expected status $expected, got $actual"
    }

    pass() {
      printf 'PASS: %s\n' "$1"
    }

Create tests/run.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    found=0

    for test_file in "$ROOT"/tests/test_*.sh; do
      [ -e "$test_file" ] || continue
      found=1
      bash "$test_file"
    done

    [ "$found" -eq 1 ] || {
      printf 'FAIL: no tests discovered\n' >&2
      exit 1
    }

Create .gitignore:

    .DS_Store
    .direnv/
    result
    .local-build/
    *.log

Make all test scripts executable.

- [ ] **Step 3: Verify the harness turns green**

Run:

    bash tests/run.sh

Expected: one PASS line from tests/test_harness.sh and exit 0. Add pass "harness assertions" as the final line of tests/test_harness.sh after its assertions.

- [ ] **Step 4: Commit the test foundation**

Run:

    git add .gitignore tests
    git commit -m "test: add bash test harness"


### Task 2: Add the nanobot declaration and target validation

**Files:**

- Create: targets/nanobot/target.json
- Create: targets/nanobot/patches/README.md
- Create: targets/nanobot/config/README.md
- Create: scripts/lib/common.sh
- Create: scripts/validate-target.sh
- Create: scripts/list-targets.sh
- Create: tests/test_target_validation.sh

- [ ] **Step 1: Write failing validation tests**

Create tests/test_target_validation.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/tests/lib/assert.sh"

    assert_status "nanobot target validates" 0 "$ROOT/scripts/validate-target.sh" nanobot
    assert_status "path traversal target is rejected" 1 "$ROOT/scripts/validate-target.sh" ../nanobot
    assert_eq "all expands to nanobot" "nanobot" "$("$ROOT/scripts/list-targets.sh" all)"
    assert_status "unknown target is rejected" 1 "$ROOT/scripts/list-targets.sh" missing-target
    pass "target validation"

Run:

    nix shell nixpkgs#jq -c bash tests/test_target_validation.sh

Expected: FAIL because the validation scripts and target declaration do not exist.

- [ ] **Step 2: Create the target declaration and target documentation**

Create targets/nanobot/target.json:

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

Create targets/nanobot/patches/README.md:

    # nanobot patches

    Files ending in .patch are applied to the checked-out upstream source in lexicographic filename order. A patch conflict stops the build before image publication. Keep this directory empty when no source change is required.

Create targets/nanobot/config/README.md:

    # nanobot configuration templates

    This directory contains non-secret examples only. Templates are copied to /opt/nanobot-overlay/config in the final image and never overwrite a mounted runtime ~/.nanobot directory.

- [ ] **Step 3: Implement common target helpers**

Create scripts/lib/common.sh:

    #!/usr/bin/env bash
    set -euo pipefail

    REPO_ROOT="$(git rev-parse --show-toplevel)"

    die() {
      printf 'error: %s\n' "$1" >&2
      exit 1
    }

    require_command() {
      command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
    }

    valid_target_id() {
      [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
    }

    target_dir() {
      valid_target_id "$1" || die "invalid target id: $1"
      printf '%s/targets/%s\n' "$REPO_ROOT" "$1"
    }

    target_config() {
      printf '%s/target.json\n' "$(target_dir "$1")"
    }

    target_field() {
      local target="$1"
      local query="$2"
      jq -er "$query" "$(target_config "$target")"
    }

    safe_target_file_name() {
      [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
    }

Create scripts/validate-target.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/scripts/lib/common.sh"

    [ "$#" -eq 1 ] || die "usage: validate-target.sh <target-id>"
    require_command jq
    target="$1"
    directory="$(target_dir "$target")"
    config="$(target_config "$target")"

    [ -d "$directory" ] || die "target directory not found: $target"
    [ -f "$config" ] || die "target configuration not found: $target"
    jq -e '
      .schemaVersion == 1 and
      (.id | type == "string") and
      (.upstream.repository | type == "string") and
      (.upstream.tagPattern | type == "string") and
      (.image.repository | type == "string") and
      (.image.platform == "linux/amd64") and
      (.build.adapter | type == "string") and
      (.build.dockerfile | type == "string")
    ' "$config" >/dev/null || die "invalid target JSON: $target"

    [ "$(target_field "$target" '.id')" = "$target" ] || die "target id does not match directory: $target"
    image="$(target_field "$target" '.image.repository')"
    case "$image" in
      ghcr.io/*) ;;
      *) die "image repository must use ghcr.io: $image" ;;
    esac

    printf '%s\n' "$target"

Create scripts/list-targets.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/scripts/lib/common.sh"

    [ "$#" -eq 1 ] || die "usage: list-targets.sh <all|target-id>"
    selection="$1"

    if [ "$selection" = "all" ]; then
      find "$ROOT/targets" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort | while IFS= read -r target; do
        "$ROOT/scripts/validate-target.sh" "$target" >/dev/null
        printf '%s\n' "$target"
      done
    else
      "$ROOT/scripts/validate-target.sh" "$selection" >/dev/null
      printf '%s\n' "$selection"
    fi

- [ ] **Step 4: Verify validation and JSON syntax**

Run:

    nix shell nixpkgs#jq -c bash tests/test_target_validation.sh
    nix shell nixpkgs#jq -c jq empty targets/nanobot/target.json

Expected: all validation assertions pass and jq reports no JSON error.

- [ ] **Step 5: Commit target validation**

Run:

    git add scripts targets tests/test_target_validation.sh
    git commit -m "feat: add target validation"


### Task 3: Resolve latest tags and implement state decisions

**Files:**

- Create: tests/fixtures/tags.txt
- Create: tests/test_tag_and_state.sh
- Modify: scripts/lib/common.sh
- Create: scripts/resolve-latest-tag.sh

- [ ] **Step 1: Write failing resolver and state tests**

Create tests/fixtures/tags.txt:

    1111111111111111111111111111111111111111	refs/tags/v0.1.5
    2222222222222222222222222222222222222222	refs/tags/v0.1.5.post3
    3333333333333333333333333333333333333333	refs/tags/v0.2.2
    4444444444444444444444444444444444444444	refs/tags/v0.3.0-rc1

Create tests/test_tag_and_state.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/tests/lib/assert.sh"
    source "$ROOT/scripts/lib/common.sh"

    pattern='^v[0-9]+(\.[0-9]+)+(\.post[0-9]+)?$'
    assert_status "tag selector exists" 0 select_latest_tag_from_file "$ROOT/tests/fixtures/tags.txt" "$pattern"
    selected="$(select_latest_tag_from_file "$ROOT/tests/fixtures/tags.txt" "$pattern")"
    assert_eq "highest stable tag is selected" "v0.2.2" "$selected"

    temp="$(mktemp -d)"
    trap 'rm -rf "$temp"' EXIT
    STATE_DIR="$temp/state"
    mkdir -p "$STATE_DIR"

    state_needs_build "nanobot" "v0.2.2" "abc123"
    write_state "nanobot" "HKUDS/nanobot" "v0.2.2" "abc123" "ghcr.io/sakiko999/nanobot" "overlay123" "2026-07-19T00:00:00Z"
    assert_status "same tag and commit skip" 1 state_needs_build "nanobot" "v0.2.2" "abc123"
    state_needs_build "nanobot" "v0.2.2" "different"
    state_needs_build "nanobot" "v0.2.3" "abc123"
    pass "tag resolution and state"

Run:

    nix shell nixpkgs#jq -c bash tests/test_tag_and_state.sh

Expected: FAIL because select_latest_tag_from_file, state_needs_build, and write_state do not exist.

- [ ] **Step 2: Add deterministic tag and state functions**

Append these definitions to scripts/lib/common.sh after the Task 2 helpers:

    STATE_DIR="$REPO_ROOT/state"

    state_file() {
      printf '%s/%s.json\n' "$STATE_DIR" "$1"
    }

    select_latest_tag_from_file() {
      local refs_file="$1"
      local pattern="$2"
      local tags
      tags="$(awk '{sub(/^refs\/tags\//, "", $2); print $2}' "$refs_file" | grep -E "$pattern" || true)"
      [ -n "$tags" ] || die "no upstream tag matched pattern: $pattern"
      printf '%s\n' "$tags" | LC_ALL=C sort -V | tail -n 1
    }

    state_needs_build() {
      local target="$1"
      local tag="$2"
      local commit="$3"
      local file
      file="$(state_file "$target")"
      [ -f "$file" ] || return 0
      local saved_tag
      local saved_commit
      saved_tag="$(jq -er '.upstream.tag' "$file")"
      saved_commit="$(jq -er '.upstream.commit' "$file")"
      [ "$saved_tag" = "$tag" ] && [ "$saved_commit" = "$commit" ] && return 1
      return 0
    }

    write_state() {
      local target="$1"
      local repository="$2"
      local tag="$3"
      local commit="$4"
      local image="$5"
      local overlay_commit="$6"
      local built_at="$7"
      local file
      local temporary
      mkdir -p "$STATE_DIR"
      file="$(state_file "$target")"
      temporary="$(mktemp "$STATE_DIR/.state.XXXXXX")"
      jq -n --arg target "$target" --arg repository "$repository" --arg tag "$tag" --arg commit "$commit" --arg image "$image" --arg overlay "$overlay_commit" --arg built_at "$built_at" '{schemaVersion: 1, target: $target, upstream: {repository: $repository, tag: $tag, commit: $commit}, image: {repository: $image, tags: ["latest", $tag]}, overlayCommit: $overlay, builtAt: $built_at}' >"$temporary"
      mv "$temporary" "$file"
    }

Create scripts/resolve-latest-tag.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/scripts/lib/common.sh"

    [ "$#" -eq 1 ] || die "usage: resolve-latest-tag.sh <target-id>"
    require_command git
    require_command jq
    target="$1"
    "$ROOT/scripts/validate-target.sh" "$target" >/dev/null
    repository="$(target_field "$target" '.upstream.repository')"
    pattern="$(target_field "$target" '.upstream.tagPattern')"
    refs="$(mktemp)"
    trap 'rm -f "$refs"' EXIT
    git ls-remote --tags --refs "https://github.com/$repository.git" >"$refs"
    select_latest_tag_from_file "$refs" "$pattern"

- [ ] **Step 3: Verify tag selection and state serialization**

Run:

    nix shell nixpkgs#jq -c bash tests/test_tag_and_state.sh
    nix shell nixpkgs#jq -c bash -n scripts/lib/common.sh
    nix shell nixpkgs#jq -c bash -n scripts/resolve-latest-tag.sh

Expected: every assertion passes, and both scripts have valid Bash syntax.

- [ ] **Step 4: Commit tag/state behavior**

Run:

    git add scripts tests/fixtures tests/test_tag_and_state.sh
    git commit -m "feat: track latest upstream state"


### Task 4: Apply patches deterministically

**Files:**

- Create: scripts/apply-patches.sh
- Create: tests/test_patch_application.sh

- [ ] **Step 1: Write the failing patch tests**

Create tests/test_patch_application.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/tests/lib/assert.sh"

    temp="$(mktemp -d)"
    trap 'rm -rf "$temp"' EXIT
    source_dir="$temp/source"
    patch_dir="$temp/patches"
    mkdir -p "$source_dir" "$patch_dir"
    printf 'one\n' >"$source_dir/message.txt"

    cat >"$patch_dir/10-first.patch" <<'PATCH'
    --- a/message.txt
    +++ b/message.txt
    @@ -1 +1 @@
    -one
    +two
    PATCH

    cat >"$patch_dir/20-second.patch" <<'PATCH'
    --- a/message.txt
    +++ b/message.txt
    @@ -1 +1 @@
    -two
    +three
    PATCH

    assert_status "patch script applies patches" 0 "$ROOT/scripts/apply-patches.sh" "$patch_dir" "$source_dir"
    assert_eq "patches apply in lexical order" "three" "$(cat "$source_dir/message.txt")"

    printf 'one\n' >"$source_dir/message.txt"
    printf 'invalid patch\n' >"$patch_dir/30-bad.patch"
    assert_status "bad patch fails" 1 "$ROOT/scripts/apply-patches.sh" "$patch_dir" "$source_dir"
    pass "patch application"

Run:

    bash tests/test_patch_application.sh

Expected: FAIL because scripts/apply-patches.sh does not exist.

- [ ] **Step 2: Implement the patch script**

Create scripts/apply-patches.sh:

    #!/usr/bin/env bash
    set -euo pipefail

    [ "$#" -eq 2 ] || {
      printf 'error: usage: apply-patches.sh <patch-directory> <source-directory>\n' >&2
      exit 1
    }

    patch_directory="$1"
    source_directory="$2"
    [ -d "$patch_directory" ] || {
      printf 'error: patch directory not found: %s\n' "$patch_directory" >&2
      exit 1
    }
    [ -d "$source_directory" ] || {
      printf 'error: source directory not found: %s\n' "$source_directory" >&2
      exit 1
    }

    for patch_file in "$patch_directory"/*.patch; do
      [ -e "$patch_file" ] || continue
      printf 'applying patch: %s\n' "$(basename "$patch_file")"
      patch -d "$source_directory" -p1 <"$patch_file"
    done

- [ ] **Step 3: Verify patch behavior and Bash syntax**

Run:

    bash tests/test_patch_application.sh
    bash -n scripts/apply-patches.sh

Expected: the ordered patch test passes, the intentionally bad patch exits 1, and syntax validation exits 0.

- [ ] **Step 4: Commit patch support**

Run:

    git add scripts/apply-patches.sh tests/test_patch_application.sh
    git commit -m "feat: apply target patches deterministically"


### Task 5: Add generic local and publication build orchestration

**Files:**

- Create: scripts/build-target.sh
- Create: scripts/build-local.sh
- Create: state/.gitkeep
- Create: tests/test_local_cli.sh

- [ ] **Step 1: Write failing local command tests**

Create tests/test_local_cli.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/tests/lib/assert.sh"

    assert_status "local build requires a target" 1 "$ROOT/scripts/build-local.sh"
    assert_status "local build rejects a version argument" 1 "$ROOT/scripts/build-local.sh" nanobot v0.2.2
    assert_status "local build rejects invalid target id before Docker" 1 "$ROOT/scripts/build-local.sh" ../nanobot
    pass "local build command contract"

Run:

    bash tests/test_local_cli.sh

Expected: FAIL because scripts/build-local.sh does not exist.

- [ ] **Step 2: Add the generic driver**

Create scripts/build-target.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/scripts/lib/common.sh"

    publish=0
    if [ "$#" -eq 2 ] && [ "$1" = "--publish" ]; then
      publish=1
      shift
    fi
    [ "$#" -eq 1 ] || die "usage: build-target.sh [--publish] <target-id>"

    require_command git
    require_command jq
    require_command docker
    target="$1"
    "$ROOT/scripts/validate-target.sh" "$target" >/dev/null

    repository="$(target_field "$target" '.upstream.repository')"
    image_repository="$(target_field "$target" '.image.repository')"
    adapter_name="$(target_field "$target" '.build.adapter')"
    target_directory="$(target_dir "$target")"
    upstream_tag="$("$ROOT/scripts/resolve-latest-tag.sh" "$target")"
    temporary="$(mktemp -d)"
    trap 'rm -rf "$temporary"' EXIT
    source_directory="$temporary/source"

    git clone --depth 1 --branch "$upstream_tag" "https://github.com/$repository.git" "$source_directory"
    upstream_sha="$(git -C "$source_directory" rev-parse HEAD)"

    if [ "$publish" -eq 1 ] && ! state_needs_build "$target" "$upstream_tag" "$upstream_sha"; then
      printf 'skip: %s already published at %s (%s)\n' "$target" "$upstream_tag" "$upstream_sha"
      exit 0
    fi

    "$ROOT/scripts/apply-patches.sh" "$target_directory/patches" "$source_directory"
    overlay_sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'local')"

    export REPO_ROOT="$ROOT"
    export TARGET_DIR="$target_directory"
    export SOURCE_DIR="$source_directory"
    export UPSTREAM_TAG="$upstream_tag"
    export UPSTREAM_SHA="$upstream_sha"
    export IMAGE_REPOSITORY="$image_repository"
    export IMAGE_TAG="$upstream_tag"
    export OVERLAY_SHA="$overlay_sha"
    "$target_directory/$adapter_name"

    if [ "$publish" -eq 1 ]; then
      docker push "$image_repository:latest"
      docker push "$image_repository:$upstream_tag"
      write_state "$target" "$repository" "$upstream_tag" "$upstream_sha" "$image_repository" "$overlay_sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi

Create scripts/build-local.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

    [ "$#" -eq 1 ] || {
      printf 'error: usage: build-local.sh <target-id>\n' >&2
      exit 1
    }

    exec "$ROOT/scripts/build-target.sh" "$1"

Create state/.gitkeep as an empty file. Make both scripts executable.

- [ ] **Step 3: Verify command contract and driver syntax**

Run:

    bash tests/test_local_cli.sh
    bash -n scripts/build-target.sh
    bash -n scripts/build-local.sh

Expected: all argument-rejection assertions pass without requiring Docker, and syntax checks exit 0.

- [ ] **Step 4: Commit the generic engine**

Run:

    git add scripts/build-target.sh scripts/build-local.sh state tests/test_local_cli.sh
    git commit -m "feat: add generic image build engine"


### Task 6: Implement the nanobot build adapter and final container contract

**Files:**

- Create: targets/nanobot/build.sh
- Create: targets/nanobot/Dockerfile
- Create: targets/nanobot/entrypoint.sh
- Create: targets/nanobot/healthcheck.sh
- Modify: scripts/validate-target.sh
- Create: tests/test_nanobot_image_contract.sh

- [ ] **Step 1: Write the failing image-contract test**

Create tests/test_nanobot_image_contract.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/tests/lib/assert.sh"

    assert_status "Dockerfile exists" 0 test -f "$ROOT/targets/nanobot/Dockerfile"
    assert_status "entrypoint exists" 0 test -f "$ROOT/targets/nanobot/entrypoint.sh"
    assert_status "healthcheck exists" 0 test -f "$ROOT/targets/nanobot/healthcheck.sh"
    dockerfile="$(cat "$ROOT/targets/nanobot/Dockerfile")"
    entrypoint="$(cat "$ROOT/targets/nanobot/entrypoint.sh")"
    healthcheck="$(cat "$ROOT/targets/nanobot/healthcheck.sh")"

    assert_contains "Dockerfile accepts a base image" "$dockerfile" "ARG BASE_IMAGE"
    assert_contains "Dockerfile exposes gateway health port" "$dockerfile" "EXPOSE 18790"
    assert_contains "Dockerfile exposes WebUI port" "$dockerfile" "EXPOSE 8765"
    assert_contains "Dockerfile sets gateway default" "$dockerfile" "CMD [\"gateway\"]"
    assert_contains "entrypoint checks writable state" "$entrypoint" "not writable"
    assert_contains "healthcheck probes endpoint" "$healthcheck" "/health"
    assert_status "target assets validate" 0 "$ROOT/scripts/validate-target.sh" nanobot
    pass "nanobot image contract"

Run:

    bash tests/test_nanobot_image_contract.sh

Expected: FAIL because the target Dockerfile and runtime scripts do not exist.

- [ ] **Step 2: Implement the real adapter, Docker overlay, and asset validation**

Create targets/nanobot/build.sh:

    #!/usr/bin/env bash
    set -euo pipefail

    [ -n "$SOURCE_DIR" ]
    [ -n "$TARGET_DIR" ]
    [ -n "$IMAGE_REPOSITORY" ]
    [ -n "$IMAGE_TAG" ]
    [ -n "$UPSTREAM_SHA" ]

    platform="$(jq -er '.image.platform' "$TARGET_DIR/target.json")"
    base_image="local/nanobot-upstream:$UPSTREAM_SHA"

    docker build --platform "$platform" --file "$SOURCE_DIR/Dockerfile" --tag "$base_image" "$SOURCE_DIR"

    docker build --platform "$platform" --file "$TARGET_DIR/Dockerfile" --build-arg BASE_IMAGE="$base_image" --build-arg UPSTREAM_TAG="$UPSTREAM_TAG" --build-arg UPSTREAM_SHA="$UPSTREAM_SHA" --build-arg OVERLAY_SHA="$OVERLAY_SHA" --tag "$IMAGE_REPOSITORY:latest" --tag "$IMAGE_REPOSITORY:$IMAGE_TAG" "$REPO_ROOT"

Create targets/nanobot/Dockerfile:

    ARG BASE_IMAGE
    FROM $BASE_IMAGE

    ARG UPSTREAM_TAG
    ARG UPSTREAM_SHA
    ARG OVERLAY_SHA

    LABEL org.opencontainers.image.source="https://github.com/HKUDS/nanobot"
    LABEL org.opencontainers.image.version="$UPSTREAM_TAG"
    LABEL org.opencontainers.image.revision="$UPSTREAM_SHA"
    LABEL org.opencontainers.image.vendor="sakiko999"
    LABEL io.github.sakiko999.nanobot.overlay-revision="$OVERLAY_SHA"

    COPY --chmod=0755 targets/nanobot/entrypoint.sh /usr/local/bin/nanobot-overlay-entrypoint
    COPY --chmod=0755 targets/nanobot/healthcheck.sh /usr/local/bin/nanobot-healthcheck
    COPY targets/nanobot/config/ /opt/nanobot-overlay/config/

    EXPOSE 18790 8765
    HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["/usr/local/bin/nanobot-healthcheck"]

    ENTRYPOINT ["/usr/local/bin/nanobot-overlay-entrypoint"]
    CMD ["gateway"]

Create targets/nanobot/entrypoint.sh:

    #!/bin/sh
    set -eu

    data_dir="$(printenv NANOBOT_HOME 2>/dev/null || true)"
    if [ -z "$data_dir" ]; then
      data_dir="$HOME/.nanobot"
    fi

    if [ -d "$data_dir" ] && [ ! -w "$data_dir" ]; then
      printf 'Error: %s is not writable; mount a directory writable by the container user.\n' "$data_dir" >&2
      exit 1
    fi

    exec nanobot "$@"

Create targets/nanobot/healthcheck.sh:

    #!/bin/sh
    set -eu

    health_url="$(printenv NANOBOT_HEALTH_URL 2>/dev/null || true)"
    if [ -z "$health_url" ]; then
      health_url="http://127.0.0.1:18790/health"
    fi

    exec python - "$health_url" <<'PY'
    import sys
    import urllib.request

    with urllib.request.urlopen(sys.argv[1], timeout=3) as response:
        if response.status != 200:
            raise SystemExit("unexpected health status: %s" % response.status)
    PY

Make the adapter, entrypoint, and healthcheck executable.

Extend scripts/validate-target.sh after its image-repository check so target metadata also requires its declared build assets:

    adapter="$(target_field "$target" '.build.adapter')"
    dockerfile="$(target_field "$target" '.build.dockerfile')"
    safe_target_file_name "$adapter" || die "unsafe adapter name: $adapter"
    safe_target_file_name "$dockerfile" || die "unsafe Dockerfile name: $dockerfile"
    [ -x "$directory/$adapter" ] || die "target adapter is not executable: $adapter"
    [ -f "$directory/$dockerfile" ] || die "target Dockerfile not found: $dockerfile"

- [ ] **Step 3: Verify static image behavior**

Run:

    bash tests/test_nanobot_image_contract.sh
    bash -n targets/nanobot/build.sh
    sh -n targets/nanobot/entrypoint.sh
    sh -n targets/nanobot/healthcheck.sh

Expected: all contract assertions and syntax checks exit 0.

- [ ] **Step 4: Run a real local image build when Docker is available**

Run:

    ./scripts/build-local.sh nanobot

Expected: it reports the resolved latest tag and source SHA, builds the upstream base and final overlay, then leaves ghcr.io/sakiko999/nanobot:latest and ghcr.io/sakiko999/nanobot:<tag> locally. If Docker is unavailable locally, record that limitation and defer the full build to the first GitHub Actions run rather than faking success.

- [ ] **Step 5: Commit the nanobot target**

Run:

    git add targets tests/test_nanobot_image_contract.sh
    git commit -m "feat: add nanobot image target"


### Task 7: Add test and publication workflows

**Files:**

- Create: .github/workflows/test.yml
- Create: .github/workflows/build-images.yml
- Create: tests/test_workflow_contract.sh

- [ ] **Step 1: Write the failing workflow contract test**

Create tests/test_workflow_contract.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/tests/lib/assert.sh"

    assert_status "publication workflow exists" 0 test -f "$ROOT/.github/workflows/build-images.yml"
    assert_status "test workflow exists" 0 test -f "$ROOT/.github/workflows/test.yml"
    workflow="$(cat "$ROOT/.github/workflows/build-images.yml")"
    tests_workflow="$(cat "$ROOT/.github/workflows/test.yml")"

    assert_contains "publication workflow is scheduled" "$workflow" "0 */6 * * *"
    assert_contains "publication workflow is manually dispatchable" "$workflow" "workflow_dispatch:"
    assert_contains "publication workflow can push state" "$workflow" "contents: write"
    assert_contains "publication workflow can publish packages" "$workflow" "packages: write"
    assert_contains "publication workflow uses GITHUB_TOKEN" "$workflow" "GITHUB_TOKEN"
    assert_contains "test workflow runs script tests" "$tests_workflow" "tests/run.sh"
    pass "workflow contract"

Run:

    bash tests/test_workflow_contract.sh

Expected: FAIL because neither workflow exists.

- [ ] **Step 2: Add the continuous test workflow**

Create .github/workflows/test.yml:

    name: Test image builder

    on:
      push:
      pull_request:

    permissions:
      contents: read

    jobs:
      test:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - name: Run Bash and configuration tests
            run: bash tests/run.sh

- [ ] **Step 3: Add the scheduled/manual publication workflow**

Create .github/workflows/build-images.yml. Replace ${{ github.event.inputs.target || 'all' }}, ${{ github.repository }}, ${{ github.actor }}, and ${{ secrets.GITHUB_TOKEN }} with the GitHub Actions expression values listed immediately below.

    name: Build container images

    on:
      schedule:
        - cron: "0 */6 * * *"
      workflow_dispatch:
        inputs:
          target:
            description: Target ID or all; always resolves the newest accepted upstream tag
            required: false
            default: all
            type: string

    permissions:
      contents: write
      packages: write

    concurrency:
      group: image-build-${{ github.repository }}
      cancel-in-progress: false

    jobs:
      build:
        runs-on: ubuntu-latest
        env:
          TARGET: ${{ github.event.inputs.target || 'all' }}
        steps:
          - uses: actions/checkout@v4
            with:
              fetch-depth: 0

          - uses: docker/login-action@v3
            with:
              registry: ghcr.io
              username: ${{ github.actor }}
              password: ${{ secrets.GITHUB_TOKEN }}

          - name: Run repository tests
            run: bash tests/run.sh

          - name: Build selected latest targets
            run: |
              while IFS= read -r target; do
                ./scripts/build-target.sh --publish "$target"
              done < <(./scripts/list-targets.sh "$TARGET")

          - name: Commit successful build state
            run: |
              if git diff --quiet -- state; then
                exit 0
              fi
              git config user.name "github-actions[bot]"
              git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
              git add state
              git commit -m "chore: record latest image builds"
              git push

Use these exact replacements:

    ${{ github.event.inputs.target || 'all' }} = GitHub event input target, falling back to all
    ${{ github.repository }} = current GitHub repository
    ${{ github.actor }} = current GitHub actor
    ${{ secrets.GITHUB_TOKEN }} = repository GITHUB_TOKEN secret

- [ ] **Step 4: Verify workflow contract and all tests**

Run:

    bash tests/test_workflow_contract.sh
    nix shell nixpkgs#jq -c bash tests/run.sh

Expected: the workflow contract and the full test suite pass.

- [ ] **Step 5: Commit CI workflows**

Run:

    git add .github tests/test_workflow_contract.sh
    git commit -m "ci: automate image builds"


### Task 8: Write operator and contributor documentation

**Files:**

- Create: README.md
- Create: docs/adding-target.md
- Create: tests/test_documentation_contract.sh
- Track: plan.md as the original request artifact

- [ ] **Step 1: Write documentation contract checks**

Create tests/test_documentation_contract.sh:

    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
    source "$ROOT/tests/lib/assert.sh"

    assert_status "README exists" 0 test -f "$ROOT/README.md"
    assert_status "target documentation exists" 0 test -f "$ROOT/docs/adding-target.md"
    readme="$(cat "$ROOT/README.md")"
    target_docs="$(cat "$ROOT/docs/adding-target.md")"

    assert_contains "README names nanobot" "$readme" "HKUDS/nanobot"
    assert_contains "README documents local build" "$readme" "./scripts/build-local.sh nanobot"
    assert_contains "README documents GHCR tags" "$readme" ":latest"
    assert_contains "target documentation names target JSON" "$target_docs" "target.json"
    assert_contains "target documentation forbids source forks" "$target_docs" "must not commit upstream source"
    pass "documentation contract"

Run:

    bash tests/test_documentation_contract.sh

Expected: FAIL because the documentation files do not exist.

- [ ] **Step 2: Create README.md**

Write README.md with these sections and commands:

    # Docker Image Builder

    This repository is a delivery layer for upstream projects. It does not fork or commit upstream source code.

    ## Current target

    - HKUDS/nanobot
    - Latest accepted Git tag only
    - ghcr.io/sakiko999/nanobot:latest
    - ghcr.io/sakiko999/nanobot:<upstream-tag>

    ## Local build

        nix shell nixpkgs#jq -c ./scripts/build-local.sh nanobot

    The local command always resolves the latest matching upstream tag and never accepts a historical tag.

    ## Container runtime

    Mount persistent nanobot state at /home/nanobot/.nanobot. Configure public listener addresses and WebSocket tokens in that mounted configuration; the image intentionally does not embed secrets.

    ## Automation

    build-images.yml checks targets every six hours and can be started manually with target=nanobot or target=all. It uses GITHUB_TOKEN for GHCR, then commits a state file only after successful publication.

    ## Add a target

    Read docs/adding-target.md. A target adds its own declaration, build adapter, Dockerfile, tests, and optional patch/configuration directories; it must not commit upstream source.

- [ ] **Step 3: Create docs/adding-target.md**

Document this exact onboarding sequence:

1. Create targets/<id>/target.json with schemaVersion 1, a validated id, a public GHCR image reference, a stable tag pattern, linux/amd64, build.sh, and Dockerfile.
2. Write target-specific tests before the adapter and Dockerfile.
3. Ensure the adapter consumes the environment variables listed in the design document and produces latest plus the upstream-tag image tags.
4. Put source changes only in ordered patch files and non-secret examples only in config/.
5. Add the target to fixture-driven script tests and run the full test suite.
6. Never commit upstream source, generated build context, tokens, or user runtime configuration.

- [ ] **Step 4: Verify documentation and repository tests**

Run:

    bash tests/test_documentation_contract.sh
    nix shell nixpkgs#jq -c bash tests/run.sh
    git diff --check

Expected: documentation assertions pass, all script tests pass, and Git reports no whitespace errors.

- [ ] **Step 5: Commit documentation**

Run:

    git add README.md docs plan.md tests/test_documentation_contract.sh
    git commit -m "docs: document image builder usage"


### Task 9: Authenticate safely, push, and perform the first remote build

**Files:**

- Modify: no repository files unless a verification failure identifies a code defect.

- [ ] **Step 1: Confirm local history and worktree contents**

Run:

    git status --short
    git log --oneline --decorate -10
    nix shell nixpkgs#jq -c bash tests/run.sh

Expected: only intentional project files are tracked, the final test suite passes, and no credential file is present.

- [ ] **Step 2: Install GitHub CLI ephemerally and authenticate without exposing the PAT**

Run GitHub CLI from an ephemeral Nix shell. Start an interactive command that reads the token from standard input:

    nix shell nixpkgs#gh -c gh auth login --hostname github.com --git-protocol https --with-token

Provide the PAT only through the interactive standard-input channel. Do not put it in a shell command, URL, environment dump, repository file, or commit message.

Then verify without printing the token:

    nix shell nixpkgs#gh -c gh auth status
    nix shell nixpkgs#gh -c gh api user --jq .login

Expected: GitHub CLI reports an authenticated GitHub account and the API returns its login.

- [ ] **Step 3: Push without embedding credentials in the remote URL**

Configure the Git credential helper through GitHub CLI:

    nix shell nixpkgs#gh -c gh auth setup-git
    git push https://github.com/sakiko999/docker-image-builder.git master

Expected: the initial project history reaches the existing GitHub repository. The configured SSH origin remains unchanged because the HTTPS URL is supplied only to this push command.

- [ ] **Step 4: Trigger and inspect the first nanobot build**

Run:

    nix shell nixpkgs#gh -c gh workflow run build-images.yml --repo sakiko999/docker-image-builder --ref master -f target=nanobot
    nix shell nixpkgs#gh -c gh run list --repo sakiko999/docker-image-builder --workflow build-images.yml --limit 1

Expected: a new workflow run starts. Monitor its result with short polls, reporting progress at least once per minute. A successful run publishes ghcr.io/sakiko999/nanobot:latest and its upstream-tag companion, then commits state/nanobot.json.

- [ ] **Step 5: Verify the published state and package metadata**

Run after the workflow succeeds:

    git fetch https://github.com/sakiko999/docker-image-builder.git master
    git show FETCH_HEAD:state/nanobot.json
    nix shell nixpkgs#gh -c gh api /users/sakiko999/packages/container/nanobot/versions --jq '.[0].metadata.container.tags'

Expected: the state records the selected upstream tag and commit, and GHCR reports both latest and the selected upstream release tag. If GHCR package visibility or workflow permissions prevent publication, report the exact GitHub error and retain the successful local repository changes without trying to bypass package policy.

## Plan self-review

### Specification coverage

| Design requirement | Implementing task |
|---|---|
| Generic target boundary | Tasks 2, 5, and 8 |
| nanobot as sole real target | Tasks 2 and 6 |
| Latest stable tag only | Tasks 3 and 5 |
| No upstream source retained | Tasks 5 and 8 |
| Target patches/configuration | Tasks 2 and 4 |
| Latest plus upstream tag image tags | Tasks 5 and 6 |
| State-based idempotency | Tasks 3, 5, and 7 |
| Six-hour/manual GHCR workflow | Task 7 |
| Non-secret runtime and healthcheck | Task 6 and Task 8 |
| Unit-level test coverage and TDD | Tasks 1 through 8 |
| Safe PAT use, remote push, first publication | Task 9 |

### Consistency checks

- All target identifiers use nanobot and all state paths use state/nanobot.json.
- Every production script uses the same target ID validation and JSON declaration.
- build-local.sh accepts exactly one target ID and delegates to build-target.sh without --publish, so it cannot accept a historical tag or write state.
- build-target.sh writes state only after both image tags have been pushed.
- GitHub Actions uses GITHUB_TOKEN for GHCR; the PAT is limited to local GitHub authentication.
- The initial image platform is linux/amd64 throughout the declaration, adapter, and design.

### Placeholder scan

The plan contains no deferred implementation marker or unspecified validation step. Every planned behavior has a named file, command, test, and expected outcome.

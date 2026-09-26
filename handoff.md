# Jules handoff: termux-dark-aether (B)

## Current build state, 27 Sep 2026

- [`Aether Update` run 36264478864](https://github.com/psyc-exe/termux-dark-aether/actions/runs/36264478864) passed after PR #7 was merged. Keep its release path separate from the APK problem.
- [`Build Aether Embedded APK` run 36264464222](https://github.com/psyc-exe/termux-dark-aether/actions/runs/36264464222) failed after PR #8 was merged. The failure is now `sdkmanager: command not found` in `install Android SDK 36 + NDK 29 + CMake` (exit 127). PR #8 removed `android-actions/setup-android@v3`, which supplied Android command-line tools. Restore a supported SDK setup or install command-line tools explicitly, then rerun the workflow to expose the next gate. Do not claim an APK build from an SDK-only fix.
- [Jules issue #9](https://github.com/psyc-exe/termux-dark-aether/issues/9) tracks the current failed commit. Avoid another PR that merely changes the step name or assumes `sdkmanager` exists on `ubuntu-latest`.
- The repository still lacks `gradlew`, `settings.gradle`, `app/src/`, and `third_party/termux-x11/`. A complete APK remains blocked until real source and toolchain inputs are supplied. Do not add placeholders or skip the inspection gate.

The older baseline below records what was known at initial handoff; use the current run links above for this failure.

## Context and objective

This is the **B** side of an A/B experiment. B was built with multiple agent harnesses and models. The separate `termux-agenticOS-beyond` repository is A; do not edit A or assume its implementation belongs here.

Take ownership of B's GitHub Actions failures. Work in `psyc-exe/termux-dark-aether` on short branches and open reviewable pull requests. First repair the installer release workflow. Investigate the embedded APK workflow as a separate task because the checkout is missing major build inputs. Keep failures visible rather than making a workflow green by skipping broken steps or publishing placeholder assets.

## Verified state (2026-09-26)

- Repository: `https://github.com/psyc-exe/termux-dark-aether`, `main` at `e1154fd1bfca891206b303a0a8134f4469703cde` when inspected.
- [Aether Update run 36231414386](https://github.com/psyc-exe/termux-dark-aether/actions/runs/36231414386) failed at **checkout** on 2026-09-26. The same workflow failed daily from 2026-09-10 through 2026-09-25. [Initial push run 34365608398](https://github.com/psyc-exe/termux-dark-aether/actions/runs/34365608398) also failed at checkout. These are public job-step conclusions from the GitHub API; the exact log message has not been verified because anonymous log download returned 403.
- [Build Aether Embedded APK run 34365608402](https://github.com/psyc-exe/termux-dark-aether/actions/runs/34365608402) failed at **build Debian rootfs**. Obtain its full log before changing the rootfs recipe.
- `.github/workflows/release.yml` passes `secrets.GH_TOKEN` to `actions/checkout`. Check whether that secret exists. Prefer the built-in `GITHUB_TOKEN` with the minimum required permissions when it is sufficient.
- The release workflow calls `installer/app/patch.sh all`, tags a minute-based name, calls `patch.sh tag`, then starts a second release job with a fresh minute-based name. Those names can diverge. Its asset globs include paths that are not built by the checked-in patch script.
- `installer/app/patch.sh` contains placeholder build steps and suppresses several errors with `|| true`. Do not treat its success exit code as proof that distro, agent, or wallpaper bundles exist.
- The APK checkout contains `app/build.gradle` and `app/AndroidManifest.xml`, but no `gradlew`, `settings.gradle`, `app/src/`, `third_party/termux-x11/`, or `.gitmodules`. `scripts/build-aether-apk.sh` requires several of these. A rootfs fix alone will not produce an APK.
- Baseline host checks passed on this checkout using Git Bash: `bash scripts/qa.sh` and `bash installer/tests/test_ui.sh`. These do not establish Android installation, desktop, GPU, or APK behavior.
- `CONTRIBUTING.md` points to a nonexistent `CLAUDE.md`; `.gitignore` excludes `AGENTS.md`. Jules can use a root `AGENTS.md`, so consider a small separate documentation change after the workflow repair.

## Task 1: installer release workflow

1. Read the failed checkout log, `.github/workflows/release.yml`, `installer/app/patch.sh`, and the installer download/update paths. State the specific failure mechanism in the PR.
2. Make checkout and publishing work with a supported repository token and explicit `contents` permissions. Avoid a custom secret unless it is genuinely required. Never print tokens.
3. Define one release identity from the checked-out commit and use it consistently for tag, release, and assets. Make retries safe and prevent concurrent runs from racing.
4. Package only artifacts that this repository can actually build. If only the tracked installer source is ready, publish that as an honestly named installer archive with a checksum. Do not advertise an APK, rootfs, agent CLI bundle, or wallpaper tarball without building and inspecting it.
5. Keep a validation job for pull requests. Decide whether the daily schedule has a real purpose; if retained, it should not create a duplicate release for an unchanged commit.
6. Update the README's release and installation instructions to match the shipped artifact and the actual repository URL. Remove stale claims about `aether-org/termux-distro` only where they affect this workflow or its use.

**Acceptance for Task 1:** Show a PR diff; passing installer host checks; a GitHub Actions run on the PR that validates without publishing; and, after merge or an authorized manual dispatch, a successful main-branch run with a release/tag and downloadable assets matching the same commit. Inspect archive contents and checksum. Report any device-only checks as pending.

## Task 2: embedded APK workflow (separate PR)

1. Read the failed `build Debian rootfs` log and reproduce or isolate that failure before patching `rootfs/build-rootfs.sh`.
2. Inventory every prerequisite referenced by `.github/workflows/build.yml`, `scripts/build-aether-apk.sh`, and `docs/BUILDING-embedded.md`. Resolve the missing Gradle wrapper, Android source, and X11 module from verified upstream sources or narrow the workflow's stated output honestly. Do not fabricate empty files or bypass preflight checks.
3. Check the pinned PRoot package URLs and extraction logic with real packages. Check rootfs and APK hashes and `scripts/inspect-aether-apk.sh` against the produced artifact.
4. Keep the result **BLOCKED** until the repository has the required source/toolchain and an actual APK passes inspection. Do not report Android first boot, X11, GPU, or signing as passed without device evidence.

**Acceptance for Task 2:** A successful build run containing the inspected APK and checksums, followed by a separate Android device acceptance report; or a precise blocker list with links to the failing logs and missing inputs.

## How to work with Jules on B

1. At [jules.google.com](https://jules.google.com), [connect GitHub](https://jules.google/docs/) and grant access specifically to `psyc-exe/termux-dark-aether`. Select `main` as the starting branch. Push this handoff to B first so Jules can read it from GitHub.
2. Start with one task per PR. Paste the prompt below for Task 1. Review Jules's plan and diff, then have it run the checks and open a PR. Verify the Actions result yourself before merging.
3. For later bugs and features, open a focused GitHub issue with expected behavior, reproduction or acceptance criteria, and relevant Android device details. [Adding the `jules` label](https://jules.google/docs/running-tasks/) can start a Jules task when its GitHub app has repository access. Review each resulting PR and keep device testing as a separate gate.
4. Jules runs in a Linux VM. Under B's Jules **Configuration → Initial Setup**, enter `bash scripts/jules-env-setup.sh`, then use [Run and Snapshot](https://jules.google/docs/environment/). This runs the installer host checks and the CI triage tests. Do not put credentials in this script. The VM cannot establish real Android first boot, X11, GPU, or device acceptance.

## Automatic maintenance integration

One-time setup:

1. Connect B to the Jules GitHub app. Create an API key in [Jules Settings](https://jules.google.com/settings).
2. In B's GitHub repository, add that key as an Actions secret named `JULES_API_KEY`. Do not put it in source, issues, or Jules Initial Setup.
3. Push this file and `.github/workflows/jules-ci-triage.yml` to B's default branch. Review the first triggered issue and Jules session before relying on the automation.

After setup, a failed main-branch run of **Aether Update** or **Build Aether Embedded APK** creates one GitHub issue per workflow and commit. The issue links the run and failed steps. The workflow creates a Jules API session with `AUTO_CREATE_PR` and records its link in the issue. Repeated daily failures at the same commit reuse the same issue. PRs remain for maintainer review. If workflow names change or new CI workflows are added, update the monitored names in the triage workflow. If an API request fails, the issue remains pending and the dispatch can be retried by rerunning the triage job.

Enable these native Jules features in B's codebase page for ongoing work:

- [Scheduled Tasks](https://jules.google/docs/scheduled-tasks/): create a weekly task with the prompt below. It can run automatically and produce a PR.
- [Suggested Tasks](https://jules.google/docs/suggested-tasks/): turn **Proactivity** on if available to your account. Its current scope mainly covers resolvable TODO comments; suggestions require review before starting.

Weekly Scheduled Task prompt:

> Read `handoff.md`. Inspect the current B repository and its open issues/PRs. Choose at most one small, verifiable maintenance fix or useful feature that is not already in progress. Implement it with focused checks and open a PR for review. Do not change the A repository. If the idea needs Android hardware or missing upstream source, document a precise proposal or blocker and do not claim it passed. Avoid duplicate PRs for an issue already being worked on.

The [Jules REST API](https://jules.google/docs/api/reference/) is experimental. This integration uses its Sources and Sessions endpoints; check for API changes if triage starts failing. Manually adding the `jules` label to a focused issue remains available for one-off work without this dispatcher.

### Paste into Jules for the first task

> Read `handoff.md`. Fix **Task 1 only** in `psyc-exe/termux-dark-aether`: the failing installer release workflow. Start by retrieving the checkout failure log and tracing the release asset paths. Make the smallest reviewable change, update the matching README instructions, run the host checks, and open a PR. State the root cause, exact tests, and any limits. Do not edit the A repository, claim an APK exists, or hide failures by skipping jobs.

### Reusable issue prompt for a feature or bugfix

> In `psyc-exe/termux-dark-aether`, implement **[one specific behavior]**. Current behavior: **[steps and observed result]**. Expected behavior: **[testable result]**. Relevant files/device: **[paths, Android version, architecture, logs]**. Keep the change focused, add a regression check where practical, run the applicable host checks, and open a PR. Mark Android-only validation pending unless it was actually performed.

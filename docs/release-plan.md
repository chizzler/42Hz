# Milestone 6 release plan

Milestone 6 produces the first public 42Hz release candidate from a published,
reproducible source. It is complete only when somebody can obtain the tagged
source without this working tree, build the application and Arch package, and
get the same result already verified locally.

The candidate is a prerelease, not a quiet declaration that audio software has
become infallible overnight.

## Exit criteria

- The source repository, candidate tag and release artefacts are public.
- Application, package, tag, AppStream entry and release notes agree on the
  version and Easy Effects base revision.
- A canonical source archive has a published SHA-256 checksum and satisfies the
  GPL source-availability obligation for the shipped binary.
- A clean machine can build from that archive without access to the development
  checkout or its Git metadata.
- Automated, integration, visual and packaging gates below pass against the
  candidate, not an earlier development build.
- Installation, conflict behaviour, known limitations, attribution and upstream
  maintenance are documented.
- Any failure after a candidate is published produces a new candidate. A public
  tag or artefact is never silently replaced.

## Decisions before the freeze

### Candidate version

Choose and record the release version before changing metadata. The existing
history made `0.7.0` the milestone-1-to-4 development version and described the
remaining 0.3 as packaging plus the release candidate. That points to
`1.0.0-rc1`, but this is a decision, not arithmetic disguised as policy.

If `1.0.0-rc1` is chosen, add one canonical prerelease version source that can
reach the binary, package, AppStream and tag without pretending CMake's numeric
`project(VERSION)` accepts a prerelease suffix. A new package version resets
`pkgrel` to 1, and `prepare()` must reject disagreement between the package and
application versions just as it already rejects an upstream-version mismatch.

### Application artwork

Replace the remaining Easy Effects-derived icons with original 42Hz artwork.
Install and inspect all normal, symbolic and disabled variants at representative
desktop sizes. Record the artwork's authorship and licence. The old art is
licensed, but launching a new identity with somebody else's face would be an
excellent way to make the attribution paragraph do all the talking.

### Publication and signing

Create the repository named by the existing metadata,
`https://github.com/chizzler/42Hz`, and add it as the Git remote. Decide whether
release tags and checksum manifests are signed; if they are, document the key
and verification command. Use an annotated tag in either case.

## Release sequence

### 1. Make the source distributable

- Change `packaging/PKGBUILD` so its 42Hz source is a pinned release source with
  a checksum, not `git archive HEAD` from its parent directory.
- Preserve the separate pinned Easy Effects `v8.2.8` source and verify that its
  version and checksums still agree with `CMakeLists.txt` and `spike/fetch.sh`.
- Define a canonical source archive generated from the candidate commit with
  stable filenames and timestamps, and produce a SHA-256 manifest.
- Build both the application and package from an extracted archive containing
  no `.git` directory.
- Keep generated archives, package working directories and binary packages out
  of Git.

This is a release blocker. The current PKGBUILD deliberately packages committed
`HEAD`, which was correct for local milestone-5 builds, but a downloaded source
archive has no parent Git repository for it to archive.

### 2. Complete metadata and user documentation

- Add the AppStream `<release>` only when its version and release date are true.
- Capture representative spectrum, mixer and equalizer screenshots, publish
  them at stable URLs and add them to AppStream metadata.
- Re-run `desktop-file-validate` and `appstreamcli validate`; only the accepted
  numeric-ID warning may remain.
- Verify that homepage, issue tracker and source links resolve after publication.
- Expand the README build section into exact Arch build dependencies and include
  package installation, upgrade, removal and EasyEffects-conflict behaviour.
- Keep both inherited PipeWire failure modes prominent in the README and release
  notes.
- Add an upstream-update procedure covering the tag and commit, archive and tree
  hashes, patch-inventory replay, dependency review, attribution review, and the
  full release gate.

### 3. Freeze and verify the candidate

Start from a clean worktree. Record every command and result in the dev diary.
Run the gates in this order so cheaper failures happen first.

#### Source and build gate

1. Fetch and verify the pinned upstream source with `spike/fetch.sh`.
2. Apply the complete inventory with `spike/reduce-deps.py`.
3. Configure a fresh Release build and compile it.
4. Check `--help`, `--version`, diagnostics, single-instance forwarding and each
   supported bypass/reset command.
5. Confirm removed inherited options fail once with `Unknown option` and emit no
   internal parser warnings during an ordinary launch.

#### Audio integration gate

1. Run `spike/recovery.sh` against its private PipeWire graph and require every
   check to pass.
2. With explicit acknowledgement that desktop audio moves briefly, run
   `spike/recovery.sh --desktop` and verify default-route restoration.
3. Exercise silence, live playback, global and EQ bypass, stream volume/mute,
   processing inclusion, profiles and the equalizer.
4. Confirm idle and active diagnostics recognise the exact seven- and eight-node
   graphs and reject incomplete or polluted graphs.

#### Visual gate

1. Start the isolated compositor with `spike/nested-session.sh`.
2. Run `spike/geometry-sweep.sh` with live audio and inspect every capture for
   clipping, overlap, misleading labels and unreachable controls.
3. Run `spike/theme-switch.sh` across its dark, light, monochrome and accented
   theme set while audio is flowing.
4. Manually exercise keyboard and pointer navigation, all spectrum modes, both
   chrome modes, the mixer, EQ, profile selection and column density.
5. Select the final release screenshots from candidate output only.

#### Package gate

1. Build from the extracted canonical source archive.
2. Audit the package payload, ownership, permissions, linked libraries and
   runtime dependencies.
3. Run `namcap` and account for every remaining warning.
4. Install on a clean Arch/Omarchy test environment, launch outside the source
   directory, run diagnostics, and exercise the primary UI path.
5. Test upgrade, removal and reinstall. Confirm no 42Hz process, PipeWire node,
   package-created system configuration or foreign-owned file survives removal;
   user settings in the home directory are allowed to persist.

### 4. Publish the candidate

- Commit the frozen candidate and push it to the public repository.
- Create and push the annotated candidate tag without moving it later.
- Publish the canonical source archive, checksum manifest, Arch package and
  release notes as prerelease assets.
- Release notes must name the Easy Effects base, summarise meaningful changes,
  credit upstream, state non-affiliation, list the two known limitations and
  provide build/install instructions.
- Download the public assets into a new directory and verify their checksums.
- Repeat the clean archive build, package checks and installed smoke test from
  those downloaded bytes.

If that final proof changes source or metadata, publish `rc2`; do not repair
`rc1` in place. Once it passes, milestone 6 is complete. Promotion to a stable
release is a later decision based on feedback, not part of this milestone.

## Release evidence

The release pass leaves three records:

- a newest-first dev-diary entry containing commands, results and commit hashes;
- release notes published with the candidate;
- a checksum manifest covering every uploaded source and binary artefact.

The worktree must be clean after generated artefacts are removed or confirmed
ignored. `git ls-files packaging` must still list only `packaging/PKGBUILD`.

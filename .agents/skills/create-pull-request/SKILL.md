---
name: create-pull-request
description: Create and submit a GitHub pull request from the current repository changes, including a person-prefixed branch, a repository-conformant commit, push, concise PR description, relevant labels, and self-assignment. Use when asked to create, open, or submit a PR, including post-execution smart-contract deployment PRs.
---

# Create Pull Request

Carry the requested changes through branch creation, commit, push, and PR creation. Do not stop after drafting commands when the user asked to create the PR.

## 1. Inspect the repository

- Read the applicable `AGENTS.md` and repository contribution instructions.
- Inspect `git status`, unstaged and staged diffs, and recent commits before changing Git state.
- Preserve unrelated user changes. Stop on an unresolved merge, rebase, or cherry-pick.
- Determine the default base branch and fetch it when network access is available.
- Check whether a PR already exists for the intended head branch before creating another one.

## 2. Create the branch

- Name every new human-authored branch `<person-name>/<short-description>`.
- Use the person's established repository prefix when it can be inferred from their existing branches or explicit request. For example, use `clement/deploy-041-etherfi-adapters`, not `feat/deploy-041-etherfi-adapters`.
- Otherwise derive `<person-name>` from the Git/GitHub identity, normalize it to lowercase kebab-case, and ask only when the identity is genuinely ambiguous.
- Keep the description short, lowercase, and kebab-cased.
- Start from the up-to-date default branch when the worktree is clean. If requested changes are already present, create the branch without discarding, resetting, or overwriting them.
- Never reuse an unrelated branch or overwrite a local or remote branch.

## 3. Validate and commit

- Review the complete diff and run the smallest relevant formatter, validation, and tests.
- Stage intended files individually. Never stage secrets, credentials, `.env` files, private keys, or unrelated changes.
- Follow repository commit conventions visible in its instructions and recent history. Repository-specific conventions take precedence.
- When no stronger convention exists, use `type(scope): imperative summary` with a conventional type such as `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `chore`, or `ci`.
- Keep the subject imperative, concise, under 72 characters, and without a trailing period. Add a body only when it explains important motivation or consequences.
- Keep commits atomic. Never amend, skip hooks, or add a co-author unless explicitly requested.

## 4. Push safely

- Push the branch with upstream tracking when needed.
- Never force-push unless the user explicitly requests it and the exact target has been verified.
- Confirm the local branch tracks the expected remote branch.

## 5. Create the PR

- Target the repository's default branch unless the user specifies another base.
- Name the PR using the rules below; do not blindly reuse the commit subject.
- Keep ordinary PR descriptions short and factual, normally using only:
  - `## Summary` with two to four bullets describing the outcome.
  - `## Verification` with commands actually run and their result.
- Add only relevant existing labels after inspecting the repository label list. Do not invent labels or add priority labels without evidence.
- Assign the PR to the authenticated GitHub user with `--assignee @me` or the equivalent API call.
- Create a normal ready-for-review PR unless the user explicitly requests a draft.

### Name the PR

- Inspect 20 to 50 recent merged PR titles, then narrow to PRs for the same component or change type. Follow the dominant specific pattern over a generic convention.
- Treat the PR title and commit subject as distinct. A conventional commit such as `docs(skill): add pull request workflow` normally becomes `Add pull request workflow` as the PR title.
- For an ordinary PR, use sentence case in the form `<Imperative verb> <specific outcome>`, for example `Add pull request creation skill`, `Fix live-state fork tests`, or `Document Talos scheduled actions`.
- Do not add a Conventional Commit prefix such as `feat:`, `fix(scope):`, or `docs:` unless recent PRs for that exact area consistently use it.
- Use a bracketed prefix only when repository history gives it domain meaning:
  - `[ARM]` for ARM deployments and release-like protocol or governance operations.
  - `[yAudit-NN]` for a change tied to that exact audit finding.
  - Never invent a bracketed category when a GitHub label already expresses it.
- Preserve established project names and capitalization such as `ARM`, `EtherFi`, `EthenaARM`, `LidoARM`, `USDC`, and `WETH`.
- Keep the title concise, specific, and free of trailing punctuation. Avoid vague titles such as `Updates`, `Various fixes`, or `Changes`.

## Smart-contract deployment PRs

For a post-execution smart-contract deployment PR in `OriginProtocol/arm-oeth`, use [PR #315](https://github.com/OriginProtocol/arm-oeth/pull/315) as the reference. Fetch its current title, body, labels, and assignee with `gh pr view 315` when available.

- For a numbered deployment, title the PR `[ARM] Deploy <NNN> <target> on <network>`, where `<NNN>` is the zero-padded deployment-script number. For example: `[ARM] Deploy 039 USDC ARM on mainnet`.
- For a numbered governance or operational action that is not a deployment, retain the imperative action and follow the closest recent `[ARM]` title, for example `[ARM] Unpause Ethena ARM via governance (035)`.
- Apply the existing `Deployment` label. Add `Deployment script` only when the PR actually changes a deployment script.
- Start with `# Description`, then include only applicable sections from the reference PR:
  - included or companion PRs;
  - `## Deployment` with the exact script path;
  - `## Contracts` with names, checksummed addresses, and explorer links;
  - `## Contract diff` with executable `make match` commands;
  - `## Configuration` for meaningful deployed values;
  - `## Governance` with the proposal status or an explicit statement that none is required;
  - required post-deployment actions and responsible actor;
  - `## Tests` listing only completed checks.
- Keep the description proportional to the deployment. Omit empty sections, repeated explanations, and details that cannot be verified. Never fabricate addresses, transaction state, governance state, tests, or related PRs.

## 6. Verify and report

- Read the created PR back from GitHub and verify its URL, base, head, title, body, labels, assignee, and open/draft state.
- Check the final Git status and report the branch, commit, PR URL, labels, assignee, validations, and current CI status.
- If GitHub access or permissions block creation, preserve all local work and report the exact remaining command or permission needed.

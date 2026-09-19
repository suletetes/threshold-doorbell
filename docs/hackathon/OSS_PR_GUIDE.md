# Open Source Mini Challenge: PR Guide

The Open Source mini challenge needs a contribution to a public repository during the hackathon window. The
strongest, most judge visible target is a pull request to Amazon's own Ring sample,
`AmazonAppDev/ring-api-helloworld`, whose CONTRIBUTING.md explicitly welcomes PRs.

You must open this PR under YOUR OWN GitHub identity. A bot cannot author a cross fork PR to an upstream repo,
so this is a step only you can complete.

## What to contribute

An accessibility oriented video processor for the sample's plugin system: a caption or high contrast overlay
processor that shows how a deaf or hard of hearing user benefits from the Ring stream. This is directly in
the spirit of Threshold and demonstrates the ecosystem understanding judges reward.

The reusable core already exists in this repo as the MIT package `packages/flutter_ring_captions`. The PR can
either port a small piece of that idea into the sample's processor interface, or add a documented example
processor.

## Exact steps (copy and paste, replace nothing but the commit body if you wish)

```bash
# 1. Fork on GitHub first (button on the repo page), then:
git clone https://github.com/AmazonAppDev/ring-api-helloworld.git
cd ring-api-helloworld
git remote add fork https://github.com/suletetes/ring-api-helloworld.git

# 2. Branch
git checkout -b feat/accessibility-caption-processor

# 3. Add your processor following docs/video-processors.md in that repo
#    (implement the VideoProcessor interface: id, name, description, process()).
#    Keep it small and focused; open an issue first if the repo asks for one.

# 4. Commit under your identity
git -c user.name=suletetes -c user.email=sulea841@gmail.com \
  commit -s -am "feat: add an accessibility caption overlay video processor"

# 5. Push to YOUR fork
git push fork feat/accessibility-caption-processor

# 6. Open the PR against upstream from the GitHub UI, or:
gh pr create --repo AmazonAppDev/ring-api-helloworld \
  --head suletetes:feat/accessibility-caption-processor \
  --base main \
  --title "feat: accessibility caption overlay video processor" \
  --body "Adds an accessibility oriented video processor demonstrating a caption/high-contrast overlay for deaf and hard of hearing users, following docs/video-processors.md."
```

## For the Devpost Open Source field

Provide: the contribution URL (the PR link), your repo URL, your GitHub username (`suletetes`), and a short
description of what you did, how it works, and why it matters. The PR does not need to be merged; a forked,
unmerged PR qualifies per the rules.

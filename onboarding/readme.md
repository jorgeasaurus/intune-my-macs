# Onboarding assets

This folder contains the onboarding splash screen package used during first-run onboarding on macOS.

- IMM-Swift Dialog Onboarding.pkg — Deployable package. This is the authoritative artifact referenced by the manifest.
- IMM-Swift Dialog Onboarding.pkg.zip — Source/edit bundle for maintainers. It exists only to enable modifications and rebuilds of the PKG. It must not be referenced by manifest.json and is ignored by automation.

Guidance
- If you need to modify the onboarding flow, unzip the ZIP, make your changes, rebuild a PKG, and replace the .pkg in this folder.
- Keep the PKG filename stable to avoid manifest updates. If you change the filename or path, update the manifest entry accordingly.
- Do not add the ZIP to the manifest.

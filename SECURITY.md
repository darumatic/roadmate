# Security policy

RoadMate AU is a community app for Australian heavy-vehicle drivers: the web app
at https://roadmate.club and the Android and iOS apps built from this repository.

## Reporting a vulnerability

Please report security problems **privately** — not in a public issue.

Use GitHub's private vulnerability reporting: the repository's **Security** tab →
**Report a vulnerability**, or go straight to
https://github.com/darumatic/roadmate/security/advisories/new

Say what you found, how to reproduce it, and what an attacker could do with it.
You will get a reply in the advisory thread. Please give us a reasonable chance to
ship a fix before disclosing the problem.

## Scope

In scope: the code and workflows in this repository, the live web app, the
Firestore security rules (`firestore.rules`) and the released mobile apps.

Supported versions: the web app is always the latest release; for the mobile apps,
only the latest store release is supported.

## Not vulnerabilities

- **The Firebase configuration values** in `lib/firebase_options.dart`,
  `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
  (API keys, project and app ids). Firebase client keys identify the project; they
  are public by design. Access is enforced by the Firestore security rules and the
  keys' API restrictions, not by keeping them secret.
- **Sites and reports being world-readable.** That data is public on purpose.

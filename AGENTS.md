# Wizard contributor guide for agents

Wizard is a legacy native Objective-C/UIKit iPad app. Read README.md, CONTRIBUTING.md, docs/COMPATIBILITY.md and the specific installation guide before changing code or installing anything.

- Preserve iOS9 APIs and both armv7/arm64. A recent host build does not establish old-device compatibility.
- Keep changes bounded. Do not use keyword-based whole-line deletion when a line also contains retained state, guards or menu actions.
- Preserve wallpaper keys, media paths, imports, favorites, crop/layout values and preference domains. Display labels are separate from stable identity.
- Run the documented host suites and repository checker. App builds require the developer-supplied IOS_SDK; never download or commit an Apple SDK.
- Install only under the user's explicit device scope. Probe exact model/OS/rootful/signing prerequisites first, create a rollback, and preserve media/preferences. Do not jailbreak, alter trust/network/system policy, use default credentials, or silently respring.
- Never commit credentials, private device records, user Photos or local work directories. GTA VI packs are separately attributed Release assets; they are not MIT source assets.
- Validate source, packaging, installation and physical acceptance separately. No screenshot or passing build substitutes for device operation acceptance.

Agent-assisted installation prompts are in docs/AGENT-INSTALL.md.

# Privacy Policy

SuperQ values user privacy and is designed from the ground up to be completely local, offline, and transparent.

### Data Collection
- **Zero Telemetry**: SuperQ does not collect, log, store, or transmit any personal data, usage metrics, crash reports, or device identifiers.
- **Zero Network Activity**: SuperQ makes no network connections whatsoever. It contains no analytics frameworks, tracking pixels, or remote update pings.

### Keyboard & System Access
- SuperQ registers a global keyboard shortcut (`⇧⌘Q`) via macOS's native Carbon Event Manager and standard event APIs solely to detect when you want to force-quit the frontmost application.
- SuperQ does not log or monitor any other keystrokes.
- SuperQ only accesses process identifiers (`PID`) of the foreground app to send the termination signal (`SIGKILL`).

### Open Source Verification
All source code is publicly accessible and auditable directly in this repository.

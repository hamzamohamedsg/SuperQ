# Contributing to SuperQ

Thank you for considering contributing to SuperQ!

## Development Setup

SuperQ has zero external dependencies and builds with standard Apple tools (Xcode / Command Line Tools).

### Requirements
- macOS 13.0+
- Swift 5.9+ / Xcode 15+

### Building Locally

```bash
# Clone the repository
git clone https://github.com/your-username/superq.git
cd superq

# Build the .app bundle
./scripts/build_app.sh

# Or build the distributable .dmg installer
./scripts/build_dmg.sh
```

## Pull Request Guidelines
- Keep PRs focused on a single fix or feature.
- Ensure the app stays minimal, fast, and does not add unnecessary bloat or dependencies.
- Test thoroughly on recent macOS versions before submitting.

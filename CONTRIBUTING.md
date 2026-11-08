# Contributing to FotoTag

Thanks for your interest! FotoTag is a small project maintained by one person in their spare time, so replies may take a few days.

You can write in English or Italian.

## Reporting a problem

Open an [issue](../../issues/new/choose) and choose "Something doesn't work". The most useful details are:
- your Mac model, memory and macOS version;
- the build number (FotoTag ▸ About FotoTag);
- what you did, what you expected, what happened.

Issues are public, so don't attach personal photos or file paths you'd rather keep private.

## Suggesting a feature

Use the "Idea" form. Please open an idea and wait for a reply before writing code for a new feature. FotoTag deliberately does one thing (keywords, captions and search); features like importing or reorganizing photos are out of scope.

## Sending a change

1. Fork the repository and create a branch from `main`.
2. Build with `./crea_app.sh` and run the tests: `swift test --scratch-path ../_build/spm`.
3. Keep each change small and focused. If it changes how the app behaves, update `docs/SPEC.md`.
4. Open a pull request and fill in the form.

The code is Swift and SwiftUI. Identifiers and comments are in Italian, so please follow the language of the file you're editing. Interface text is localized in English and Italian (`Sources/FotoTag/Localizable.xcstrings`): when you add a string, add both.

## License of contributions

By contributing, you agree that your changes are released under the project's license, the [GNU GPL version 3](LICENSE).

## Conduct

Everyone involved is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

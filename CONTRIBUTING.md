# Contributing to FotoTag

Thanks for your interest. FotoTag is a small project maintained by one person in their spare time, so replies may take a few days.

You can write in English or Italian.

## Reporting a problem

Open an [issue](../../issues/new/choose) and choose "Something doesn't work". Most useful are:
- your Mac model, memory and macOS version;
- the build number (FotoTag ▸ About FotoTag);
- what you did, what you expected, what happened.

Don't attach personal photos or paths you don't want to make public: issues are visible to everyone.

## Suggesting a feature

Use the "Idea" form. Before writing code for a new feature, open an idea and wait for a reply: FotoTag does one thing (keywords, captions and search), and some ideas, such as reorganising or importing photos, stay out on purpose.

## Sending a change

1. Fork the repository and create a branch from `main`.
2. Build with `./crea_app.sh` and run the tests: `swift test --scratch-path ../_build/spm`.
3. Keep the change small and about one thing. If it changes how the app behaves, update `docs/SPEC.md`.
4. Open a pull request and fill in the form.

The code is Swift and SwiftUI. Names, interface text and comments are in Italian: keep the language of the file you are editing.

## License of contributions

By sending a change you agree that it is distributed under the project's license, the [GNU GPL version 3](COPYING).

## Conduct

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

# Contributing to livery

Thanks for helping. Bug fixes, docs and tests are welcome as pull requests straight away. For a new feature or a change in behaviour, open an issue first so we can agree on the design before you write code.

## Setup

You need the Dart SDK (any version `pubspec.yaml` allows), and Flutter to work on the [example app](example/).

```sh
dart pub get
```

## Checks

CI runs these on every pull request, and each must pass before it can merge:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

It also generates the example's config and runs `flutter analyze` and `flutter test` in `example/`. The Android build of the example is a tagged test, skipped by default; run it with `dart test --tags gradle --run-skipped` when you change the Kotlin output or the Android guide.

## Changes

- Every change in behaviour comes with tests, written first.
- A change users can see updates the docs in the same pull request: [`README.md`](README.md), [`doc/`](doc/) or the [example](example/).
- Keep a pull request to one change. Don't edit `CHANGELOG.md` or the version in `pubspec.yaml`; releases set them.

## Pull requests

Pull requests are squash-merged, and the title becomes the commit on `main` and the line in the changelog. Write it as a [Conventional Commit](https://www.conventionalcommits.org/en/v1.0.0/) for livery users:

```
type(scope): summary
```

- `type` is one of `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`. `feat`, `fix` and `perf` appear in the changelog.
- `scope` is optional and names the area, for example `android`, `ios`, `dart` or `cli`.
- `summary` is imperative and lowercase, has no trailing period, and keeps the whole title within 72 characters.

For example: `feat(android): write manifest placeholders from the kotlin output`.

A breaking change adds `!` after the type, `feat(cli)!: ...`, and the description ends with a `BREAKING CHANGE:` footer saying what users must change. The description becomes the commit body, so keep it to what explains the change.

The maintainer may reword the title or description before merging.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

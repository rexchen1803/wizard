# Contributing

Thanks for helping improve Wizard. Before opening a change, review the [compatibility guide](docs/COMPATIBILITY.md), [privacy notes](docs/open-source/PRIVACY.md), and [third-party material notices](THIRD_PARTY.md).

## Report an issue

Use the GitHub bug or feature form. For a bug, include the Wizard version/build, iPad model, iOS version, installation environment, and steps to reproduce. Redact usernames, home paths, network addresses, credentials, serial numbers, UDIDs, private installation details, and personal media from logs or screenshots.

## Prepare a change

Keep changes focused and include a regression check when the behavior can be tested on the host. User interface changes should identify the tested model and OS separately from source or build evidence. Do not describe a host regression or a successful compile as device acceptance.

The app build uses an Apple iPhoneOS SDK that is not included in this repository. Do not add SDK files, signing material, installers, device records, imported photos, or media without a documented source and distribution right. Wizard-authored code uses MIT; third-party assets and code keep their own terms.

## Run the checks

The host suites require macOS, Apple Clang, and Python 3. From the repository root:

```sh
python3 scripts/check-repository.py
python3 tests/repository-regressions.py
python3 tests/native-regressions.py
./App/tests/run-http-transport-regressions.sh
./App/tests/run-weather-service-regressions.sh
python3 App/tests/cast-lifecycle-regressions.py
python3 App/tests/media-lifecycle-regressions.py
python3 App/tests/gallery-media-regressions.py
python3 App/tests/menu-layout-regressions.py
python3 App/tests/power-edge-regressions.py
```

These checks exercise source logic with host-side fixtures and doubles. They do not install the app or verify native rendering, private system symbols, signing, stock iOS, or a fresh installation. The optional universal device build is documented in the [build guide](docs/open-source/README.md#build) and requires an iPhoneOS SDK you obtained through Apple's development tools.

## Pull requests

Use the pull request template to summarize the user-facing change, list the checks you ran, and separate source/build evidence from device evidence. For third-party material, update its attribution and license record before including it. Do not add product claims, compatibility promises, or release notes that exceed the verified evidence.

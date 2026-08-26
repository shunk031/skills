## What Changed

- Added `npm:textlint` to the mise-managed tools.
- Added the two textlint rule packages already referenced by `home/dot_config/textlint/config.json`.
- Kept the textlint packages grouped together under the npm tools section.

## Verification

- `make setup`
- `MISE_CONFIG_FILE="$PWD/home/dot_mise/config.toml" mise config ls | rg -n "textlint|cffnpwr|ja-space|npm:"`
- `MISE_CONFIG_FILE="$PWD/home/dot_mise/config.toml" mise exec -- textlint --version`
- `printf 'これは textlint の検証です。\n' | MISE_CONFIG_FILE="$PWD/home/dot_mise/config.toml" mise exec -- textlint --format json --config home/dot_config/textlint/config.json --stdin --stdin-filename sample.md`
- `git diff --check`
- `MISE_CONFIG_FILE="$PWD/home/dot_mise/config.toml" mise exec -- prek run --files home/dot_mise/config.toml`

Local Bats was not run because this repository forbids local Bats runs.


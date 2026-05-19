# mautic-ci-runner

This repository contains GitHub Actions workflows that are used across our other repositories for CI purposes.

## Supported Mautic versions

Major versions are configured in [`globalSettings/versionRequirements.csv`](globalSettings/versionRequirements.csv). Plugin repositories pass the major version via `mauticVersion` in their workflow, for example:

```yaml
with:
  mauticVersion: 7
```

| Major | Mautic release tags (matrix) | PHP versions |
|-------|------------------------------|--------------|
| 5     | 5.2.9, 5.2.10                | 8.2, 8.3     |
| 7     | 7.0.2, 7.1.1                 | 8.2, 8.3, 8.4 |

When a new Mautic patch or PHP version is released, update the corresponding row in `versionRequirements.csv`.

## checkdod.sh

This script checks if the composer.json, README.md and config.php meets all requirements by Leuchtfeuer.
# mautic-ci-runner

This repository contains GitHub Actions workflows that are used across out other repositories for CI purposes.

## Plugin dependencies

Extra Composer packages are passed through the shared workflow's
`additionalRequirements` input. Composer installs them under `plugins/`, so the
dependency cache covers `bin`, `vendor` and `plugins` - except the plugin under
test, which is excluded so a restored cache can never overwrite the current
checkout. Save and restore use the same path list in every job.

The cache key includes the Mautic lock file, the tested plugin's Composer
manifest, the additional requirements, and the PHP/Mautic versions. Bump the
`composer-vN-` prefix whenever the cached layout changes.

Packages that are not on Packagist (for example private Leuchtfeuer plugins)
also need the `additionalRepositories` input, a JSON array of Composer
repositories:

```yaml
with:
  additionalRequirements: 'leuchtfeuer/mautic-lehner-products:"^4.0"'
  additionalRepositories: '[{"type":"vcs","url":"https://github.com/Leuchtfeuer/mautic-lehner-products"}]'
secrets:
  PERSONAL_ACCESS_TOKEN: ${{ secrets.PERSONAL_ACCESS_TOKEN }}
```

Composer reads private GitHub repositories with `PERSONAL_ACCESS_TOKEN`, so the
token must have read access to them. When additional requirements are set,
Composer installs Mautic without scripts first and runs the scripts with the
requirements, because the scripts boot Mautic with the tested plugin.

## checkdod.sh

This script checks if the composer.json, README.md and config.php meets all requirements by Leuchtfeuer.

#!/bin/bash

# functions
# returns the Value of the key. It contains either the direct Value, the Array or json-block.
function extract_top_level_block {
  local key=$1
  local file=$2

  awk -v key="$key" '
  BEGIN {
    in_block = 0
    found = 0
    brace_level = 0
  }
  {
    # Suche nach der Zeile mit "key":
    if (!found && $0 ~ "\"" key "\"" && $0 ~ /:/) {
      found = 1

      # Ausgabe der ganzen Zeile (inkl. Schlüssel und Wert)
      print

      # Zähle alle Klammern in dieser Zeile
      brace_level += gsub(/[{\[]/, "")
      brace_level -= gsub(/[}\]]/, "")

      # Wenn Block schon geschlossen ist (kein offenes { oder [), dann beenden
      if (brace_level == 0) {
        exit
      }

      # Sonst Block gestartet
      in_block = 1
      next
    }

    if (in_block) {
      print
      brace_level += gsub(/[{\[]/, "")
      brace_level -= gsub(/[}\]]/, "")
      if (brace_level == 0) {
        exit
      }
    }
  }
  ' "$file"
}

function extract_config_value {
  local key=$1
  local file=$2

  grep -E "^[[:space:]]*'$key'[[:space:]]*=>" "$file" | head -n1 | \
  sed -E "s/^[[:space:]]*'$key'[[:space:]]*=>[[:space:]]*'([^']*)'[[:space:]]*,?/\1/"
}

# script start
set -euo pipefail

# global variables
README="README.md"
COMPOSER="composer.json"
KEYWORDS=('mautic')
DIRECTORY="install-directory-name"
REQUIRE=('php' 'mautic/core-lib')
CR="Leuchtfeuer Digital Marketing GmbH"

# Theme or Plugin?
PLUGIN=$(grep '"type": "mautic-' $COMPOSER | sed -E 's/.*"type"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/') # "mautic- for specific type of the file and not of something else in the composer"
if [[ "$PLUGIN" == "mautic-plugin" ]]; then
  PLUGIN=true
  KEYWORDS+=('plugin' 'integration')
  AUTHORS=("name\": \"$CR" 'email": "mautic-plugins@leuchtfeuer.com' 'homepage": "https://Leuchtfeuer.com/mautic/' 'role": "Developer')
  LICENSE="GPL-3\.0-or-later"
  AUTOLOAD="psr-4"
  CONFIG="Config/config.php"
elif [[ "$PLUGIN" == "mautic-theme" ]]; then
  PLUGIN=false
  KEYWORDS+=('theme')
  CONFIG="config.php"
else
  echo "this directory is neither a Plugin nor a Theme or it is not defined in the $COMPOSER"
  exit 1
fi

# check composer.json
# it needs to be checked before config.php
# Start composer
composererrorstoplevel=()
composererrorsinside=()
composerkeys=('name' 'description' 'keywords' 'extra' 'require') # extra needs to be before autoload
if [[ "$PLUGIN" == true ]]; then
  composerkeys+=('authors' 'license' 'autoload')
fi
for key in "${composerkeys[@]}"; do
  block=$(extract_top_level_block "$key" "$COMPOSER")
  if [[ "$block" == "" ]]; then
    composererrorstoplevel+=($key)
    continue
  fi
  if [[ $key == 'name' ]]; then
    [[ "$block" != *'"leuchtfeuer/'* ]] && composererrorsinside+=('"name" needs to start with "leuchtfeuer/"')
  elif [[ $key == 'description' ]]; then
    description=$(echo "$block" | sed -E "s/.*\"description\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/")
  elif [[ $key == 'keywords' ]]; then
    # check if keywords has an array
    if [[ "$block" != *'['* || "$block" != *']'* ]]; then
      composererrorsinside+=('"keywords" needs to be an array')
      continue
    fi
    for required in "${KEYWORDS[@]}"; do
      if [[ "$block" != *\"$required\"* ]]; then
        composererrorsinside+=("keyword \"$required\" is missing in \"keywords\"")
      fi
    done
  elif [[ $key == 'extra' ]]; then
    if [[ "$block" != *\"$DIRECTORY\"* ]]; then
      composererrorsinside+=("extra needs \"$DIRECTORY\" as an option")
    fi
    installdirectoryname=$(echo "$block" | grep "\"$DIRECTORY\"" | sed -E "s/.*\"$DIRECTORY\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/")
  elif [[ $key == 'require' ]]; then
    for singlerequire in "${REQUIRE[@]}"; do
      if [[ "$block" != *\"$singlerequire\"* ]]; then
        composererrorsinside+=("keyword \"$singlerequire\" is missing in \"require\"")
      fi
    done
  fi
  if [[ $key == 'authors' ]]; then
      for author in "${AUTHORS[@]}"; do
        if [[ "$block" != *\"$author\"* ]]; then
          composererrorsinside+=("keyword with specific value \"$author\" is missing")
        fi
      done
  fi
  if [[ $key == 'license' ]]; then
    if [[ "$block" != *\"$LICENSE\"* ]]; then
      composererrorsinside+=("license needs to be \"$LICENSE\"")
    fi
  fi
  if [[ $key == 'autoload' ]]; then
    if [[ "$block" != *\"$AUTOLOAD\"* ]]; then
      composererrorsinside+=("autoload needs an option \"$AUTOLOAD\"")
    fi
    if [[ -z "${installdirectoryname:-}" ]]; then
      composererrorsinside+=("Can not extract the install-directory-name, please be sure to fill out")
      continue
    fi
    pattern="\"MauticPlugin\\\\$installdirectoryname\\\\\""
    if [[ "$block" != *"$pattern"* ]]; then
      composererrorsinside+=("autoload needs $pattern as an option")
    fi
  fi
done
# End Composer
# check config.php
# Start config
configkeys=('name' 'description' 'author' 'version')
configerrors=()
for key in "${configkeys[@]}"; do
  value=$(extract_config_value "$key" "$CONFIG")
  if [[ -z "$value" ]]; then
    configerrors+=("$key is missing or empty in config.php")
    continue
  fi
  if [[ $key == 'description' ]]; then
    if [[ "$value" != "$description" ]]; then
      configerrors+=($'The description needs to be the same in the composer.json and the config.php\n  composer.json: '"$description"$'\n  config.php: '"$value")
    fi
  fi
  if [[ $key == 'author' ]]; then
    if [[ "$value" != "$CR" ]]; then
      configerrors+=("author needs to be \"$CR\"")
    fi
  fi
done
# End config

# check README.md
# Start readme
readmeerrors=()

if [[ "$PLUGIN" == true ]]; then
  readmekeys=('# Plugin Name' '## Overview' '## Requirements' '## Installation' '### Composer' '### Manual Installation' '## Configuration' '## Usage' '## Credits' '## Author')
else
  readmekeys=('# Theme Name')
fi
for key in "${readmekeys[@]}"; do
  if ! grep -Fq -- "$key" "$README"; then
    readmeerrors+=("Missing section: $key")
  fi
done
# End readme

# Output of Errors
if [[ ${#composererrorstoplevel[@]} -eq 0 && ${#composererrorsinside[@]} -eq 0 && ${#configerrors[@]} -eq 0 && ${#readmeerrors[@]} -eq 0 ]]; then
  printf "\e[32m$README, $CONFIG and $COMPOSER are in good shape\n\e[0m" # green
  exit 0
else
  if [[ ${#composererrorstoplevel[@]} -eq 0 ]]; then
    printf "\e[32m1st part of $COMPOSER check passed: all options present.\n\e[0m"
  else
    printf "\e[31mOptions missing in composer.json:\n\e[0m" # red
    for err in "${composererrorstoplevel[@]}"; do
      echo "  - $err"
    done
  fi
  if [[ ${#composererrorsinside[@]} -eq 0 ]]; then
    printf "\e[32m2nd part of $COMPOSER check passed: all values right.\n\e[0m"
  else
    printf "\e[31mOptions wrong in composer.json:\n\e[0m"
    for err in "${composererrorsinside[@]}"; do
      echo "  - $err"
    done
  fi
  if [[ ${#configerrors[@]} -eq 0 ]]; then
    printf "\e[32m$CONFIG check passed: all options present and right.\n\e[0m"
  else
    printf "\e[31mValues missing or wrong in $CONFIG:\n\e[0m"
    for err in "${configerrors[@]}"; do
      echo "  - $err"
    done
  fi
  if [[ ${#readmeerrors[@]} -eq 0 ]]; then
    printf "\e[32m$README check passed: all sections present.\n\e[0m"
  else
    printf "\e[31mREADME.md check failed:\n\e[0m"
    for err in "${readmeerrors[@]}"; do
      echo "- $err"
    done
  fi
fi
exit 1












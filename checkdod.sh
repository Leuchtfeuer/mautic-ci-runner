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
    # Searching for line with "key":
    if (!found && $0 ~ "\"" key "\"" && $0 ~ /:/) {
      found = 1

      # Output of the whole line(incl. key and value)
      print

      # Count all braces
      brace_level += gsub(/[{\[]/, "")
      brace_level -= gsub(/[}\]]/, "")

      # exit if block ends (count braces reach 0)
      if (brace_level == 0) {
        exit
      }

      # start block
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

  local match=$(grep -E "^[[:space:]]*'$key'[[:space:]]*=>" "$file" | head -n1 || true)
  [[ -z "$match" ]] && { echo ""; return 0; }

  echo "$match" | sed -E "s/^[[:space:]]*'$key'[[:space:]]*=>[[:space:]]*'([^']*)'[[:space:]]*,?/\1/"
}

function check_for_path_violations() {
  local search_dir=${1:-.}
  local filter=":[0-9]+:"
  local path_pattern='(/[^[:space:]"'"'"']+|[A-Za-z]:\\[^[:space:]"'"'"']+|(\.\.?/)[^[:space:]"'"'"']+)'
  local api_ignore='(GET|POST|PUT|DELETE|PATCH|curl|fetch|axios|http(s)?://|/api/)'
  local others="($filter[[:space:]]*/\*\*)"
  local exclude_ignore='exclude\('

  local raw_matches
  raw_matches=$(grep -Einr --include="*.php" --include="*.js" --exclude-dir={vendor,node_modules} "$path_pattern" "$search_dir" 2>/dev/null || true)

  local matches
  matches=$(echo "$raw_matches" | grep -Ev "$api_ignore" || true)
  matches=$(echo "$matches" | grep -Ev "$others" || true)
  matches=$(echo "$matches" | grep -Ev "$exclude_ignore" || true)

  matches=$(echo "$matches" | awk -F: '
  {
    match($0, /[^ ]+\.php/)
    filepath = substr($0, RSTART, RLENGTH)
    split(filepath, parts, "/")
    filename = parts[length(parts)]
    if (filename == "config.php") next

    line = substr($0, index($0,$3))

    if (line ~ /^\s*\/\//) next
    if (line ~ /@[A-Za-z0-9_\/.-]+/) next
    if (line ~ /<\/[a-zA-Z0-9:_-]+>/) next

    comment_pos = match(line, /\/\//)
    if (comment_pos > 0) {
      code_before_comment = substr(line, 1, comment_pos - 1)
      if (code_before_comment ~ /\/[^[:space:]]*$/ || code_before_comment ~ /[A-Za-z]:\\[^[:space:]]*$/) {
        print $0
      }
    } else {
      print $0
    }
  }')

  if [[ -n "$matches" ]]; then
    while IFS= read -r line; do
      pathviolations_tmp+=("$line")
    done <<< "$matches"
  fi

  return 0
}

function extract_code_part() {
  local line="$1"
  local code paths=()
  local file_rel="${line%%:*}"
  local file_abs
  file_abs=$(realpath "$file_rel" 2>/dev/null || true)
  code="${line#*:}"
  code="${code#*:}"
  code="${code#"${code%%[![:space:]]*}"}"
  while IFS= read -r match; do
    clean_path="${match:1:${#match}-2}"
    if [[ -n "$file_abs" ]]; then
      echo "$file_abs: $clean_path"
    else
      echo "$file_rel: $clean_path"
    fi
  done < <(echo "$code" | grep -oE "['\"][./@A-Za-z0-9_:\\*?-]+['\"]")
}

function max_upward_traversal() {
  local rel_path="$1"
  local depth=0
  local max_depth=0

  IFS='/' read -ra parts <<< "$rel_path"

  for part in "${parts[@]}"; do
    if [[ "$part" == ".." ]]; then
      ((depth++))
      if ((depth > max_depth)); then
        max_depth=$depth
      fi
    elif [[ -n "$part" && "$part" != "." ]]; then
      ((depth--))
      if ((depth < 0)); then depth=0; fi
    fi
  done

  echo "$max_depth"
}

function check_path_tail() {
  local base_path="$1"
  local depth="$2"
  IFS='/' read -ra parts <<< "$base_path"
  local total=${#parts[@]}
  local start=$(( total - depth ))
  (( start < 0 )) && start=0

  local keyword
  for (( i = start; i < total; i++ )); do
    keyword="${parts[i]}"
    if [[ "$keyword" =~ ^(html|htdocs|current|shared)$ ]]; then
      return 0 
    fi
  done

  return 1
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
COMPOSEREXIST=true
CONFIGEXIST="unknown"
READMEEXIST=true

# Are the composer and readme existing?
if [[ ! -f "$README" ]]; then
  READMEEXIST=false
fi 
if [[ ! -f "$COMPOSER" ]]; then
  if [[ "$READMEEXIST" == true ]]; then
    printf "\e[32m$README don't exist. \e[0m"
  fi
  printf "\e[32m$COMPOSER don't exist. config.php is unknown.\e[0m"
  exit 1
fi

# Theme or Plugin?
PLUGIN=$(grep '"type": "mautic-' $COMPOSER | sed -E 's/.*"type"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/') # "mautic- for specific type of the file and not of something else in the composer"
if [[ "$PLUGIN" == "mautic-plugin" ]]; then
  PLUGIN=true
  KEYWORDS+=('plugin' 'integration')
  AUTHORS=("name\": \"$CR" 'homepage": "https://Leuchtfeuer.com/mautic/' 'role": "Developer' 'email": "mautic-plugins@leuchtfeuer.com')
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

# is config existing?
if [[ ! -f "$CONFIG" ]]; then
  CONFIGEXIST=false
else
  CONFIGEXIST=true
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
    nametheme=${name_theme##*/}
    continue
  elif [[ $key == 'description' ]]; then
    description=$(echo "$block" | sed -E "s/.*\"description\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/")
    if [[ -z "${description:-}" ]]; then
      composererrorsinside+=("description is empty")
    fi
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
      if [[ "$author" == *"email"* ]]; then
        block=$(echo "$block" | tr '[:upper:]' '[:lower:]')
      fi
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
      composererrorsinside+=("Can not extract the install-directory-name, please be sure to fill out, autoload unknown")
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
if [[ "$CONFIGEXIST" == true ]]; then
  configkeys=('name' 'description' 'author' 'version')
  configerrors=()
  for key in "${configkeys[@]}"; do
    value=$(extract_config_value "$key" "$CONFIG")
    if [[ -z "$value" ]]; then
      configerrors+=("$key is missing or empty in config.php")
      continue
    fi
    if [[ $key == 'description' ]]; then
      if [[ -z "${description:-}" ]]; then
        configerrors+=("TIPP: copy the description of $CONFIG to $COMPOSER")
        continue
      fi
      if [[ "$value" != "$description" ]]; then
        configerrors+=($'The description needs to be the same in the composer.json and the config.php\n  composer.json: '"$description"$'\n  config.php: '"$value")
      fi
    fi
    if [[ $key == 'author' ]]; then
      if [[ "$value" != "$CR" ]]; then
        configerrors+=("author needs to be \"$CR\"")
      fi
    fi
    if [[ $key == 'name' ]]; then
      nameplugin="$value"
      if [[ -z "${nameplugin:-}" ]]; then
        configerrors+=("name should have a value")
      fi
    fi
  done
fi
# End config

# check README.md
# Start readme
if [[ "$READMEEXIST" == true ]]; then
  readmeerrors=()
  if [[ "$PLUGIN" == true ]]; then
    readmekeys=('# Plugin Name' '## Overview' '## Requirements' '## Installation' '### Composer' '### Manual Installation' '## Configuration' '## Usage' '## Credits' '## Author')
    synonymover=('## Overview' '## Purpose' '## Features')
    synonymreq=('## Requirements' '## Version Support')
  else
    readmekeys=('# Theme Name')
  fi
  for key in "${readmekeys[@]}"; do
    if [[ $key == '# Theme Name' ]]; then
      nametheme=$(echo "$nametheme" | tr '[:upper:]' '[:lower:]')
      if [[ -z "${nametheme:-}" ]]; then
        readmeerrors+=("TIPP: copy the name from $README to $COMPOSER in name behind \"leuchtfeuer/\"")
      fi
      if ! grep -Fq -- "# $nametheme" "$README"; then
        readmeerrors+=("Name of Theme should be the same as end of name ($nametheme) in $COMPOSER")
        continue
      fi
    fi
    if [[ $key == "## Overview" ]]; then
      forward=false
      for subkey in "${synonymover[@]}"; do
        if grep -Fq -- "$subkey" "$README"; then
          forward=true
        fi
      done
      if [[ "$forward" == true ]]; then
        continue
      else
        readmeerrors+=('Missing Section: ## Overview / Purpose / Features')
        continue
      fi
    fi
    if [[ $key == "## Requirements" ]]; then
      forward=false
      for subkey in "${synonymreq[@]}"; do
        if grep -Fq -- "$subkey" "$README"; then
          forward=true
        fi
      done
      if [[ "$forward" == true ]]; then
        continue
      else
        readmeerrors+=('Missing Section: ## Requirements / Version Support')
        continue
      fi
    fi
    if [[ $key == '# Plugin Name' ]]; then
      if [[ -z "${nameplugin:-}" ]]; then
        readmeerrors+=("TIPP: copy name from $README to $CONFIG")
        continue
      fi
      if ! grep -Fq -- "$nameplugin" "$README"; then
        readmeerrors+=("Name of the Plugin should be the same as the name ($nameplugin) in $CONFIG")
      fi
      continue
    fi
    if ! grep -Fq -- "$key" "$README"; then
      readmeerrors+=("Missing section: $key")
    fi
  done
fi
# End readme

# check for relativ or absolute paths in Code
# Start path check
SEARCH_DIR="./"
pathviolations_tmp=()
pathviolations=()
check_for_path_violations "$SEARCH_DIR"
for line in "${pathviolations_tmp[@]}"; do
  while IFS= read -r code_part; do
    base_path="${code_part%%:*}"
    base_path=$(dirname "$base_path")
    path_only="${code_part#*: }"

    if [[ "$path_only" == /* || "$path_only" == *".."* ]]; then
      depth=$(max_upward_traversal "$path_only")
      echo "$base_path"
      echo "$path_only"
      echo "$depth"
      if check_path_tail "$base_path" "$depth"; then
        pathviolations+=("$line")
      fi
    fi
  done < <(extract_code_part "$line")
done
# End path check

# Output of Errors
if [[ "$CONFIGEXIST" == true && "$READMEEXIST" == true ]]; then
  if [[ ${#composererrorstoplevel[@]} -eq 0 && ${#composererrorsinside[@]} -eq 0 && ${#configerrors[@]} -eq 0 && ${#readmeerrors[@]} -eq 0 ]]; then
    printf "\e[32m$README, $CONFIG and $COMPOSER are in good shape\n\e[0m" # green
    exit 0
  fi
fi

if [[ ${#composererrorstoplevel[@]} -eq 0 ]]; then
  printf "\e[32m1st part of $COMPOSER check passed: all options present.\n\e[0m"
else
  printf "\e[31mOptions missing in composer.json:\n\e[0m" # red
  for err in "${composererrorstoplevel[@]}"; do
    echo "  - $err"
  done
fi
if [[ ${#composererrorsinside[@]} -eq 0 ]]; then
  printf "\e[32m2nd part of $COMPOSER check passed: all known values right.\n\e[0m"
else
  printf "\e[31mOptions wrong in composer.json:\n\e[0m"
  for err in "${composererrorsinside[@]}"; do
    echo "  - $err"
  done
fi
if [[ ${#composererrorstoplevel[@]} -eq 0 && ${#composererrorsinside[@]} -eq 0 ]]; then
  printf "\e[32mYour $COMPOSER meets all requirements\n\e[0m"
fi
if [[ "$CONFIGEXIST" == true ]]; then
  if [[ ${#configerrors[@]} -eq 0 ]]; then
    printf "\e[32m$CONFIG check passed: all options present and right.\n\e[0m"
  else
    printf "\e[31mValues missing or wrong in $CONFIG:\n\e[0m"
    for err in "${configerrors[@]}"; do
      echo "  - $err"
    done
  fi
else
  printf "\e[32m$CONFIG don't exist. \e[0m"
fi
if [[ "$READMEEXIST" == true ]]; then
  if [[ ${#readmeerrors[@]} -eq 0 ]]; then
    printf "\e[32m$README check passed: all sections present.\n\e[0m"
  else
    printf "\e[31mREADME.md check failed:\n\e[0m"
    for err in "${readmeerrors[@]}"; do
      echo " - $err"
    done
  fi
else
  printf "\e[31m$README don't exist. \e[0m"
fi
if [[ ${#pathviolations[@]} -eq 0 ]]; then
  printf "\e[32mPath Violation check passed: no relevant hardcoded paths.\n\e[0m"
else
  printf "\e[31mPath Violation check failed:\n\e[0m"
  for entry in "${pathviolations[@]}"; do
    echo "  - $entry"
  done
fi
exit 1












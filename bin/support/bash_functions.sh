#!/usr/bin/env bash

curl_retry_on_18() {
  local ec=18;
  local attempts=0;
  while (( ec == 18 && attempts++ < 3 )); do
    curl "$@" # -C - would return code 33 if unsupported by server
    ec=$?
  done
  return $ec
}

# This function will install a version of Ruby onto the
# system for the buildpack to use. It coordinates download
# and setting appropriate env vars for execution
#
# Example:
#
#   install_bootstrap_ruby "$BIN_DIR" "$BUILDPACK_DIR"
#
# Takes two arguments, the first is the location of the buildpack's
# `bin` directory. This is where the `download_ruby` script can be
# found. The second argument is the root directory where Ruby
# can be installed.
#
# This function relies on the env var `$STACK` being set. This
# is set in codon outside of the buildpack. An example of a stack
# would be "scalingo-22".
install_bootstrap_ruby()
{
  local bin_dir=$1
  local buildpack_dir=$2

  # Multi-arch aware stack support
  if [ "$STACK" == "scalingo-24" ]; then
    local arch
    arch=$(dpkg --print-architecture)
    local heroku_buildpack_ruby_dir="$buildpack_dir/vendor/ruby/$STACK/$arch"
  else
    local heroku_buildpack_ruby_dir="$buildpack_dir/vendor/ruby/$STACK"
  fi

  # The -d flag checks to see if a file exists and is a directory.
  # This directory may be non-empty if a previous compile has
  # already placed a Ruby executable here.
  if [ ! -d "$heroku_buildpack_ruby_dir" ]; then
    heroku_buildpack_ruby_dir=$(mktemp -d)
    # bootstrap ruby
    "$bin_dir"/support/download_ruby "$bin_dir" "$heroku_buildpack_ruby_dir"
    function atexit {
      # shellcheck disable=SC2317
      rm -rf "$heroku_buildpack_ruby_dir"
    }
    trap atexit EXIT
  fi

  echo "$heroku_buildpack_ruby_dir"
}

which_java()
{
  which java > /dev/null
}

# Detects if a given Gemfile.lock has jruby in it
# $ cat Gemfile.lock | grep jruby # => ruby 2.5.7p001 (jruby 9.2.13.0)
detect_needs_java()
{
  local app_dir=$1
  local gemfile_lock="$app_dir/Gemfile.lock"
  # local needs_jruby=0
  local skip_java_install=1

  if which_java; then
    return $skip_java_install
  fi

  grep "(jruby " "$gemfile_lock" --quiet &> /dev/null
}

# Runs another buildpack against the build dir
#
# Example:
#
#   compile_buildpack_v2 "$build_dir" "$cache_dir" "$env_dir" "https://buildpack-registry.s3.us-east-1.amazonaws.com/buildpacks/heroku/nodejs.tgz" "heroku/nodejs"
#
compile_buildpack_v2()
{
  local build_dir=$1
  local cache_dir=$2
  local env_dir=$3
  local buildpack=$4
  local name=$5

  local dir
  local url
  local branch

  dir=$(mktemp -t buildpackXXXXX)
  rm -rf "$dir"

  url=${buildpack%#*}
  branch=${buildpack#*#}

  if [ "$branch" == "$url" ]; then
    branch=""
  fi

  if [ "$url" != "" ]; then
    echo "-----> Downloading Buildpack: ${name}"

    if [[ "$url" =~ \.tgz$ ]] || [[ "$url" =~ \.tgz\? ]]; then
      mkdir -p "$dir"
      curl_retry_on_18 -s --fail --retry 3 --retry-connrefused --connect-timeout "${CURL_CONNECT_TIMEOUT:-3}" "$url" | tar xvz -C "$dir" >/dev/null 2>&1
    else
      git clone "$url" "$dir" >/dev/null 2>&1
    fi
    cd "$dir" || return

    if [ "$branch" != "" ]; then
      git checkout "$branch" >/dev/null 2>&1
    fi

    # we'll get errors later if these are needed and don't exist
    chmod -f +x "$dir/bin/{detect,compile,release}" || true

    framework=$("$dir"/bin/detect "$build_dir")

    # shellcheck disable=SC2181
    if [ $? == 0 ]; then
      echo "-----> Detected Framework: $framework"
      "$dir"/bin/compile "$build_dir" "$cache_dir" "$env_dir"

      # shellcheck disable=SC2181
      if [ $? != 0 ]; then
        exit 1
      fi

      # check if the buildpack left behind an environment for subsequent ones
      if [ -e "$dir/export" ]; then
        set +u # http://redsymbol.net/articles/unofficial-bash-strict-mode/#sourcing-nonconforming-document
        # shellcheck disable=SC1091
        source "$dir/export"
        set -u # http://redsymbol.net/articles/unofficial-bash-strict-mode/#sourcing-nonconforming-document
      fi

      if [ -x "$dir/bin/release" ]; then
        "$dir"/bin/release "$build_dir" > "$1"/last_pack_release.out
      fi
    else
      echo "Couldn't detect any framework for this buildpack. Exiting."
      exit 1
    fi
  fi
}


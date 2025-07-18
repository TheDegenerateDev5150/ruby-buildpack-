require "language_pack"
require "language_pack/rails2"

# Rails 3 Language Pack. This is for all Rails 3.x apps.
class LanguagePack::Rails3 < LanguagePack::Rails2
  # detects if this is a Rails 3.x app
  # @return [Boolean] true if it's a Rails 3.x app
  def self.use?
    rails_version = bundler.gem_version('railties')
    return false unless rails_version
    is_rails3 = rails_version >= Gem::Version.new('3.0.0') &&
                rails_version <  Gem::Version.new('4.0.0')
    return is_rails3
  end

  def name
    "Ruby/Rails"
  end

  def default_process_types
    # let's special case thin here
    web_process = bundler.has_gem?("thin") ?
      "bundle exec thin start -R config.ru -e $RAILS_ENV -p ${PORT:-5000}" :
      "bundle exec rails server -p ${PORT:-5000}"

    super.merge({
      "web" => web_process,
      "console" => "bundle exec rails console"
    })
  end

  def rake_env
    default_env_vars.merge("RAILS_GROUPS" => "assets").merge(super)
  end

  def compile
    super
  end

  def config_detect
    super
    @assets_compile_config = @rails_runner.detect("assets.compile")
    @x_sendfile_config     = @rails_runner.detect("action_dispatch.x_sendfile_header")
  end

  def best_practice_warnings
    super
    warn_x_sendfile_use!

    if assets_compile_enabled?
      safe_sprockets_version_needed = sprocket_version_upgrade_needed
      if safe_sprockets_version_needed
        message = <<ERROR
A security vulnerability has been detected in your application.
To protect your application you must take action. Your application
is currently exposing its credentials via an easy to exploit directory
traversal.

To protect your application you must either upgrade to Sprockets version "#{safe_sprockets_version_needed}"
or disable dynamic compilation at runtime by setting:

```
config.assets.compile = false # Disables security vulnerability
```

ERROR
        error(message)
      end

      warn(<<~WARNING)
        You set your `config.assets.compile = true` in production.
        This can negatively impact the performance of your application.

      WARNING
    end
  end

private

  def warn_x_sendfile_use!
    return false unless @x_sendfile_config.success?
    if @x_sendfile_config.did_match?("X-Sendfile") && !has_apache? # Apache
      warn(<<~WARNING)
        You set `config.action_dispatch.x_sendfile_header = 'X-Sendfile'` in production,
        but you do not have `apache` installed on this app. This setting will cause any assets
        being served by your application to be returned without a body.

        To fix this issue, please set:

        ```
        config.action_dispatch.x_sendfile_header = nil
        ```
      WARNING
    end

    if @x_sendfile_config.did_match?("X-Accel-Redirect") && !has_nginx? # Nginx
      warn(<<~WARNING)
        You set `config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect'` in production,
        but you do not have `nginx` installed on this app. This setting will cause any assets
        being served by your application to be returned without a body.

        To fix this issue, please set:

        ```
        config.action_dispatch.x_sendfile_header = nil
        ```
      WARNING
    end
  end

  def has_apache?
    path = run("which apachectl")
    return true if path && $?.success?
    return false
  end

  def has_nginx?
    path = run("which nginx")
    return true if path && $?.success?
    return false
  end

  def sprocket_version_upgrade_needed
    # Due to https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2018-3760
    sprockets_version = bundler.gem_version('sprockets')
    if sprockets_version.nil?
      return false
    elsif sprockets_version < Gem::Version.new("2.12.5")
      return "2.12.5"
    elsif sprockets_version > Gem::Version.new("3") &&
          sprockets_version < Gem::Version.new("3.7.2")
      return "3.7.2"
    elsif sprockets_version > Gem::Version.new("4") &&
          sprockets_version < Gem::Version.new("4.0.0.beta8")
      return "4.0.0.beta8"
    else
      return false
    end
  end

  def assets_compile_enabled?
    return false unless @assets_compile_config.success?
    @assets_compile_config.did_match?("true")
  end

  def install_plugins
    return false if bundler.has_gem?('rails_12factor')
    plugins = {"rails_log_stdout" => "rails_stdout_logging", "rails3_serve_static_assets" => "rails_serve_static_assets" }.
                reject { |plugin, gem| bundler.has_gem?(gem) }
    return false if plugins.empty?
    plugins.each do |plugin, gem|
      warn "Injecting plugin '#{plugin}'"
    end
    warn "Add 'rails_12factor' gem to your Gemfile to skip plugin injection"
    LanguagePack::Helpers::PluginsInstaller.new(plugins.keys).install
  end

  # runs the tasks for the Rails 3.1 asset pipeline
  def run_assets_precompile_rake_task
    if File.exist?("public/assets/manifest.yml")
      puts "Detected manifest.yml, assuming assets were compiled locally"
      return true
    end

    precompile = rake.task("assets:precompile")
    return true unless precompile.is_defined?

    topic("Preparing app for Rails asset pipeline")

    precompile.invoke(env: rake_env)

    if precompile.success?
      puts "Asset precompilation completed (#{"%.2f" % precompile.time}s)"
    else
      precompile_fail(precompile.output)
    end
  end

  # generate a dummy database_url
  def database_url
    # need to use a dummy DATABASE_URL here, so rails can load the environment
    return env("DATABASE_URL") if env("DATABASE_URL")
    scheme =
      if bundler.has_gem?("pg") || bundler.has_gem?("jdbc-postgres")
        "postgres"
    elsif bundler.has_gem?("mysql")
      "mysql"
    elsif bundler.has_gem?("mysql2")
      "mysql2"
    elsif bundler.has_gem?("sqlite3") || bundler.has_gem?("sqlite3-ruby")
      "sqlite3"
    end
    "#{scheme}://user:pass@127.0.0.1/dbname"
  end
end

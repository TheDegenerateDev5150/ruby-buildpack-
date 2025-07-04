require "language_pack"
require "language_pack/rails3"

# Rails 4 Language Pack. This is for all Rails 4.x apps.
class LanguagePack::Rails4 < LanguagePack::Rails3
  ASSETS_CACHE_LIMIT = 52428800 # bytes

  # detects if this is a Rails 4.x app
  # @return [Boolean] true if it's a Rails 4.x app
  def self.use?
    rails_version = bundler.gem_version('railties')
    return false unless rails_version
    is_rails4 = rails_version >= Gem::Version.new('4.0.0.beta') &&
                rails_version <  Gem::Version.new('4.1.0.beta1')
    return is_rails4
  end

  def name
    "Ruby/Rails"
  end

  def default_process_types
    super.merge({
      "web"     => "bin/rails server -p ${PORT:-5000} -e $RAILS_ENV",
      "console" => "bin/rails console"
    })
  end

  def compile
    super
  end

  private

  def install_plugins
    return false if bundler.has_gem?('rails_12factor')
    plugins = ["rails_serve_static_assets", "rails_stdout_logging"].reject { |plugin| bundler.has_gem?(plugin) }
    return false if plugins.empty?

    warn <<~WARNING
      Include 'rails_12factor' gem to enable all platform features
      See https://doc.scalingo.com/languages/ruby/rails-integration-gems for more information.
    WARNING
    # do not install plugins, do not call super
  end

  def public_assets_folder
    "public/assets"
  end

  def default_assets_cache
    "tmp/cache/assets"
  end

  def cleanup
    super
    return if assets_compile_enabled?
    return unless Dir.exist?(default_assets_cache)
    FileUtils.remove_dir(default_assets_cache)
  end

  def run_assets_precompile_rake_task
    if Dir.glob("public/assets/{.sprockets-manifest-*.json,manifest-*.json}", File::FNM_DOTMATCH).any?
      puts "Detected manifest file, assuming assets were compiled locally"
      return true
    end

    precompile = rake.task("assets:precompile")
    return true if precompile.not_defined?

    topic("Preparing app for Rails asset pipeline")

    @cache.load_without_overwrite public_assets_folder
    @cache.load default_assets_cache

    precompile.invoke(env: rake_env)

    if precompile.success?
      puts "Asset precompilation completed (#{"%.2f" % precompile.time}s)"

      clean_task = rake.task("assets:clean")
      if clean_task.task_defined?
        puts "Cleaning assets"
        clean_task.invoke(env: rake_env)

        cleanup_assets_cache
        @cache.store public_assets_folder
        @cache.store default_assets_cache
      end
    else
      precompile_fail(precompile.output)
    end
  end

  def cleanup_assets_cache
    LanguagePack::Helpers::StaleFileCleaner.new(default_assets_cache).clean_over(ASSETS_CACHE_LIMIT)
  end
end

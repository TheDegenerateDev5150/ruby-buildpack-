require "language_pack"
require "language_pack/base"

class LanguagePack::Metadata
  FOLDER = 'vendor/scalingo'

  def initialize(cache)
    ensure_sc_compat
    if cache
      @cache = cache
      @cache.load FOLDER
    end
  end

  def [](key)
    read(key)
  end

  def []=(key, value)
    write(key, value)
  end

  def read(key)
    full_key = "#{FOLDER}/#{key}"
    File.read(full_key).strip if exists?(key)
  end

  def exists?(key)
    full_key = "#{FOLDER}/#{key}"
    File.exist?(full_key) && !Dir.exist?(full_key)
  end
  alias_method :include?, :exists?

  def write(key, value, isave = true)
    FileUtils.mkdir_p(FOLDER)

    full_key = "#{FOLDER}/#{key}"
    File.open(full_key, 'w') {|f| f.puts value }
    save if isave

    return true
  end

  def touch(key)
    write(key, "true")
  end

  def fetch(key)
    return read(key) if exists?(key)

    value = yield

    write(key, value.to_s)
    return value
  end

  def save(file = FOLDER)
    @cache ? @cache.add(file) : false
  end

  protected

  def ensure_sc_compat
    if File.exist?('vendor/scalingo') && !File.exist?(FOLDER)
      FileUtils.mv('vendor/scalingo', FOLDER)
    end
  end
end

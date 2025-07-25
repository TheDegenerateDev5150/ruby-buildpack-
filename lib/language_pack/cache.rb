require "pathname"
require "language_pack"

# Manipulates/handles contents of the cache directory
class LanguagePack::Cache
  # @param [String] path to the cache store
  def initialize(cache_path)
    if cache_path
      @cache_base = Pathname.new(cache_path)
    else
      @cache_base = nil
    end
  end

  # removes the the specified path from the cache
  # @param [String] relative path from the cache_base
  def clear(path)
    return unless @cache_base

    target = (@cache_base + path)
    target.exist? && target.rmtree
  end

  # Overwrite cache contents
  # When called the cache destination will be cleared and the new contents coppied over
  # This method is perferable as LanguagePack::Cache#add can cause accidental cache bloat.
  #
  # @param [String] path of contents to store. it will be stored using this a relative path from the cache_base.
  # @param [String] relative path to store the cache contents, if nil it will assume the from path
  def store(from, path = nil)
    return unless @cache_base

    path ||= from
    clear path
    copy from, (@cache_base + path)
  end

  # Adds file to cache without clearing the destination
  # Use LanguagePack::Cache#store to avoid accidental cache bloat
  def add(from, path = nil)
    return unless @cache_base

    path ||= from
    copy from, (@cache_base + path)
  end

  # load cache contents
  # @param [String] relative path of the cache contents
  # @param [String] path of where to store it locally, if nil, assume same relative path as the cache contents
  def load(path, dest = nil)
    return unless @cache_base

    dest ||= path
    copy (@cache_base + path), dest
  end

  def load_without_overwrite(path, dest=nil)
    return unless @cache_base

    dest ||= path

    case ENV["STACK"]
    when "heroku-22", "scalingo-20", "scalingo-22"
      copy (@cache_base + path), dest, "-a -n"
    else
      copy (@cache_base + path), dest, "-a --update=none"
    end
  end

  # copy cache contents
  # @param [String] source directory
  # @param [String] destination directory
  def copy(from, to, options='-a')
    return unless @cache_base

    return false unless File.exist?(from)
    return true if File.expand_path(from) == File.expand_path(to) # see story 80029582
    FileUtils.mkdir_p File.dirname(to)
    command = "cp #{options} #{from}/. #{to}"
    system(command)
    raise "Command failed `#{command}`" unless $?
  end

  # copy contents between to places in the cache
  # @param [String] source cache directory
  # @param [String] destination directory
  def cache_copy(from,to)
    return unless @cache_base

    copy(@cache_base + from, @cache_base + to)
  end

  # check if the cache content exists
  # @param [String] relative path of the cache contents
  # @param [Boolean] true if the path exists in the cache and false if otherwise
  def exists?(path)
    return unless @cache_base

    File.exist?(@cache_base + path)
  end
end

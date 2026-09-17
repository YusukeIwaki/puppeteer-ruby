# frozen_string_literal: true

# File operations honoring the global symlink policy
# (Puppeteer.set_follow_symlinks). When following is disabled, paths are
# opened with O_NOFOLLOW so symlinks raise Errno::ELOOP instead of being
# traversed. Platforms without O_NOFOLLOW (Windows) ignore the policy.
module Puppeteer::FileSystem
  WRITE_NOFOLLOW_MODE = 0o600

  # @rbs return: bool -- Whether file operations follow symlinks
  def self.follow_symlinks
    defined?(@follow_symlinks) ? @follow_symlinks : true
  end

  # @rbs value: bool -- Whether file operations should follow symlinks
  # @rbs return: bool -- The new value
  def self.follow_symlinks=(value)
    @follow_symlinks = value
  end

  def self.nofollow_supported?
    defined?(File::NOFOLLOW) == 'constant'
  end

  # Whether paths must currently be opened without following symlinks.
  def self.protected?
    !follow_symlinks && nofollow_supported?
  end

  # Reads a text file, refusing symlinks while protected.
  #
  # @rbs path: String -- File path
  # @rbs encoding: Encoding -- Text encoding
  # @rbs return: String -- File content
  def self.read_file(path, encoding: Encoding::UTF_8)
    if protected?
      File.open(path, File::RDONLY | File::NOFOLLOW, encoding: encoding, &:read)
    else
      File.read(path, encoding: encoding)
    end
  end

  # Writes data to a file, refusing symlinks while protected.
  #
  # @rbs path: String -- File path
  # @rbs data: String -- Bytes to write
  # @rbs return: Integer -- Bytes written
  def self.write_file(path, data)
    if protected?
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC | File::NOFOLLOW | File::BINARY, WRITE_NOFOLLOW_MODE) do |file|
        file.write(data)
      end
    else
      File.binwrite(path, data)
    end
  end

  # Opens a file for streaming writes, refusing symlinks while protected.
  # The caller must close the returned file.
  #
  # @rbs path: String -- File path
  # @rbs mode: String -- Open mode used when unprotected
  # @rbs return: File -- Open file handle
  def self.open_for_writing(path, mode: 'wb')
    if protected?
      flags = File::WRONLY | File::CREAT | File::TRUNC | File::NOFOLLOW
      flags |= File::BINARY if mode.include?('b')
      File.open(path, flags, WRITE_NOFOLLOW_MODE)
    else
      File.open(path, mode)
    end
  end

  # Opens a file for exclusive creation, refusing symlinks while protected.
  # Raises Errno::EEXIST when the path already exists, Errno::ELOOP for a
  # symlink while protected. The caller must close the returned file.
  #
  # @rbs path: String -- File path
  # @rbs return: File -- Open file handle
  def self.open_exclusive(path)
    flags = File::WRONLY | File::CREAT | File::EXCL | File::BINARY
    flags |= File::NOFOLLOW if protected?
    File.open(path, flags)
  end

  self.follow_symlinks = true
end

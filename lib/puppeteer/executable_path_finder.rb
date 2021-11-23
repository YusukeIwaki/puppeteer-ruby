class Puppeteer::ExecutablePathFinder
  # @param executable_names [Array<String>] executable file names to find.
  def initialize(*executable_names)
    @executable_names = executable_names
  end

  def find_executables_in_path
    Enumerator.new do |result|
      @executable_names.each do |name|
        # Find the first existing path.
        paths.each do |path|
          candidate = File.join(path, name)
          next unless File.exist?(candidate)
          result << candidate
          break
        end
      end
    end
  end

  def find_first
    find_executables_in_path.first
  end

  private def paths
    ENV['PATH'].split(File::PATH_SEPARATOR)
  end
end

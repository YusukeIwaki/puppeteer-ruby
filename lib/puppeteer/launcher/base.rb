module Puppeteer::Launcher
  class Base
    # @param {string} projectRoot
    # @param {string} preferredRevision
    def initialize(project_root:, preferred_revision:, is_puppeteer_core:)
      @project_root = project_root
      @preferred_revision = preferred_revision
      @is_puppeteer_core = is_puppeteer_core
    end

    class ExecutablePathNotFound < StandardError; end

    # @returns [String] Chrome Executable file path.
    # @raise [ExecutablePathNotFound]
    def resolve_executable_path
      if !@is_puppeteer_core
        # puppeteer-core doesn't take into account PUPPETEER_* env variables.
        executable_path = ENV['PUPPETEER_EXECUTABLE_PATH']
        if FileTest.exist?(executable_path)
          return executable_path
        end
        raise ExecutablePathNotFound.new(
          "Tried to use PUPPETEER_EXECUTABLE_PATH env variable to launch browser but did not find any executable at: #{executable_path}",
        )
      end

      # temporal logic.
      if Puppeteer.env.darwin?
        case self
        when Chrome
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
        when Firefox
          '/Applications/Firefox Nightly.app/Contents/MacOS/firefox'
        end
      else
        case self
        when Chrome
          '/usr/bin/google-chrome'
        when Firefox
          '/usr/bin/firefox'
        end
      end

      # const browserFetcher = new BrowserFetcher(launcher._projectRoot);
      # if (!launcher._isPuppeteerCore) {
      #   const revision = process.env['PUPPETEER_CHROMIUM_REVISION'];
      #   if (revision) {
      #     const revisionInfo = browserFetcher.revisionInfo(revision);
      #     const missingText = !revisionInfo.local ? 'Tried to use PUPPETEER_CHROMIUM_REVISION env variable to launch browser but did not find executable at: ' + revisionInfo.executablePath : null;
      #     return {executablePath: revisionInfo.executablePath, missingText};
      #   }
      # }
      # const revisionInfo = browserFetcher.revisionInfo(launcher._preferredRevision);
      # const missingText = !revisionInfo.local ? `Browser is not downloaded. Run "npm install" or "yarn install"` : null;
      # return {executablePath: revisionInfo.executablePath, missingText};
    end
  end
end

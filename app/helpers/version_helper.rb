module VersionHelper

  # Returns the version of the application. In case the application is running in a development environment,
  # the version is determined from the git repository. Otherwise, the version is determined from the environment
  # variables GIT_TAG, GIT_BRANCH and GIT_COMMIT.
  #
  # @return [String] the version of the application
  def app_version
    if development_environment?
      version_from_git
    else
      version_from_environment
    end
  end

  # Returns the given version string as integer for easy version comparison.
  # The version string must be in the format: v<major>.<minor>.<patch>
  # @param [String] version_string the version string to convert to an integer
  # @return [Integer] the version string as integer
  def version_as_int(version_string)
    # remove the leading 'v' from the version string, then split the version string into an array of integers and return
    # the first 3 elements of the array as an integer with the following calculation:
    # major * 10000 + minor * 100 + patch
    raise ArgumentError, "Invalid version string: #{version_string}" unless version_string =~ /^v\d+\.\d+\.\d+/
    # if any gibberish is appended to the "official" version string, it is ignored (like branch name or commit hash)
    version_string[1..]&.split('.').map(&:to_i).first(3).inject(0) { |a, e| a * 100 + e }
  end

  # Returns the given version integer as string.
  # @param [Integer] version_int the version integer to convert to a string
  # @return [String] the version integer as string
  # @example
  #   version_int = 304
  #   int_as_version(version_int)
  #   => "v0.3.4"
  def int_as_version(version_int)
    major = version_int / 10000
    minor = (version_int - major * 10000) / 100
    patch = version_int - major * 10000 - minor * 100
    "v#{major}.#{minor}.#{patch}"
  end

  private

  # Returns true if the application is running in a development environment.
  # This is determined by checking if the .git directory exists in the application root directory.
  #
  # @return [Boolean] true if the application is running in a development environment
  def development_environment?
    File.directory?(Rails.root.join('.git'))
  end

  # Returns the version of the application determined from the git repository.
  #
  # The format of the version is: <tag>-<branch>-<commit>(-dirty)
  # where <tag> is the latest descendant git tag, <branch> is the current git branch, <commit> is the current shortened
  # git commit SHA-1 and dirty is appended if the git repository is dirty.
  #
  # If the git repository is not tagged, the version is: <branch>-<commit>(-dirty). In case the tag is the same as
  # the current commit, the commit SHA-1 is omitted. In case the branch is main or master, the branch name is omitted.
  #
  # @return [String] the version of the application
  #
  # @note this method uses the Rugged Gem to access the git repository, which internally uses libgit2 and doesn't fork a
  #      separate process like the git Gem does.
  def version_from_git
    repo = Rugged::Repository.new(Rails.root.to_s)

    # Get the current commit
    current_commit = repo.head.target

    # Get the current branch
    current_branch = repo.head.name.sub("refs/heads/", "")

    # Get the current commit (first 7 characters)
    current_commit_short = current_commit.oid[0, 7]

    # Find the latest ancestor tag
    latest_ancestor_tag = repo.tags.sort_by { |t| repo.lookup(t.target.oid).time }
                              .select { |t| repo.descendant_of?(current_commit.oid, t.target.oid) }
                              .last

    # Check if the repo is dirty
    dirty = ''
    repo.status do |file, status|
      if status != 'WT_NEW'
        dirty = '-dirty'
        break
      end
    end

    # Build the version string
    if latest_ancestor_tag
      version = "#{latest_ancestor_tag.name}"
    else
      version = ""
    end

    unless ["main", "master"].include?(current_branch)
      version += "-#{current_branch}" unless version.empty?
    end

    version += "-#{current_commit_short}" unless latest_ancestor_tag&.target_id == current_commit.oid
    version + dirty
  end

  # Returns the version of the application determined from the environment variables GIT_TAG, GIT_BRANCH and GIT_COMMIT.
  # The format of the version is: either <tag> or <branch>-<commit>
  #
  # @return [String] the version of the application
  def version_from_environment
    version_parts = []
    version_parts << ENV['GIT_TAG'] if ENV['GIT_TAG'].present?

    branch = non_default_env_branch
    version_parts << branch if branch.present? && version_parts.empty?

    version_parts << ENV['GIT_COMMIT'] if ENV['GIT_COMMIT'].present? && ENV['GIT_TAG'].blank?
    version_parts.compact.join('-')
  end

  # Returns the current git branch from the environment variable GIT_BRANCH if it is not the default branch
  # (main or master). Otherwise, nil is returned.
  #
  # @return [String, nil] the current git branch from the environment variable GIT_BRANCH if it is not the default
  #                       branch (main or master)
  def non_default_env_branch
    branch = ENV['GIT_BRANCH']
    branch unless branch == 'main' || branch == 'master'
  end
end

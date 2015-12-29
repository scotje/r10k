require 'r10k/git'
require 'r10k/git/errors'
require 'forwardable'
require 'r10k/logging'
require 'json'

# Manage how Git repositories are created and set to specific refs
class R10K::Git::StatefulRepository

  include R10K::Logging

  # @!attribute [r] repo
  #   @api private
  attr_reader :repo
  attr_accessor :head

  extend Forwardable
  #def_delegators :@repo, :head

  # Create a new shallow git working directory
  #
  # @param ref     [String] The git ref to check out
  # @param remote  [String] The git remote to use for the repo
  # @param basedir [String] The path containing the Git repo
  # @param dirname [String] The directory name of the Git repo
  def initialize(ref, remote, basedir, dirname)
    @ref = ref
    @remote = remote

    @cache = R10K::Git.cache.generate(remote)
    @repo = R10K::Git.thin_repository.new(basedir, dirname, @cache)

    @worktree = File.join(basedir, dirname)
  end

  def sync
    @cache.sync if sync_cache?

    sha = @head = @cache.resolve(@ref)

    if sha.nil?
      raise R10K::Git::UnresolvableRefError.new("Unable to sync repo to unresolvable ref '#{@ref}'", :git_dir => @repo.git_dir)
    end

    if !File.directory?(@worktree) || !File.exists?(File.join(@worktree, '.r10k-deploy.json'))
      FileUtils.remove_entry_secure(@worktree, true)
      FileUtils.mkdir_p(@worktree)
    end

    logger.debug { "Ensuring #{@repo.path} is at #{@ref}" }
    @cache.repo.send(:git, ["reset", "--hard", sha], { :work_tree => @worktree, :git_dir => @cache.repo.git_dir.to_s })

    # FIXME: this should maybe be controlled by an option
    @cache.repo.send(:git, ["clean", "--force", "-e", ".r10k-deploy.json"], { :work_tree => @worktree, :git_dir => @cache.repo.git_dir.to_s })
  end

  def status(target_sha=nil)
    if !File.directory?(@worktree)
      return :absent
    end

    r10k_info = nil

    begin
      File.open("#{@worktree}/.r10k-deploy.json", "r") do |fh|
        r10k_info = JSON.parse(fh.read)
      end
    rescue
      # FIXME: rescue file not found and JSON parse errors only
      return :mismatched
    end

    if File.exist?("#{@worktree}/.git")
      return :mismatched
    elsif !target_sha || (r10k_info["signature"] != target_sha)
      return :outdated
    else
      return :insync
    end
  end

  # @api private
  def sync_cache?
    return true if !@cache.exist?
    return true if !@cache.resolve(@ref)
    return true if !([:commit, :tag].include? @cache.ref_type(@ref))
    return false
  end
end

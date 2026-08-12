# frozen_string_literal: true

require "fileutils"

require_relative "commands"

module Litestream
  # Removes orphaned Litestream v0.3 shadow-WAL directories left behind after an
  # upgrade to v0.5.x. v0.5 writes LTX data to `<meta>/ltx` and never reads or
  # deletes the old `<meta>/generations` tree, so it accumulates as dead weight.
  module Cleanup
    # raised when an orphaned generations/ directory could not be deleted
    CleanupFailedException = Class.new(StandardError)

    # Directory Litestream keeps beside each database, e.g. `.app.sqlite3-litestream`.
    META_DIR_SUFFIX = "-litestream"

    # v0.3 shadow-WAL subdirectory (dead under v0.5).
    GENERATIONS_DIR = "generations"

    # v0.5 LTX subdirectory. A non-empty one signals v0.5 has taken over replication.
    LTX_DIR = "ltx"

    Summary = Struct.new(:removed, keyword_init: true)

    class << self
      # Enumerate configured databases and delete each one's orphaned
      # `generations/` tree, but only when a non-empty `ltx/` directory beside it
      # confirms v0.5 has taken over. Returns a Summary of the removed paths (or,
      # under dry_run, the paths that would be removed).
      def clean!(dry_run: false)
        removed = []
        failures = []

        eligible_generations_dirs.each do |generations|
          if dry_run
            removed << generations
            next
          end

          begin
            FileUtils.rm_r(generations, secure: true)
            removed << generations
          rescue SystemCallError => error
            failures << [generations, error.message]
          end
        end

        raise CleanupFailedException, failure_message(failures, removed) if failures.any?

        Summary.new(removed: removed)
      end

      private

      def eligible_generations_dirs
        Litestream::Commands.databases.filter_map do |db|
          path = db["path"]
          next if path.nil?

          meta = File.join(File.dirname(path), ".#{File.basename(path)}#{META_DIR_SUFFIX}")
          generations = File.join(meta, GENERATIONS_DIR)
          ltx = File.join(meta, LTX_DIR)

          generations if Dir.exist?(generations) && ltx_replicated?(ltx)
        end
      end

      # v0.5 has taken over only once it has written a real LTX file. An `ltx/`
      # dir holding just an empty level subdirectory (e.g. `ltx/0/`, created on
      # boot before the first sync) is not proof of replication, so we require at
      # least one `.ltx` file before deleting the old generations tree.
      def ltx_replicated?(ltx)
        Dir.exist?(ltx) && Dir.glob(File.join(ltx, "**", "*.ltx")).any?
      end

      def failure_message(failures, removed)
        details = failures.map { |path, reason| "  #{path}\n  Reason: #{reason}" }.join("\n\n")
        cleaned = removed.empty? ? "(none)" : removed.join("\n  ")

        <<~MESSAGE
          Could not delete orphaned Litestream v0.3 data at:

          #{details}

          Successfully removed before the failure:
            #{cleaned}

          Free the space manually after confirming v0.5 replication is healthy:
              ls -la <meta-dir>
              rm -rf <failed-path>

          See https://github.com/fractaledmind/litestream-ruby/issues/6
        MESSAGE
      end
    end
  end
end

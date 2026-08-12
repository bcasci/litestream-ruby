namespace :litestream do
  desc "Print the ENV variables needed for the Litestream config file"
  task env: :environment do
    puts "LITESTREAM_REPLICA_BUCKET=#{Litestream.replica_bucket}"
    puts "LITESTREAM_REPLICA_REGION=#{Litestream.replica_region}"
    puts "LITESTREAM_REPLICA_ENDPOINT=#{Litestream.replica_endpoint}"
    puts "LITESTREAM_ACCESS_KEY_ID=#{Litestream.replica_key_id}"
    puts "LITESTREAM_SECRET_ACCESS_KEY=#{Litestream.replica_access_key}"

    true
  end

  desc 'Monitor and continuously replicate SQLite databases defined in your config file, for example `rake litestream:replicate -- -exec "foreman start"`'
  task replicate: :environment do
    options = parse_argv_options

    Litestream::Commands.replicate(**options)
  end

  desc "Restore a SQLite database from a Litestream replica, for example `rake litestream:restore -- -database=storage/production.sqlite3`"
  task restore: :environment do
    options = parse_argv_options
    database = options.delete(:"--database") || options.delete(:"-database")

    puts Litestream::Commands.restore(database, **options)
  end

  desc "List all databases and associated replicas in the config file, for example `rake litestream:databases -- -no-expand-env`"
  task databases: :environment do
    options = parse_argv_options

    puts Litestream::Commands::Output.format(Litestream::Commands.databases(**options))
  end

  desc "List all generations for a database or replica, for example `rake litestream:generations -- -database=storage/production.sqlite3`"
  task generations: :environment do
    options = parse_argv_options
    database = options.delete(:"--database") || options.delete(:"-database")

    puts Litestream::Commands::Output.format(Litestream::Commands.generations(database, **options))
  end

  desc "Download the Litestream binary for the current platform (required when installing from a git source)"
  task download: :environment do
    exe_path = Litestream::Commands.download
    puts "Downloaded Litestream binary to #{exe_path}"
  end

  desc "Delete orphaned Litestream v0.3 shadow-WAL (`generations/`) directories left after upgrading to v0.5, for example `rake litestream:prune_v0_3_generations -- -dry-run`"
  task prune_v0_3_generations: :environment do
    options = parse_argv_options
    dry_run = options.key?(:"-dry-run") || options.key?(:"--dry-run")

    summary = Litestream::Cleanup.clean!(dry_run: dry_run)

    if summary.removed.empty?
      puts "No orphaned Litestream v0.3 `generations/` directories found."
    else
      count = summary.removed.length
      verb = dry_run ? "Would remove" : "Removed"
      noun = (count == 1) ? "directory" : "directories"
      puts "#{verb} #{count} orphaned Litestream v0.3 `generations/` #{noun}:"
      summary.removed.each { |path| puts "  #{path}" }
    end
  end

  desc "List all LTX files for a database or replica, for example `rake litestream:ltx -- -database=storage/production.sqlite3`"
  task ltx: :environment do
    options = parse_argv_options
    database = options.delete(:"--database") || options.delete(:"-database")

    puts Litestream::Commands::Output.format(
      Litestream::Commands.ltx(database, **options)
    )
  end

  private

  def parse_argv_options
    options = {}
    if (separator_index = ARGV.index("--"))
      ARGV.slice(separator_index + 1, ARGV.length)
        .map { |pair| pair.split("=") }
        .each { |opt| options[opt[0]] = opt[1] || nil }
    end
    options.symbolize_keys!
  end
end

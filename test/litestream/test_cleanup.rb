# frozen_string_literal: true

require "test_helper"

class TestCleanup < ActiveSupport::TestCase
  def setup
    @root = File.expand_path("../../tmp/cleanup_test", __dir__)
    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  # Build a database file plus its `.<basename>-litestream` meta dir, optionally
  # seeding the generations/ and ltx/ subtrees. Returns the db path.
  def build_db(name, generations: false, ltx: nil)
    db_path = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(db_path))
    File.write(db_path, "")

    meta = File.join(File.dirname(db_path), ".#{File.basename(db_path)}-litestream")

    if generations
      wal = File.join(meta, "generations", "443618af4a6368d1", "wal")
      FileUtils.mkdir_p(wal)
      File.write(File.join(wal, "0000000000000000.wal"), "x")
    end

    unless ltx.nil?
      ltx_dir = File.join(meta, "ltx")
      FileUtils.mkdir_p(ltx_dir)
      case ltx
      when :non_empty
        level = File.join(ltx_dir, "0")
        FileUtils.mkdir_p(level)
        File.write(File.join(level, "0000-0001.ltx"), "y")
      when :level_only
        # v0.5 created the level dir on boot but has not synced an .ltx file yet
        FileUtils.mkdir_p(File.join(ltx_dir, "0"))
      end
    end

    db_path
  end

  def generations_dir(db_path)
    File.join(File.dirname(db_path), ".#{File.basename(db_path)}-litestream", "generations")
  end

  def ltx_dir(db_path)
    File.join(File.dirname(db_path), ".#{File.basename(db_path)}-litestream", "ltx")
  end

  def stub_databases(*db_paths)
    entries = db_paths.map { |p| {"path" => p} }
    Litestream::Commands.stub :databases, entries do
      yield
    end
  end

  def test_removes_generations_when_ltx_is_non_empty
    db = build_db("app.sqlite3", generations: true, ltx: :non_empty)

    stub_databases(db) do
      Litestream::Cleanup.clean!
    end

    refute Dir.exist?(generations_dir(db))
  end

  def test_keeps_generations_when_ltx_absent
    db = build_db("app.sqlite3", generations: true, ltx: nil)

    stub_databases(db) do
      Litestream::Cleanup.clean!
    end

    assert Dir.exist?(generations_dir(db))
  end

  def test_keeps_generations_when_ltx_is_empty
    db = build_db("app.sqlite3", generations: true, ltx: :empty)

    stub_databases(db) do
      Litestream::Cleanup.clean!
    end

    assert Dir.exist?(generations_dir(db))
  end

  def test_keeps_generations_when_ltx_has_only_empty_level_dir
    db = build_db("app.sqlite3", generations: true, ltx: :level_only)

    stub_databases(db) do
      Litestream::Cleanup.clean!
    end

    assert Dir.exist?(generations_dir(db))
  end

  def test_preserves_ltx_dir_db_file_and_meta_dir
    db = build_db("app.sqlite3", generations: true, ltx: :non_empty)
    meta = File.dirname(ltx_dir(db))

    stub_databases(db) do
      Litestream::Cleanup.clean!
    end

    assert Dir.exist?(ltx_dir(db))
    assert File.exist?(db)
    assert Dir.exist?(meta)
  end

  def test_skips_database_with_no_meta_dir
    db = build_db("app.sqlite3")

    summary = stub_databases(db) do
      Litestream::Cleanup.clean!
    end

    assert_equal [], summary.removed
  end

  def test_skips_meta_dir_with_no_generations
    db = build_db("app.sqlite3", ltx: :non_empty)

    summary = stub_databases(db) do
      Litestream::Cleanup.clean!
    end

    assert_equal [], summary.removed
  end

  def test_removes_only_eligible_database
    eligible = build_db("eligible.sqlite3", generations: true, ltx: :non_empty)
    ineligible = build_db("ineligible.sqlite3", generations: true, ltx: :empty)

    summary = stub_databases(eligible, ineligible) do
      Litestream::Cleanup.clean!
    end

    assert_equal [generations_dir(eligible)], summary.removed
    refute Dir.exist?(generations_dir(eligible))
    assert Dir.exist?(generations_dir(ineligible))
  end

  def test_derives_meta_dir_beside_database_path
    db = build_db("storage/app.sqlite3", generations: true, ltx: :non_empty)
    expected = File.join(@root, "storage", ".app.sqlite3-litestream", "generations")

    summary = stub_databases(db) do
      Litestream::Cleanup.clean!
    end

    assert_equal [expected], summary.removed
  end

  def test_dry_run_deletes_nothing_but_reports
    db = build_db("app.sqlite3", generations: true, ltx: :non_empty)

    summary = stub_databases(db) do
      Litestream::Cleanup.clean!(dry_run: true)
    end

    assert Dir.exist?(generations_dir(db))
    assert_equal [generations_dir(db)], summary.removed
  end

  def test_deletion_failure_raises_with_path_and_reason
    db = build_db("app.sqlite3", generations: true, ltx: :non_empty)

    error = assert_raises(Litestream::Cleanup::CleanupFailedException) do
      FileUtils.stub :rm_r, ->(*) { raise Errno::EACCES, generations_dir(db) } do
        stub_databases(db) do
          Litestream::Cleanup.clean!
        end
      end
    end

    assert_includes error.message, generations_dir(db)
    assert_includes error.message, "Permission denied"
  end

  def test_multiple_failures_are_aggregated
    first = build_db("first.sqlite3", generations: true, ltx: :non_empty)
    second = build_db("second.sqlite3", generations: true, ltx: :non_empty)

    error = assert_raises(Litestream::Cleanup::CleanupFailedException) do
      FileUtils.stub :rm_r, ->(path, **) { raise Errno::EACCES, path } do
        stub_databases(first, second) do
          Litestream::Cleanup.clean!
        end
      end
    end

    assert_includes error.message, generations_dir(first)
    assert_includes error.message, generations_dir(second)
  end
end

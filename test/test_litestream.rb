# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestLitestream < Minitest::Test
  def teardown
    Litestream.systemctl_command = nil
    Litestream.replica_bucket = nil
    Litestream.replica_key_id = nil
    Litestream.replica_access_key = nil
  end

  # A stand-in for Process::Status that answers #exitstatus.
  ExitStatus = Struct.new(:exitstatus)

  # Build a stub for the private `capture` helper. `responses` maps an expected
  # argv array to the stdout string it should return; the status is always 0.
  def capture_stub(responses)
    proc do |*command|
      match = responses.find { |cmd, _| cmd == command }
      [match ? match[1] : "", ExitStatus.new(0)]
    end
  end

  def test_that_it_has_a_version_number
    refute_nil ::Litestream::VERSION
  end

  def test_replicate_process_systemd
    stubbed_status = ["● litestream.service - Litestream",
      "     Loaded: loaded (/lib/systemd/system/litestream.service; enabled; vendor preset: enabled)",
      "     Active: active (running) since Tue 2023-07-25 13:49:43 UTC; 8 months 24 days ago",
      "   Main PID: 1179656 (litestream)",
      "      Tasks: 9 (limit: 1115)",
      "     Memory: 22.9M",
      "        CPU: 10h 49.843s",
      "     CGroup: /system.slice/litestream.service",
      "             └─1179656 /usr/bin/litestream replicate",
      "",
      "Warning: some journal files were not opened due to insufficient permissions."].join("\n")

    stub = capture_stub([
      [["which", "systemctl"], "/usr/bin/systemctl\n"],
      [["systemctl", "status", "litestream"], stubbed_status]
    ])

    Litestream.stub :capture, stub do
      info = Litestream.replicate_process

      assert_equal "running", info[:status]
      assert_equal "1179656", info[:pid]
      assert_equal DateTime, info[:started].class
    end
  end

  def test_replicate_process_systemd_custom_command
    stubbed_status = ["● myapp-litestream.service - Litestream",
      "     Loaded: loaded (/lib/systemd/system/litestream.service; enabled; vendor preset: enabled)",
      "     Active: active (running) since Tue 2023-07-25 13:49:43 UTC; 8 months 24 days ago",
      "   Main PID: 1179656 (litestream)",
      "      Tasks: 9 (limit: 1115)",
      "     Memory: 22.9M",
      "        CPU: 10h 49.843s",
      "     CGroup: /system.slice/litestream.service",
      "             └─1179656 /usr/bin/litestream replicate",
      "",
      "Warning: some journal files were not opened due to insufficient permissions."].join("\n")
    Litestream.systemctl_command = "systemctl --user status myapp-litestream.service"

    stub = capture_stub([
      [["which", "systemctl"], "/usr/bin/systemctl\n"],
      [["systemctl", "--user", "status", "myapp-litestream.service"], stubbed_status]
    ])

    Litestream.stub :capture, stub do
      info = Litestream.replicate_process

      assert_equal "running", info[:status]
      assert_equal "1179656", info[:pid]
      assert_equal DateTime, info[:started].class
    end
  end

  def test_systemctl_command_with_shell_metacharacters_is_split_not_interpreted
    Litestream.systemctl_command = "systemctl status x; touch pwned"
    received = []

    stub = proc do |*command|
      received << command
      output = (command == ["which", "systemctl"]) ? "/usr/bin/systemctl\n" : ""
      [output, ExitStatus.new(0)]
    end

    Litestream.stub :capture, stub do
      Litestream.replicate_process
    end

    # The command is passed as a split argv array, so `;` and `touch` are inert tokens.
    assert_includes received, ["systemctl", "status", "x;", "touch", "pwned"]
  end

  def test_systemctl_absent_falls_through_to_process_info
    # `which systemctl` empty => systemctl_info returns nil; process_info yields {}.
    stub = capture_stub([[["which", "systemctl"], ""]])

    Litestream.stub :capture, stub do
      assert_nil Litestream.send(:systemctl_info)
    end
  end

  def test_replicate_process_ps
    stubbed_ps_list = [
      "40358 ttys008    0:01.11 ruby --yjit bin/rails litestream:replicate",
      "40364 ttys008    0:00.07 /path/to/litestream-ruby/exe/architecture/litestream replicate --config /path/to/app/config/litestream.yml"
    ].join("\n")

    stubbed_ps_status = [
      "STAT STARTED",
      "S+   Mon Jul  1 11:10:58 2024"
    ].join("\n")

    stub = capture_stub([
      [["which", "systemctl"], ""],
      [["ps", "-ax"], stubbed_ps_list],
      [["ps", "-o", "state,lstart", "40364"], stubbed_ps_status]
    ])

    Litestream.stub :capture, stub do
      info = Litestream.replicate_process

      assert_equal "sleeping", info[:status]
      assert_equal "40364", info[:pid]
      assert_equal DateTime, info[:started].class
    end
  end

  def test_replicate_process_returns_empty_hash_when_no_replicate_process
    stub = capture_stub([
      [["which", "systemctl"], ""],
      [["ps", "-ax"], "12345 ttys000   0:00.01 some other process"]
    ])

    Litestream.stub :capture, stub do
      assert_equal({}, Litestream.replicate_process)
    end
  end

  def test_replicate_process_survives_missing_binaries
    # No shell to swallow a missing binary: IO.popen raises Errno::ENOENT.
    # capture must rescue it so the dashboard degrades to {} instead of 500.
    IO.stub :popen, ->(*) { raise Errno::ENOENT, "systemctl" } do
      assert_equal({}, Litestream.replicate_process)
    end
  end

  def test_verify_reraises_original_error_when_database_open_fails
    boom = Class.new(StandardError)

    SQLite3::Database.stub :new, ->(*) { raise boom, "cannot open" } do
      error = assert_raises(boom) do
        Litestream.verify!("tmp/does_not_matter.sqlite3", replication_sleep: 0)
      end
      assert_equal "cannot open", error.message
    end
  end

  def test_verify_success_cleans_up_sentinel_and_backup
    FileUtils.mkdir_p("tmp")
    source = "tmp/verify_source_#{SecureRandom.hex(4)}.sqlite3"
    backup_path = nil

    # restore copies the live source db (already holding the sentinel) to its -o path.
    restore = proc do |db, **argv|
      backup_path = argv["-o"]
      FileUtils.cp(db, backup_path)
    end

    result = Litestream::Commands.stub :restore, restore do
      Litestream.verify!(source, replication_sleep: 0)
    end

    assert result
    refute_nil backup_path
    refute File.exist?(backup_path), "backup file should be cleaned up in the ensure block"
  ensure
    File.delete(source) if source && File.exist?(source)
  end

  def test_configure_is_removed
    refute Litestream.respond_to?(:configure)
    assert_nil defined?(Litestream::Configuration)
  end

  def test_deprecator_is_kept
    assert_kind_of ActiveSupport::Deprecation, Litestream.deprecator
  end

  def test_replica_credentials_resolve_from_writer_without_configuration_fallback
    Litestream.replica_bucket = "s3://mybkt"
    Litestream.replica_key_id = "key"
    Litestream.replica_access_key = "secret"

    assert_equal "s3://mybkt", Litestream.replica_bucket
    assert_equal "key", Litestream.replica_key_id
    assert_equal "secret", Litestream.replica_access_key
  end

  def test_databases_maps_paths_and_slices_generations
    db_path = "#{Rails.root}/storage/test.sqlite3"
    stubbed_databases = [{"path" => db_path, "replicas" => "s3"}]
    stubbed_generations = [{
      "generation" => "abc123",
      "name" => "s3",
      "lag" => "1s",
      "start" => "2024-05-02T11:32:16Z",
      "end" => "2024-05-02T11:33:10Z",
      "extra" => "should be dropped"
    }]

    Litestream::Commands.stub :databases, stubbed_databases do
      Litestream::Commands.stub :generations, stubbed_generations do
        result = Litestream.databases

        assert_equal "[ROOT]/storage/test.sqlite3", result.first["path"]
        assert_equal(
          {"generation" => "abc123", "name" => "s3", "lag" => "1s",
           "start" => "2024-05-02T11:32:16Z", "end" => "2024-05-02T11:33:10Z"},
          result.first["generations"].first
        )
      end
    end
  end
end

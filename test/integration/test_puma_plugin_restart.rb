# frozen_string_literal: true

require "test_helper"
require "socket"

# Boots a real Puma against the Litestream plugin and restarts it with SIGUSR2.
#
# The unit tests in test/test_puma_plugin.rb drive the plugin's lifecycle hooks
# directly, so they cannot see whether Puma calls those hooks at the right time.
# That ordering is half the defect in #14: `in_background` was registered from
# inside `on_booted`, after Puma had already run `Plugins.fire_background`, so
# the monitor never started. Only a booted Puma shows that. This mirrors how
# puma and rails/solid_queue test their own plugins.
class TestPumaPluginRestart < ActiveSupport::TestCase
  self.use_transactional_tests = false

  # Baked into the stub's command line so `ps` can find the processes this test
  # started and no others.
  SENTINEL = "litestream-puma-plugin-restart-test"

  BOOT_TIMEOUT = 30

  def setup
    @dummy_root = Rails.root
    @tmpdir = @dummy_root.join("tmp", SENTINEL)
    FileUtils.rm_rf(@tmpdir)
    FileUtils.mkdir_p(@tmpdir)
    write_stub_executable
    @puma_log = @tmpdir.join("puma.log")
    @puma_pid = boot_puma
  end

  def teardown
    stop_puma
    replication_pids.each { |pid| kill_and_reap(pid) }
    FileUtils.rm_rf(@tmpdir)
  end

  def test_a_restart_leaves_exactly_one_litestream_process
    first_pid = wait_for(BOOT_TIMEOUT, "Litestream to start") { replication_pids.first }

    Process.kill(:USR2, @puma_pid)

    surviving = wait_for(BOOT_TIMEOUT, "the restart to leave exactly one Litestream process") do
      pids = replication_pids
      pids.first if pids.size == 1 && pids.first != first_pid
    end

    assert_equal [surviving], replication_pids
  end

  # Puma 7 renamed the lifecycle events and warns on every boot for the old
  # names. The plugin registers under whichever names the events object has.
  def test_it_logs_no_puma_deprecation_warning
    wait_for(BOOT_TIMEOUT, "Litestream to start") { replication_pids.first }

    refute_includes read_puma_log, "is deprecated"
  end

  private

  # A stand-in for the litestream binary: it `exec`s a process that sleeps until
  # signalled, so the test can watch it start and stop. `RUBYOPT=` and
  # `--disable-gems` keep it from loading bundler, and the trap keeps SIGINT from
  # printing an `Interrupt` backtrace.
  def write_stub_executable
    stub = @tmpdir.join("litestream")
    File.write(stub, <<~SH)
      #!/bin/sh
      RUBYOPT= exec "#{RbConfig.ruby}" --disable-gems -e 'trap("INT") { exit }; sleep' -- #{SENTINEL} "$@"
    SH
    FileUtils.chmod(0o755, stub)
  end

  def boot_puma
    env = {
      "LITESTREAM_INSTALL_DIR" => @tmpdir.to_s,
      "PIDFILE" => @tmpdir.join("puma.pid").to_s,
      "PORT" => available_port.to_s,
      "RAILS_ENV" => "test"
    }
    command = %w[bundle exec puma -C config/puma_litestream.rb config.ru]

    Process.spawn(env, *command, chdir: @dummy_root.to_s, out: @puma_log.to_s, err: [:child, :out])
  end

  def stop_puma
    Process.kill(:TERM, @puma_pid)
    wait_for(BOOT_TIMEOUT, "Puma to exit") { Process.waitpid(@puma_pid, Process::WNOHANG) }
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  # `ps` rather than the plugin's own bookkeeping: the defect in #14 was in the
  # process table, not in what the plugin believed it had started.
  def replication_pids
    `ps -ax -o pid=,command=`.lines.filter_map { |line|
      pid, command = line.strip.split(" ", 2)
      pid.to_i if command.to_s.include?(SENTINEL) && command.include?("--disable-gems")
    }
  end

  def available_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def kill_and_reap(pid)
    Process.kill(:KILL, pid)
    Process.waitpid(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def wait_for(timeout, description)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      result = yield
      return result if result
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        flunk "Timed out after #{timeout}s waiting for #{description}. " \
              "Litestream pids: #{replication_pids.inspect}. Puma log:\n#{read_puma_log}"
      end
      sleep 0.1
    end
  end

  def read_puma_log
    File.exist?(@puma_log) ? File.read(@puma_log) : "(no puma log)"
  end
end

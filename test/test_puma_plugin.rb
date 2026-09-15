# frozen_string_literal: true

require "test_helper"
require "puma/plugin"
require "puma/plugin/litestream"

class TestPumaPlugin < ActiveSupport::TestCase
  class FakeEvents
    attr_reader :booted, :stopped, :restarted

    def on_booted(&block)
      @booted = block
    end

    def on_stopped(&block)
      @stopped = block
    end

    def on_restart(&block)
      @restarted = block
    end
  end

  class FakeLogWriter
    attr_reader :messages

    def initialize
      @messages = []
    end

    def log(message)
      @messages << message
    end
  end

  class FakeLauncher
    attr_reader :events, :log_writer

    def initialize
      @events = FakeEvents.new
      @log_writer = FakeLogWriter.new
    end
  end

  def setup
    @launcher = FakeLauncher.new
    @plugin = Puma::Plugins.find("litestream").new
    # Capture the background block instead of handing it to the real Puma
    # registry, which would leak it into every later `fire_background`.
    @background_blocks = []
    captured = @background_blocks
    @plugin.define_singleton_method(:in_background) { |&block| captured << block }
  end

  # The monitor loop sleeps between passes; tests drive it one pass at a time.
  def skip_monitor_sleep
    @plugin.define_singleton_method(:sleep) { |_seconds| nil }
  end

  def boot(pid)
    Litestream::Commands.stub :replicate, pid do
      @launcher.events.booted.call
    end
  end

  class TestPidTracking < TestPumaPlugin
    def test_records_the_pid_returned_by_replicate
      @plugin.start(@launcher)
      boot(4242)

      assert_equal 4242, @plugin.litestream_pid
    end

    def test_starts_replication_asynchronously
      @plugin.start(@launcher)
      replicate = Minitest::Mock.new
      replicate.expect(:call, 4242, [], async: true)

      Litestream::Commands.stub :replicate, replicate do
        @launcher.events.booted.call
      end

      assert_mock replicate
    end
  end

  class TestStopLitestream < TestPumaPlugin
    def test_checks_liveness_then_signals_then_reaps
      @plugin.start(@launcher)
      boot(4242)
      calls = []

      Process.stub :kill, ->(signal, pid) { calls << [:kill, signal, pid] } do
        Process.stub :waitpid, ->(pid, flags) { calls << [:waitpid, pid, flags] } do
          @launcher.events.stopped.call
        end
      end

      assert_equal [[:kill, 0, 4242], [:kill, :INT, 4242], [:waitpid, 4242, 0]], calls
    end

    def test_logs_that_it_is_stopping_litestream
      @plugin.start(@launcher)
      boot(4242)

      Process.stub :kill, nil do
        Process.stub :waitpid, nil do
          @launcher.events.stopped.call
        end
      end

      assert_includes @launcher.log_writer.messages, "Stopping Litestream..."
    end

    def test_does_not_signal_a_process_that_is_already_gone
      @plugin.start(@launcher)
      boot(4242)
      signals = []

      Process.stub :kill, ->(signal, _pid) {
        signals << signal
        raise Errno::ESRCH if signal == 0
      } do
        @launcher.events.stopped.call
      end

      assert_equal [0], signals
    end

    def test_survives_the_child_being_reaped_by_puma_first
      @plugin.start(@launcher)
      boot(4242)

      Process.stub :kill, nil do
        Process.stub :waitpid, ->(_pid, _flags) { raise Errno::ECHILD } do
          @launcher.events.stopped.call
        end
      end

      assert_includes @launcher.log_writer.messages, "Stopping Litestream..."
    end

    def test_does_nothing_when_replication_never_started
      @plugin.start(@launcher)
      signals = []

      Process.stub :kill, ->(signal, _pid) { signals << signal } do
        @launcher.events.stopped.call
      end

      assert_empty signals
    end

    def test_restart_stops_litestream_too
      @plugin.start(@launcher)
      boot(4242)
      signals = []

      Process.stub :kill, ->(signal, _pid) { signals << signal } do
        Process.stub :waitpid, nil do
          @launcher.events.restarted.call
        end
      end

      assert_equal [0, :INT], signals
    end
  end

  class TestMonitorRegistration < TestPumaPlugin
    # Puma runs `Plugins.fire_background` before it fires the booted event, so a
    # block registered from inside `on_booted` is never run.
    def test_registers_the_monitor_during_start_not_on_boot
      @plugin.start(@launcher)

      assert_equal 1, @background_blocks.size
    end
  end

  class TestLitestreamGone < TestPumaPlugin
    def test_is_false_before_replication_starts
      @plugin.start(@launcher)

      refute @plugin.send(:litestream_gone?)
    end

    def test_is_false_while_the_process_runs
      @plugin.start(@launcher)
      boot(4242)

      Process.stub :waitpid, nil do
        Process.stub :kill, 1 do
          refute @plugin.send(:litestream_gone?)
        end
      end
    end

    # An exited-but-unreaped child still answers `kill(0)`, so the reap has to
    # happen before the liveness check.
    def test_reaps_a_zombie_before_reporting_it_alive
      @plugin.start(@launcher)
      boot(4242)
      reaped = false

      Process.stub :waitpid, ->(_pid, _flags) { reaped = true } do
        Process.stub :kill, ->(_signal, _pid) { raise Errno::ESRCH if reaped } do
          assert @plugin.send(:litestream_gone?)
        end
      end
    end

    def test_treats_a_process_owned_by_another_user_as_alive
      @plugin.start(@launcher)
      boot(4242)

      Process.stub :waitpid, nil do
        Process.stub :kill, ->(_signal, _pid) { raise Errno::EPERM } do
          refute @plugin.send(:litestream_gone?)
        end
      end
    end
  end

  class TestMonitorLoop < TestPumaPlugin
    def test_signals_puma_when_litestream_goes_away
      @plugin.start(@launcher)
      boot(4242)
      skip_monitor_sleep
      signalled = []

      @plugin.stub :litestream_gone?, true do
        Process.stub :kill, ->(signal, pid) { signalled << [signal, pid] } do
          @plugin.send(:monitor_litestream)
        end
      end

      assert_equal [[:INT, $$]], signalled
      assert_includes @launcher.log_writer.messages, "Detected Litestream has gone away, stopping Puma..."
    end

    def test_does_not_signal_puma_after_a_deliberate_stop
      @plugin.start(@launcher)
      boot(4242)
      skip_monitor_sleep
      signalled = []

      Process.stub :kill, nil do
        Process.stub :waitpid, nil do
          @launcher.events.stopped.call
        end
      end

      @plugin.stub :litestream_gone?, true do
        Process.stub :kill, ->(signal, pid) { signalled << [signal, pid] } do
          @plugin.send(:monitor_litestream)
        end
      end

      assert_empty signalled
    end
  end
end

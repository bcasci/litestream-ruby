require "puma/plugin"

# Copied from https://github.com/rails/solid_queue/blob/15408647f1780033dad223d3198761ea2e1e983e/lib/puma/plugin/solid_queue.rb
Puma::Plugin.create do
  attr_reader :litestream_pid, :log_writer

  def start(launcher)
    @log_writer = launcher.log_writer
    @stopping = false

    # Registered here rather than inside `on_booted`: Puma runs
    # `Puma::Plugins.fire_background` before it fires the booted event, and
    # `in_background` only appends to the array that `fire_background` has
    # already iterated. A block registered from inside `on_booted` never runs.
    in_background do
      monitor_litestream
    end

    register_event(launcher.events, :after_booted, :on_booted) do
      @stopping = false
      @litestream_pid = Litestream::Commands.replicate(async: true)
    end

    register_event(launcher.events, :after_stopped, :on_stopped) { stop_litestream }
    register_event(launcher.events, :before_restart, :on_restart) { stop_litestream }
  end

  private

  # Puma 7 renamed the lifecycle events and kept the old names as deprecated
  # aliases that warn on every boot. Puma 6, which this gem still supports, has
  # only the old names, so ask the events object rather than checking a version.
  def register_event(events, name, legacy_name, &block)
    name = legacy_name unless events.respond_to?(name)
    events.public_send(name, &block)
  end

  # Signals the Litestream process and then reaps it. The liveness check and the
  # signal come before the reap: reaping first leaves a pid that the kernel may
  # already have recycled, and signalling that pid would hit another process.
  def stop_litestream
    @stopping = true
    return unless litestream_running?

    log "Stopping Litestream..."
    Process.kill(:INT, litestream_pid)
    reap_litestream(0)
  rescue Errno::ESRCH, Errno::ECHILD
    # The process exited between the liveness check and the signal, or Puma's
    # master reaped it first. Either way there is nothing left to stop.
  end

  def monitor_litestream
    loop do
      sleep 2
      break if @stopping
      next unless litestream_gone?

      log "Detected Litestream has gone away, stopping Puma..."
      Process.kill(:INT, $$)
      break
    end
  end

  def litestream_gone?
    # `on_booted` has not run yet, so there is no process to monitor.
    return false if litestream_pid.nil?

    # Reap first: an exited-but-unreaped child still answers `kill(0)`.
    reap_litestream
    !litestream_running?
  end

  # `Process.kill(0, pid)` rather than `waitpid`, because Puma's master reaps any
  # child it finds (`Puma::Cluster#wait_workers`), not only its own workers, so
  # `waitpid` can raise `Errno::ECHILD` for a process that is still running.
  def litestream_running?
    return false if litestream_pid.nil?

    Process.kill(0, litestream_pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def reap_litestream(flags = Process::WNOHANG)
    Process.waitpid(litestream_pid, flags)
  rescue Errno::ECHILD, Errno::ESRCH
    nil
  end

  def log(...)
    log_writer.log(...)
  end
end

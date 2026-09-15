# Puma configuration used only by test/integration/test_puma_plugin_restart.rb.
# It boots the real Litestream Puma plugin against a stub executable so a
# SIGUSR2 restart can be observed end to end.

threads 1, 1

port ENV.fetch("PORT") { 3000 }

environment ENV.fetch("RAILS_ENV") { "test" }

pidfile ENV.fetch("PIDFILE") { "tmp/pids/puma_litestream.pid" }

plugin :litestream

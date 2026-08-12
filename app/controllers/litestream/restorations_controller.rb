# frozen_string_literal: true

module Litestream
  class RestorationsController < ApplicationController
    # POST /restorations
    def create
      database = params[:database].remove("[ROOT]/")
      dir, file = File.split(database)
      ext = File.extname(file)
      base = File.basename(file, ext)
      now = Time.now.utc.strftime("%Y%m%d%H%M%S")
      backup = File.join(dir, "#{base}-#{now}#{ext}")

      Litestream::Commands.restore(database, **{"-o" => backup})

      redirect_to root_path, notice: "Restored to <code>#{backup}</code>."
    rescue Litestream::Commands::DatabaseRequiredException,
      Litestream::Commands::CommandFailedException,
      Litestream::Commands::ExecutableNotFoundException,
      Litestream::Commands::UnsupportedPlatformException,
      SystemCallError => e
      redirect_to root_path, alert: "Restore failed: #{e.message} — verify the database path and your Litestream configuration, then retry."
    end
  end
end

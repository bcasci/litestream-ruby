# frozen_string_literal: true

require "test_helper"

class Litestream::TestRestorationsController < ActionDispatch::IntegrationTest
  test "create redirects with a remediation alert when restore fails with CommandFailedException" do
    error = Litestream::Commands::CommandFailedException.new("Failed to execute `litestream restore`; Reason: no such database")

    Litestream::Commands.stub :restore, ->(*) { raise error } do
      post litestream.restorations_url, params: {database: "[ROOT]/storage/test.sqlite3"}
    end

    assert_redirected_to litestream.root_path
    assert_match "Failed to execute", flash[:alert]
    assert_match "verify the database path and your Litestream configuration, then retry", flash[:alert]
  end

  test "create redirects with a remediation alert when restore fails with DatabaseRequiredException" do
    error = Litestream::Commands::DatabaseRequiredException.new("database argument is required")

    Litestream::Commands.stub :restore, ->(*) { raise error } do
      post litestream.restorations_url, params: {database: "[ROOT]/storage/test.sqlite3"}
    end

    assert_redirected_to litestream.root_path
    assert_match "database argument is required", flash[:alert]
    assert_match "verify the database path and your Litestream configuration, then retry", flash[:alert]
  end

  test "create redirects instead of 500 when restore raises a SystemCallError (missing binary)" do
    Litestream::Commands.stub :restore, ->(*) { raise Errno::ENOENT, "litestream" } do
      post litestream.restorations_url, params: {database: "[ROOT]/storage/test.sqlite3"}
    end

    assert_redirected_to litestream.root_path
    assert_match "verify the database path and your Litestream configuration, then retry", flash[:alert]
  end

  # End-to-end: a real restore that exits non-zero flows restore -> execute -> run,
  # raises CommandFailedException, and the controller surfaces an alert (not a success notice).
  test "create surfaces an alert (not a success notice) when the restore process exits non-zero" do
    failed = Object.new
    failed.define_singleton_method(:success?) { false }
    capture3 = proc { |*cmd| ["", "restore failed: no such replica", failed] }

    Litestream::Commands.stub :executable, "exe/test/litestream" do
      Open3.stub :capture3, capture3 do
        post litestream.restorations_url, params: {database: "[ROOT]/storage/test.sqlite3"}
      end
    end

    assert_redirected_to litestream.root_path
    assert_nil flash[:notice]
    assert_match "restore failed: no such replica", flash[:alert]
    assert_match "verify the database path and your Litestream configuration, then retry", flash[:alert]
  end
end

# frozen_string_literal: true

require "pg"
require "securerandom"

host = ENV.fetch("TEST_POSTGRES_HOST")
user = ENV.fetch("TEST_POSTGRES_USER")
password = ENV.fetch("TEST_POSTGRES_PASSWORD")
port = ENV.fetch("TEST_POSTGRES_PORT", "5432")

# PostgreSQL identifiers are at most 63 bytes. Each invocation owns a new name.
database = "sure_oh_#{SecureRandom.hex(16)}"
raise "Unsafe database name" unless database.match?(/\Asure_oh_[0-9a-f]{32}\z/) && database.bytesize <= 63

admin = PG.connect(host: host, port: port, user: user, password: password, dbname: "postgres")
created = false
begin
  admin.exec("CREATE DATABASE #{database}")
  created = true
  admin.exec("REVOKE CONNECT ON DATABASE #{database} FROM PUBLIC")
  PG.connect(host: host, port: port, user: user, password: password, dbname: database) do |connection|
    connection.exec("SELECT 1")
  end

  ENV.update(
    "DB_HOST" => host,
    "DB_PORT" => port,
    "POSTGRES_USER" => user,
    "POSTGRES_PASSWORD" => password,
    "POSTGRES_DB" => database,
    "RAILS_ENV" => "test",
    "DISABLE_PARALLELIZATION" => "true"
  )
  ENV.delete("DATABASE_URL")

  puts "Using isolated test database #{database}"
  raise "Schema load failed" unless system("bin/rails", "db:schema:load")
  raise "Test command failed" unless system(*ARGV)
ensure
  if created
    admin.exec("DROP DATABASE #{database}")
    puts "Dropped isolated test database #{database}"
  end
  admin.finish
end

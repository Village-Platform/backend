# db:prepare for containers that start at the same time (several pods can boot at once).
#
# On an empty database, db:prepare loads db/schema.rb. That step is not protected by
# the migration lock, so two containers loading the schema together fail with
# PG::DuplicateObject. This task takes a PostgreSQL advisory lock on its own connection
# first: the first container prepares the database, the others wait and then find it ready.
namespace :db do
  desc "Run db:prepare while holding a PostgreSQL advisory lock"
  task :prepare_locked do
    require "pg"

    lock_id = 4_207_202_610 # any constant shared by all containers of this app
    lock = PG.connect(ENV.fetch("DATABASE_URL"))
    begin
      lock.exec("SELECT pg_advisory_lock(#{lock_id})")
      Rake::Task["db:prepare"].invoke
    ensure
      lock.exec("SELECT pg_advisory_unlock(#{lock_id})") rescue nil
      lock.close
    end
  end
end

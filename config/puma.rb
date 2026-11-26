threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)

plugin :tmp_restart

# Runs the Solid Queue supervisor (dispatcher + workers) beside Puma: no separate worker pod yet.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Exit cleanly (code 0) on SIGTERM, e.g. when Kubernetes stops the pod.
raise_exception_on_sigterm false

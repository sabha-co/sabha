# frozen_string_literal: true

# Yabeda metrics are NON-PRODUCTION only. The gems load in the :performance and
# :development bundler groups, and the Prometheus /metrics endpoint is mounted
# only in those envs (config/routes.rb) — production loads and exposes nothing.
#
# Plugin groups self-register via their Railties; the resulting Prometheus
# series (name = "<group>_<metric>") that Loadscope's rails tap scrapes:
#   yabeda-activerecord -> activerecord_connection_pool_{size,connections,busy,waiting}
#   yabeda-gvl_metrics  -> rack_gvl_metrics_gvl_wait  (gauge, nanoseconds)
#   yabeda-puma-plugin  -> puma_{busy_threads,max_threads,requests_count}
#                          (activated via `plugin :yabeda` in config/puma.rb)
return if Rails.env.production?

# In multi-worker Puma (only when WEB_CONCURRENCY is set for a multi-core load
# test) per-worker gauges must aggregate through a shared store, or /metrics
# reports a single worker's view. Single-process performance runs need nothing.
if ENV["WEB_CONCURRENCY"].to_i > 1
  require "prometheus/client"
  dir = Rails.root.join("tmp/prometheus")
  FileUtils.mkdir_p(dir)
  Prometheus::Client.config.data_store =
    Prometheus::Client::DataStores::DirectFileStore.new(dir: dir.to_s)
end

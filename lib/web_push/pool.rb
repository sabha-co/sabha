# This is in lib so we can use it in a thread pool without the Rails executor
class WebPush::Pool
  attr_reader :delivery_pool, :invalidation_pool, :connection, :invalid_subscription_handler

  def initialize(invalid_subscription_handler:)
    @delivery_pool = Concurrent::ThreadPoolExecutor.new(max_threads: 50, queue_size: 10000)
    @invalidation_pool = Concurrent::FixedThreadPool.new(1)
    @connection = Net::HTTP::Persistent.new(name: "web_push", pool_size: 150)
    @invalid_subscription_handler = invalid_subscription_handler
  end

  # Build every notification before posting any of them. Building one hits the
  # DB for the badge count and resolves the endpoint's DNS, either of which can
  # raise — and a posted delivery can't be recalled, so raising partway through
  # would re-send the earlier ones when the job retries. Posting itself can't
  # raise, so once the first delivery is out the rest follow.
  def queue(payload, subscriptions)
    tenant = current_tenant
    deliveries = subscriptions.map { |subscription| [ subscription.notification(**payload), subscription.id ] }

    deliveries.each { |notification, subscription_id| deliver_later(notification, subscription_id, tenant) }
  end

  def shutdown
    connection.shutdown
    shutdown_pool(delivery_pool)
    shutdown_pool(invalidation_pool)
  end

  private
    def deliver_later(notification, subscription_id, tenant)
      delivery_pool.post do
        deliver(notification, subscription_id, tenant)
      rescue Exception => e
        Rails.logger.error "Error in WebPush::Pool.deliver: #{e.class} #{e.message}"
      end
    rescue Concurrent::RejectedExecutionError
    end

    def deliver(notification, id, tenant)
      notification.deliver(connection: connection)
    rescue WebPush::ExpiredSubscription, OpenSSL::OpenSSLError => ex
      invalidate_subscription_later(id, tenant) if invalid_subscription_handler
    end

    def invalidate_subscription_later(id, tenant)
      invalidation_pool.post do
        with_tenant(tenant) do
          invalid_subscription_handler.call(id)
        end
      rescue Exception => e
        Rails.logger.error "Error in WebPush::Pool.invalid_subscription_handler: #{e.class} #{e.message}"
      end
    end

    def shutdown_pool(pool)
      pool.shutdown
      pool.kill unless pool.wait_for_termination(1)
    end

    # Get current tenant (if SaaS mode with activerecord-tenanted)
    def current_tenant
      if defined?(ApplicationRecord) && ApplicationRecord.respond_to?(:current_tenant)
        ApplicationRecord.current_tenant
      end
    end

    # Execute block with tenant context restored
    def with_tenant(tenant, &block)
      if tenant.present? && defined?(ApplicationRecord) && ApplicationRecord.respond_to?(:with_tenant)
        ApplicationRecord.with_tenant(tenant, &block)
      else
        yield
      end
    end
end

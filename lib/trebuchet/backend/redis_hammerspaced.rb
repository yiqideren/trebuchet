require 'trebuchet/backend/redis'
require 'json'

class Trebuchet::Backend::RedisHammerspaced < Trebuchet::Backend::Redis

  # This class will rely on a cron job to sync all trebuchet features
  # to local hammerspace thus this class never directly updates hammerspace
  # We also cache in memory the features as we do in redis_cached

  attr_accessor :namespace

  def initialize(*args)
    @namespace = 'trebuchet/'
    begin
      # args must be a hash
      @options = args.first
      @redis = @options[:client]
      @hammerspace = @options[:hammerspace]
      unless @options[:skip_check]
        # raise error if not connectedUncaught ReferenceError: google is not defined
        @redis.exists(feature_names_key) # @redis.info is slow and @redis.client.connected? is NOT reliable
        @hammerspace.has_key?(feature_names_key)
      end
    rescue Exception => e
      raise Trebuchet::BackendInitializationError, e.message
    end
  end

  def get_strategy(feature_name)
    if cached_strategies.has_key?(feature_name)
      # use cached if available (even if value is nil)
      cached_strategies[feature_name]
    else
      # call to hammerspace
      cache_strategy feature_name, get_strategy_hammerspace(feature_name)
    end
  end

  def get_strategy_hammerspace(feature_name)
    # Read from hammerspace
    return nil unless @hammerspace.has_key?(feature_key(feature_name))
    # h will be a string, we need to convert it back to Hash
    h = @hammerspace[feature_key(feature_name)]
    begin
      h = JSON.load(h)
    rescue
      return nil
    end
    unpack_strategy(h)
  end

  def unpack_strategy(options)
    # We don't need to further convert values
    # because it's already taken care of
    # by the refresh cron job
    return nil unless options.is_a?(Hash)
    [].tap do |a|
      options.each do |k, v|
        key = k.to_sym
        a << key
        a << v
      end
    end
  end

  def get_feature_names
    # Read from hammerspace
    return [] unless @hammerspace.has_key?(feature_names_key)
    JSON.load(@hammerspace[feature_names_key])
  end

  def append_strategy(feature_name, strategy, options = nil)
    # though we can't clear the strategy for all active instances
    # this will clear the cache in the console environment to show current settings
    self.clear_cached_strategies
    super(feature_name, strategy, options)
  end

  def cache_strategy(feature_name, strategy)
    cached_strategies[feature_name] = strategy
    return strategy
  end

  def cached_strategies
    @cached_strategies ||= Hash.new
  end

  def cache_cleared_at
    @cache_cleared_at ||= Time.now
  end

  def clear_cached_strategies
    @cache_cleared_at = Time.now
    @cached_strategies = nil
  end


end

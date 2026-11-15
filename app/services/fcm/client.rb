require "fcm"

module Fcm
  # The adapter between the app and Google: callers see these methods and the Fcm::* errors only.
  # Every request goes through the fcm gem; this class only turns its results into errors.
  #
  # The gem never raises for a failed request, it returns { status_code:, body:, headers: }, and it
  # returns nil, without sending, when it dislikes a topic name or condition.
  #
  # Topic membership uses the gem's batch_topic_subscription, i.e. the legacy Instance ID API,
  # which Google removes on 2027-09-29 ("Manage topics" in the FCM docs). Before then, move
  # subscribe/unsubscribe to the topicSubscriptions REST API or a gem version that uses it.
  #
  # FCM_SERVICE_ACCOUNT_JSON holds the service-account key itself, as one line of JSON, injected from
  # the environment (a k8s secret in production, .env locally). The app never reads a key file.
  # Without it (development without Firebase, CI) every call is a logged no-op.
  class Client
    MAX_CONDITION_TOPICS = 5
    MAX_BATCH_TOKENS = 1000 # Instance ID batchAdd / batchRemove limit

    def initialize(credentials_json: ENV["FCM_SERVICE_ACCOUNT_JSON"].presence, sender: nil)
      @credentials_json = load_credentials(credentials_json)
      @project_id = JSON.parse(@credentials_json).fetch("project_id") if @credentials_json
      @sender = sender
    end

    def enabled?
      @credentials_json.present?
    end

    # The send_to_* methods take a payload from Fcm::Message.payload and return FCM's message name
    # ("projects/p/messages/123"), or "disabled". Failures raise Fcm::* errors.

    def send_to_token(token, payload)
      send_message { sender.send_v1({ token: }.merge(payload)) }
    end

    # HTTP v1 has no multicast (the legacy registration_ids and the batch endpoint are gone), so
    # this is one request per token. It never raises for one token: a retry of the whole list
    # would re-send to the tokens that already got it. Only AuthError stops it, since no other
    # token would get through either.
    def send_to_tokens(tokens, payload)
      tokens.uniq.each_with_object(TokensResult.empty) do |token, result|
        result.sent[token] = send_to_token(token, payload)
      rescue AuthError
        raise
      rescue Unregistered
        result.unregistered << token
      rescue Error => e
        result.failed[token] = e
      end
    end

    def send_to_topic(topic, payload)
      send_message { sender.send_to_topic(topic, payload) }
    end

    # One topic is addressed directly; 2 to 5 become a condition (:or reaches anyone in any of them,
    # :and only those in all of them).
    def send_to_topics(topics, payload, operator: :or)
      topics = topics.uniq
      unless topics.size.between?(1, MAX_CONDITION_TOPICS)
        raise ArgumentError, "FCM sends to 1 to #{MAX_CONDITION_TOPICS} topics at once, got #{topics.size}"
      end
      return send_to_topic(topics.first, payload) if topics.one?

      send_to_condition(Message.condition_for(topics, operator:), payload)
    end

    # Any condition FCM accepts, e.g. "'news' in topics && !('owners' in topics)".
    def send_to_condition(condition, payload)
      send_message { sender.send_to_topic_condition(condition, payload) }
    end

    # Both return the tokens FCM reported NOT_FOUND (no longer registered); the caller deletes those
    # devices. Any other per-token error is logged and the token kept, so a mistake on our side
    # cannot wipe the devices table.
    def subscribe(topic_key, tokens)
      manage_topic(tokens) { |batch| sender.batch_topic_subscription(topic_key, batch) }
    end

    def unsubscribe(topic_key, tokens)
      manage_topic(tokens) { |batch| sender.batch_topic_unsubscription(topic_key, batch) }
    end

    private

    def send_message
      return disabled("send") unless enabled?

      JSON.parse(checked { yield }[:body]).fetch("name")
    end

    # The batch answers 200 with one result per token, in order: {} or { "error" => "NOT_FOUND" }.
    def manage_topic(tokens)
      unless enabled?
        disabled("topics")
        return []
      end

      tokens.each_slice(MAX_BATCH_TOKENS).flat_map do |batch|
        results = JSON.parse(checked { yield batch }[:body].presence || "{}").fetch("results", [])
        batch.zip(results).filter_map do |token, result|
          error = result&.dig("error")
          next token if error == "NOT_FOUND"

          Rails.logger.warn("[Fcm] topic call refused, token kept: #{error}") if error
          nil
        end
      end
    end

    # Runs a gem call and raises the matching Fcm::* error unless it succeeded.
    def checked
      result = translate_errors { yield }
      raise InvalidArgument, "FCM message rejected by the fcm gem before sending" if result.nil?

      code = result[:status_code].to_i
      raise error_for(code, result[:body].to_s, header(result[:headers], "Retry-After")) unless code.between?(200, 299)

      result
    end

    # Fails at boot-time use with an actionable message rather than with an obscure OAuth error on
    # the first push. The usual mistakes: a file path instead of the JSON, or the Android
    # google-services.json, which cannot send.
    def load_credentials(value)
      return if value.blank?

      json = value.strip
      unless json.start_with?("{")
        raise ArgumentError, "FCM_SERVICE_ACCOUNT_JSON must hold the service-account JSON itself, on one line, " \
                             "not a file path. Build it with: jq -c . fcm_service_account.json"
      end

      parsed = JSON.parse(json)
      return json if parsed["type"] == "service_account" && parsed["private_key"].present?

      kind = parsed.key?("project_info") ? "the Android google-services.json" : "not a service-account key"
      raise ArgumentError, "FCM_SERVICE_ACCOUNT_JSON is #{kind}, which cannot send. Use a service-account " \
                           "private key: Firebase console > Project settings > Service accounts > Generate new private key."
    end

    def error_for(code, body, retry_after_header)
      error_code = parse_error_code(body)
      message = "FCM #{code} #{error_code}".strip
      case code
      when 401, 403 then AuthError.new(message)
      when 404 then error_code == "UNREGISTERED" ? Unregistered.new(message) : Error.new(message)
      when 400 then InvalidArgument.new(message)
      when 429, 500..599
        retry_after = retry_after_header&.then { |value| Integer(value, exception: false) }
        Retryable.new(message, retry_after:)
      else Error.new(message)
      end
    end

    NETWORK_ERRORS = [ Faraday::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, IOError,
                       Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError ].freeze

    # Everything that can go wrong on the wire becomes an Fcm::* error, so jobs only handle those.
    # The gem fetches its access token through Signet, which raises AuthorizationError for a revoked
    # or wrong key (invalid_grant).
    def translate_errors
      yield
    rescue *NETWORK_ERRORS, Signet::RemoteServerError, Signet::UnexpectedStatusError => e
      raise Retryable, "#{e.class}: #{e.message}"
    rescue Signet::AuthorizationError => e
      raise AuthError, "#{e.class}: #{e.message}"
    end

    # HTTP v1 puts the FCM-specific code in error.details[] (type FcmError); the Instance ID API
    # answers { "error": "<CODE>" }.
    def parse_error_code(body)
      error = JSON.parse(body.to_s)["error"]
      return error if error.is_a?(String)

      (error&.dig("details") || []).filter_map { |detail| detail["errorCode"] }.first
    rescue JSON::ParserError
      nil
    end

    # Built lazily. Kept-alive connections are per thread (Net::HTTP is not thread-safe), so each
    # Puma or Solid Queue thread reuses its own TLS connection to FCM.
    def sender
      @sender ||= FCM.new(StringIO.new(@credentials_json), @project_id,
                          timeout: 10, open_timeout: 5, keep_alive_connections: true)
    end

    # Faraday's headers are case-insensitive; a plain Hash (specs) is not.
    def header(headers, name)
      return if headers.nil?

      headers[name] || headers.find { |key, _| key.to_s.casecmp?(name) }&.last
    end

    def disabled(action)
      Rails.logger.info("[Fcm] #{action} skipped: FCM_SERVICE_ACCOUNT_JSON is not set")
      "disabled"
    end
  end
end

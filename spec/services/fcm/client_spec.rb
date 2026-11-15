require "rails_helper"

RSpec.describe Fcm::Client do
  # Stands in for the fcm gem's FCM instance: every call returns { status_code:, body:, headers: }.
  # sent records [ gem method, *arguments ].
  let(:sent) { [] }
  let(:send_results) { [] }
  let(:sender) do
    double("FCM").tap do |fcm|
      %i[ send_v1 send_to_topic send_to_topic_condition batch_topic_subscription batch_topic_unsubscription ].each do |name|
        allow(fcm).to receive(name) do |*args|
          sent << [ name, *args ]
          send_results.shift || { status_code: 200, body: '{"name":"projects/p/messages/1"}', headers: {} }
        end
      end
    end
  end
  let(:key_json) { { type: "service_account", project_id: "p", private_key: "-----BEGIN PRIVATE KEY-----\nx\n" }.to_json }
  let(:client) do
    described_class.new(credentials_json: key_json, sender:)
  end

  def send_returns(code, body = "{}", headers = {})
    send_results << { status_code: code, body:, headers: }
  end
  let(:payload) { Fcm::Message.payload(title: "T", body: "B", data: {}) }

  def fcm_error(status, error_code)
    { error: { status:, details: [ { "@type" => "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: error_code } ] } }.to_json
  end

  describe "#send_to_token" do
    it "sends through the fcm gem and returns the message name" do
      expect(client.send_to_token("t", payload)).to eq("projects/p/messages/1")
      expect(sent).to eq([ [ :send_v1, { token: "t", **payload } ] ])
    end

    it "raises Unregistered on 404 UNREGISTERED" do
      send_returns(404, fcm_error("NOT_FOUND", "UNREGISTERED"))
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::Unregistered)
    end

    it "raises InvalidArgument on 400" do
      send_returns(400, fcm_error("INVALID_ARGUMENT", "INVALID_ARGUMENT"))
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::InvalidArgument)
    end

    it "raises Retryable with retry_after on 429" do
      send_returns(429, fcm_error("RESOURCE_EXHAUSTED", "QUOTA_EXCEEDED"), "retry-after" => "30")
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::Retryable) { |e| expect(e.retry_after).to eq(30) }
    end

    it "raises Retryable on 503 without Retry-After" do
      send_returns(503)
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::Retryable) { |e| expect(e.retry_after).to be_nil }
    end

    it "raises AuthError on 401 and 403" do
      send_returns(401)
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::AuthError)
      send_returns(403, fcm_error("PERMISSION_DENIED", "SENDER_ID_MISMATCH"))
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::AuthError)
    end

    it "raises a plain Error, not Unregistered, on a 404 without UNREGISTERED" do
      send_returns(404, "{}")
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::Error) { |e| expect(e).not_to be_a(Fcm::Unregistered) }
    end

    it "maps the gem's network and token failures" do
      allow(sender).to receive(:send_v1).and_raise(Faraday::TimeoutError)
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::Retryable)

      allow(sender).to receive(:send_v1).and_raise(Signet::AuthorizationError.new("invalid_grant"))
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::AuthError)
    end

    it "raises InvalidArgument when the gem silently sends nothing" do
      allow(sender).to receive(:send_v1).and_return(nil)
      expect { client.send_to_token("t", payload) }.to raise_error(Fcm::InvalidArgument)
    end

    it "is a no-op when no credentials are set" do
      disabled = described_class.new(credentials_json: nil, sender:)
      expect(disabled).not_to be_enabled
      expect(disabled.send_to_token("t", payload)).to eq("disabled")
      expect(sent).to be_empty
    end

    it "builds the gem client from the credentials JSON" do
      real = described_class.new(credentials_json: key_json)
      expect(real.send(:sender)).to be_an_instance_of(FCM)
    end
  end

  describe "#send_to_tokens" do
    it "sends once per distinct token and reports each outcome" do
      send_returns(200, '{"name":"projects/p/messages/1"}')
      send_returns(404, fcm_error("NOT_FOUND", "UNREGISTERED"))
      send_returns(429, fcm_error("RESOURCE_EXHAUSTED", "QUOTA_EXCEEDED"))
      send_returns(400, fcm_error("INVALID_ARGUMENT", "INVALID_ARGUMENT"))

      result = client.send_to_tokens(%w[ a b c d a ], payload)

      expect(sent.map { |_, message| message[:token] }).to eq(%w[ a b c d ])
      expect(result.sent).to eq("a" => "projects/p/messages/1")
      expect(result.unregistered).to eq(%w[ b ])
      expect(result.failed.transform_values(&:class)).to eq("c" => Fcm::Retryable, "d" => Fcm::InvalidArgument)
    end

    it "stops on AuthError, which no other token would get past" do
      send_returns(401)
      expect { client.send_to_tokens(%w[ a b ], payload) }.to raise_error(Fcm::AuthError)
      expect(sent.size).to eq(1)
    end
  end

  describe "topics and conditions" do
    it "sends to one topic with the gem's topic method" do
      expect(client.send_to_topic("news", payload)).to eq("projects/p/messages/1")
      expect(sent).to eq([ [ :send_to_topic, "news", payload ] ])
    end

    it "sends to one topic directly and to several as a condition" do
      client.send_to_topics(%w[ all all ], payload)
      client.send_to_topics(%w[ news owners ], payload)
      client.send_to_topics(%w[ news owners ], payload, operator: :and)

      expect(sent).to eq([
        [ :send_to_topic, "all", payload ],
        [ :send_to_topic_condition, "'news' in topics || 'owners' in topics", payload ],
        [ :send_to_topic_condition, "'news' in topics && 'owners' in topics", payload ]
      ])
    end

    it "refuses no topics or more than FCM allows in one condition" do
      expect { client.send_to_topics([], payload) }.to raise_error(ArgumentError)
      expect { client.send_to_topics(%w[ a b c d e f ], payload) }.to raise_error(ArgumentError, /1 to 5/)
      expect(sent).to be_empty
    end

    it "sends a hand-written condition" do
      client.send_to_condition("'news' in topics && !('owners' in topics)", payload)
      expect(sent).to eq([ [ :send_to_topic_condition, "'news' in topics && !('owners' in topics)", payload ] ])
    end

    it "raises InvalidArgument when the gem refuses a topic name without sending" do
      allow(sender).to receive(:send_to_topic).and_return(nil)
      expect { client.send_to_topic("bad name!", payload) }.to raise_error(Fcm::InvalidArgument)
    end

    it "lets the real gem validate topic names before any request" do
      real = described_class.new(credentials_json: key_json)
      expect { real.send_to_topic("bad name!", payload) }.to raise_error(Fcm::InvalidArgument)
      expect { real.send_to_condition("'news' in topics; drop", payload) }.to raise_error(Fcm::InvalidArgument)
    end
  end

  describe "credentials" do
    it "takes the key JSON from the environment value" do
      client = described_class.new(credentials_json: key_json, sender:)
      expect(client).to be_enabled
      expect(client.send_to_token("t", payload)).to eq("projects/p/messages/1")
    end

    it "rejects the Android google-services.json with a clear message" do
      android = { project_info: { project_id: "p" }, client: [] }.to_json
      expect { described_class.new(credentials_json: android) }
        .to raise_error(ArgumentError, /google-services\.json.*service-account/)
    end

    it "rejects a file path: the key must be the JSON itself" do
      expect { described_class.new(credentials_json: "fcm_service_account.json") }
        .to raise_error(ArgumentError, /JSON itself.*not a file path/)
    end
  end

  describe "topics" do
    def batch_returns(*results)
      send_returns(200, { results: }.to_json)
    end

    it "subscribes the tokens in one gem call and returns the ones FCM no longer knows" do
      batch_returns({}, { error: "NOT_FOUND" }, {})

      expect(client.subscribe("news", %w[ a b c ])).to eq(%w[ b ])
      expect(sent).to eq([ [ :batch_topic_subscription, "news", %w[ a b c ] ] ])
    end

    it "unsubscribes through the gem's batch call" do
      batch_returns({}, {})

      expect(client.unsubscribe("news", %w[ a b ])).to eq([])
      expect(sent).to eq([ [ :batch_topic_unsubscription, "news", %w[ a b ] ] ])
    end

    it "keeps a token with any other per-token error" do
      batch_returns({ error: "INVALID_ARGUMENT" }, { error: "INTERNAL" })
      expect(client.subscribe("news", %w[ a b ])).to eq([])
    end

    it "splits more tokens than one batch allows" do
      stub_const("#{described_class}::MAX_BATCH_TOKENS", 2)
      batch_returns({}, { error: "NOT_FOUND" })
      batch_returns({ error: "NOT_FOUND" })

      expect(client.subscribe("news", %w[ a b c ])).to eq(%w[ b c ])
      expect(sent.map(&:last)).to eq([ %w[ a b ], %w[ c ] ])
    end

    it "maps request-level failures like a send" do
      send_returns(503)
      expect { client.subscribe("news", %w[ a ]) }.to raise_error(Fcm::Retryable)

      send_returns(401, { error: "Unauthorized" }.to_json)
      expect { client.subscribe("news", %w[ a ]) }.to raise_error(Fcm::AuthError, /Unauthorized/)

      allow(sender).to receive(:batch_topic_subscription).and_raise(Faraday::ConnectionFailed)
      expect { client.subscribe("news", %w[ a ]) }.to raise_error(Fcm::Retryable)
    end

    it "is a no-op when no credentials are set" do
      disabled = described_class.new(credentials_json: nil, sender:)
      expect(disabled.subscribe("news", %w[ a ])).to eq([])
      expect(sent).to be_empty
    end
  end
end

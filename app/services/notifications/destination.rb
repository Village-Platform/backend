module Notifications
  # Where a tap on a notification leads: a screen from a closed list plus a record id. The apps map
  # "screen" to a route and open the inbox for any screen they do not know, which is what keeps old
  # app versions safe when a screen is added here (add it, then ship an app that handles it).
  class Destination
    SCREENS = %w[ none article firm category subscription ].freeze
    ADMIN_SCREENS = (SCREENS - %w[ subscription ]).freeze # subscription is for system notifications

    attr_reader :screen, :id

    def self.none = new(screen: "none")

    def initialize(screen:, id: nil)
      @screen = screen.to_s
      @id = id.presence
    end

    def valid? = error.nil?

    # Arabic, for the admin forms.
    def error
      return "الشاشة غير معروفة." unless SCREENS.include?(screen)
      return if screen == "none"
      return "يجب تحديد رقم العنصر." if id.nil?

      "العنصر المطلوب غير موجود أو غير منشور." if target.nil?
    end

    # The record a tap opens, if it can still be shown: approved articles that are published or
    # scheduled (a campaign is sent when its article goes live), visible firms.
    def target
      return @target if defined?(@target)

      @target = case screen
      when "article" then Article.approved.where.not(published_at: nil).find_by(id:)
      when "firm" then Firm.visible.find_by(id:)
      when "category" then Category.find_by(id:)
      when "subscription" then Subscription.find_by(id:)
      end
    end

    # Can a tap open it right now? A scheduled article is a valid destination to save, but not yet
    # to send.
    def live?
      valid? && (screen != "article" || target.published?)
    end

    # FCM data values must be strings.
    def to_data
      screen == "none" ? { "screen" => "none" } : { "screen" => screen, "id" => id.to_s }
    end
  end
end

module Articles
  # Keeps an article's push campaign in step with the article: created when it has a notify topic
  # and a publish time, rescheduled when that time moves, canceled when either is cleared or the
  # article leaves review approved. Once the campaign has gone out (or failed), edits never push
  # again.
  class SyncPushCampaign
    BODY_LENGTH = 140

    def self.call(article) = new(article).call

    def initialize(article)
      @article = article
      @campaign = article.push_campaign
    end

    def call
      return @campaign if @campaign && (@campaign.sent? || @campaign.sending? || @campaign.failed?)
      return cancel unless @article.approved? && @article.notify_topic && @article.published_at

      schedule
    end

    private

    def cancel
      @campaign.cancel!("أُلغي الإشعار من صفحة المقال.") if @campaign&.scheduled?
      @campaign
    end

    def schedule
      campaign = @campaign || @article.build_push_campaign
      scheduled_at = [ @article.published_at, Time.current ].max
      # The queued job already targets this time; the topics it reads at send time.
      unchanged = campaign.scheduled? && campaign.persisted? && campaign.scheduled_at == scheduled_at

      campaign.assign_attributes(
        title: @article.title.truncate(NotificationCampaign::TITLE_LENGTH),
        body: @article.body.squish.truncate(BODY_LENGTH),
        screen: "article", target_id: @article.id, scheduled_at:
      )
      campaign.topics = [ @article.notify_topic ] unless campaign.topic_ids == [ @article.notify_topic_id ]
      return campaign.tap(&:save!) if unchanged

      Campaigns::Schedule.call(campaign:)
    end
  end
end

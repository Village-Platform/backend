module Devices
  # Upserts an app install by installation_id (stable) and stores its current FCM token (rotates).
  #
  # Ownership rules: an anonymous request cannot change a device that belongs to a user, otherwise
  # whoever learned an installation_id could swap in their own token and receive that user's pushes.
  # The exception is the install itself, which proves it by presenting the token already stored:
  # it may detach (an expired JWT, a deleted account, a logout whose detach call failed). A
  # signed-in request may claim a guest device, its own, or another user's (the same phone, a new
  # login): the previous user is detached first.
  class Register
    def self.call(**) = new(**).call

    def initialize(installation_id:, token:, user:, locale: nil, app_version: nil, platform: "android")
      @installation_id = installation_id
      @token = token
      @user = user
      @platform = platform
      @attributes = { locale:, app_version:, platform: }.compact
    end

    def call
      device, changed = Device.transaction do
        device = Device.lock.find_or_initialize_by(installation_id: @installation_id)
        authorize!(device)
        Detach.call(device:) if device.user_id && device.user_id != @user&.id

        # A token now belongs to this install; an older row still holding it is a stale install.
        # Its topics are remembered so the token can be pulled out of the ones this install lacks.
        stale = Device.where(token: @token).where.not(installation_id: @installation_id)
        @stale_topic_ids = stale.flat_map { |old| old.topics.ids }.uniq
        stale.delete_all

        changed = device.new_record? || device.token != @token || device.user_id != @user&.id
        device.assign_attributes(token: @token, user: @user, last_seen_at: Time.current, **@attributes)
        device.save!
        [ device, changed ]
      end

      SyncDeviceTopicsJob.perform_later(device.id) if changed
      SyncDeviceTopicsJob.perform_later(device.id, topic_ids: @stale_topic_ids) if @stale_topic_ids.any?
      Observability::Metrics.increment(:devices_registered, result: changed ? "changed" : "unchanged")
      device
    end

    private

    # Blocks the takeovers described above. An install also never changes platform: a mismatch is
    # one surface reaching for another's row (the mobile API naming a dashboard browser's
    # installation_id, which would let any signed-in user claim it).
    def authorize!(device)
      raise OwnershipError if @user.nil? && device.user_id.present? && device.token != @token
      raise OwnershipError if device.persisted? && device.platform != @platform
    end
  end
end

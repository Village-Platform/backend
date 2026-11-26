module Api
  module V1
    # The app registers on launch, in onNewToken and right after login (with the bearer), and
    # detaches on logout before it drops the JWT. Guests register too: they receive broadcasts.
    class DevicesController < BaseController
      before_action :authenticate_user!, only: :detach

      # An unauthenticated write: limit it per IP.
      rate_limit to: 30, within: 1.minute, only: :update,
                 with: -> { render_error(:too_many_requests, "rate_limited") }

      # PUT /api/v1/devices/:installation_id  { "token", "locale", "app_version", "platform" }
      def update
        attributes = params.permit(:locale, :app_version, :platform).to_h.symbolize_keys
        # Browsers register through the dashboard (Admin::PushDevicesController), never here.
        if attributes.key?(:platform) && Device::APP_PLATFORMS.exclude?(attributes[:platform])
          return render_error(:unprocessable_content, "validation_failed")
        end

        device = Devices::Register.call(
          installation_id: params[:installation_id],
          token: params.require(:token),
          user: current_user,
          **attributes
        )
        render_record(device, DeviceSerializer)
      end

      # POST /api/v1/devices/:installation_id/detach
      def detach
        device = Device.find_by!(installation_id: params[:installation_id])
        raise Devices::OwnershipError unless device.user_id == current_user.id

        render_record(Devices::Detach.call(device:), DeviceSerializer)
      end
    end
  end
end

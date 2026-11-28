module Api
  module V1
    class MeController < BaseController
      before_action :authenticate_user!

      def show
        render_record(current_user, UserSerializer)
      end

      # A new password revokes every token of this user, including the one on this request, so the
      # response carries a replacement in meta.token. Clients that ignore it are signed out on their
      # next call (a 401), which is safe, only abrupt.

      def update
        attrs = me_params

        if phone_change?(attrs) && !current_user.authenticate(params[:user][:current_password].to_s)
          return render_error(:unprocessable_content, "invalid_password")
        end

        current_user.assign_attributes(attrs)
        current_user.save!(context: :profile_update)

        if current_user.saved_change_to_token_version?
          render json: {
            data: UserSerializer.render(current_user),
            meta: { token: issue_token_for(current_user) }
          }
        else
          render_record(current_user, UserSerializer)
        end
      rescue ActiveRecord::RecordInvalid => e
        raise unless e.record.errors.of_kind?(:phone, :taken)

        render_error(:unprocessable_content, "phone_taken", details: e.record.errors.to_hash(true))
      end


      # DELETE /api/v1/me  { "password": "..." }
      # Re-asks for the password so a leaked token alone cannot delete the account. A wrong
      # password is 422, not 401: the app signs the user out on any 401.
      def destroy
        return render_error(:forbidden, "forbidden") if current_user.super_admin?
        return render_error(:unprocessable_content, "invalid_password") unless current_user.authenticate(params.require(:password))

        Users::DeleteAccount.call(user: current_user)
        head :no_content
      end

      private

      def me_params
        params.require(:user).permit(:name, :email, :phone, :password, :password_confirmation)
      end

      def phone_change?(attrs)
        attrs.key?(:phone) && User.normalize_value_for(:phone, attrs[:phone]) != current_user.phone
      end
    end
  end
end

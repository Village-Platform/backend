module Api
  module V1
    class FirmsController < BaseController
      before_action :authenticate_user!, except: %i[index show]
      before_action :set_firm, only: %i[show update destroy approve reject]

      # GET /api/v1/firms?category_id=1&q=pharmacy&mine=true
      # GET /api/v1/categories/:category_id/firms
      #
      # Lists show only visible firms, to everyone. The policy scope still decides what a user may
      # open: owners and reviewers reach pending / suspended firms through show, owners list all of
      # their own with mine=true, and reviewers list the firms waiting for review with review=pending.
      def index
        scope = policy_scope(Firm).includes(category: { icon_image_attachment: :blob }).order(:name, :id)
        scope = if params[:mine].present? && current_user
          scope.where(owner_id: current_user.id)
        elsif params[:review] == "pending" && current_user&.reviewer?
          scope.pending
        else
          scope.visible
        end
        scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
        scope = scope.search(params[:q]) if params[:q].present?
        scope = filter(scope)

        records, meta = paginate(scope)
        render_collection(records, meta, FirmSerializer, user: current_user)
      end

      def show
        authorize @firm
        render_record(@firm, FirmSerializer, user: current_user)
      end

      # Goes live or waits for review depending on the author (Firms::Create): 403
      # subscription_required past the plan's quota, 403 too_many_pending past the review cap.
      def create
        authorize Firm
        firm = Firms::Create.call(author: current_user, attributes: permitted_attributes(Firm))
        render_record(firm, FirmSerializer, status: :created, user: current_user)
      end

      # An owner's edit of an active firm may send it back for review (Firms::Update).
      def update
        authorize @firm
        Firms::Update.call(firm: @firm, editor: current_user, attributes: permitted_attributes(@firm))
        render_record(@firm, FirmSerializer, user: current_user)
      end

      def destroy
        authorize @firm
        @firm.destroy!
        head :no_content
      end

      # PATCH /api/v1/firms/:id/approve
      def approve
        authorize @firm, :review?
        Firms::Review.approve(firm: @firm, reviewer: current_user)
        render_record(@firm, FirmSerializer, user: current_user)
      end

      # PATCH /api/v1/firms/:id/reject { reason }
      def reject
        authorize @firm, :review?
        Firms::Review.reject(firm: @firm, reviewer: current_user, reason: params.require(:reason))
        render_record(@firm, FirmSerializer, user: current_user)
      end

      private

      def set_firm
        @firm = policy_scope(Firm).find(params[:id])
      end
    end
  end
end

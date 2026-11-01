module Api
  module V1
    class CategoriesController < BaseController
      # Image loaders fetch icon_url without the API's headers.
      skip_before_action :require_api_token!, only: :icon
      before_action :authenticate_user!, except: %i[index show icon]
      before_action :set_category, only: %i[show update destroy icon]

      def index
        records, meta = paginate(filter(policy_scope(Category).with_attached_icon_image.ordered))
        render_collection(records, meta, CategorySerializer)
      end

      def show
        authorize @category
        render_record(@category, CategorySerializer)
      end

      # GET /api/v1/categories/:id/icon?v=<icon_version>
      # Public image bytes. A URL carrying the current version never changes content, so it is
      # cached for a year by the app and the CDN; without it (or with an old one) for an hour.
      def icon
        authorize @category, :show?
        blob = @category.icon_image.blob if @category.icon_image.attached?
        raise ActiveRecord::RecordNotFound unless blob

        if params[:v].present? && params[:v] == @category.icon_version
          expires_in 1.year, public: true, immutable: true
        else
          expires_in 1.hour, public: true
        end
        return unless stale?(etag: blob.checksum, public: true)

        response.headers["X-Content-Type-Options"] = "nosniff"
        send_data blob.download, type: blob.content_type, disposition: "inline"
      end

      def create
        authorize Category
        category = Category.create!(permitted_attributes(Category))
        render_record(category, CategorySerializer, status: :created)
      end

      def update
        authorize @category
        @category.update!(permitted_attributes(@category))
        render_record(@category, CategorySerializer)
      end

      def destroy
        authorize @category
        if @category.destroy
          head :no_content
        else
          render_error(:unprocessable_content, "cannot_delete", details: @category.errors.to_hash(true))
        end
      end

      private

      def set_category
        @category = policy_scope(Category).find(params[:id])
      end
    end
  end
end

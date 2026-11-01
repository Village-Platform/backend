module Api
  module V1
    class ArticlesController < BaseController
      before_action :authenticate_user!, except: %i[index show]
      before_action :set_article, only: %i[show update destroy approve reject]

      # GET /api/v1/articles?kind=news&mine=true
      #
      # Lists published articles. Authors list all of their own with mine=true, reviewers the ones
      # waiting for review with review=pending (and, as before, every article without it).
      def index
        scope = policy_scope(Article).includes(:author).latest_first
        scope = if params[:mine].present? && current_user
          scope.where(author_id: current_user.id)
        elsif current_user&.reviewer?
          params[:review] == "pending" ? scope.pending : scope
        else
          scope.published
        end
        scope = scope.where(kind: params[:kind]) if Article.kinds.key?(params[:kind])

        records, meta = paginate(filter(scope))
        render_collection(records, meta, ArticleSerializer, user: current_user)
      end

      def show
        authorize @article
        render_record(@article, ArticleSerializer, user: current_user)
      end

      # Approved or waiting for review depending on the author (Articles::Create): 403
      # too_many_pending past the review cap.
      def create
        authorize Article
        article = Articles::Create.call(author: current_user, attributes: permitted_attributes(Article))
        render_record(article, ArticleSerializer, status: :created, user: current_user)
      end

      # An author's edit of an approved article may send it back for review (Articles::Update).
      def update
        authorize @article
        Articles::Update.call(article: @article, editor: current_user, attributes: permitted_attributes(@article))
        render_record(@article, ArticleSerializer, user: current_user)
      end

      def destroy
        authorize @article
        @article.destroy!
        head :no_content
      end

      # PATCH /api/v1/articles/:id/approve
      def approve
        authorize @article, :review?
        Articles::Review.approve(article: @article, reviewer: current_user)
        render_record(@article, ArticleSerializer, user: current_user)
      end

      # PATCH /api/v1/articles/:id/reject { reason }
      def reject
        authorize @article, :review?
        Articles::Review.reject(article: @article, reviewer: current_user, reason: params.require(:reason))
        render_record(@article, ArticleSerializer, user: current_user)
      end

      private

      def set_article
        @article = policy_scope(Article).find(params[:id])
      end
    end
  end
end

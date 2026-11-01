class ArticlePolicy < ApplicationPolicy
  def index?   = true
  def show?    = true
  # Any signed-in user; Articles::Create decides whether it is approved or waits for review.
  def create?  = user.present?
  def update?  = super_admin? || author?
  def destroy? = super_admin? || author?
  # Approve / reject a submission (Articles::Review): admins and super admins.
  def review? = reviewer?

  def permitted_attributes
    %i[title body kind published_at]
  end

  private

  def author?
    user.present? && record.author_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    # Public: published articles. Authors also see their own (pending, rejected, scheduled);
    # reviewers see every article.
    def resolve
      return scope.all if reviewer?
      return scope.published if user.nil?

      scope.published.or(scope.where(author_id: user.id))
    end
  end
end

class FirmPolicy < ApplicationPolicy
  BASE_ATTRIBUTES = %i[category_id name description phone whatsapp address latitude longitude working_hours].freeze

  def index?   = true
  def show?    = true
  # Any signed-in user; Firms::Create decides whether it goes live or waits for review.
  def create?  = user.present?
  def update?  = super_admin? || owner?
  def destroy? = super_admin? || owner?
  # Approve / suspend by setting `status` through update; sent to the apps in FirmSerializer's `can`.
  def moderate? = super_admin?
  # Approve / reject a submission (Firms::Review): admins and super admins.
  def review? = reviewer?

  # Only super admins can change the status (approve / suspend).
  def permitted_attributes
    moderate? ? BASE_ATTRIBUTES + [ :status ] : BASE_ATTRIBUTES
  end

  private

  def owner?
    user.present? && record.owner_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    # Public: visible firms. Owners also see all of their own firms; reviewers see every firm, to
    # open the submissions they review.
    def resolve
      return scope.all if reviewer?
      return scope.visible if user.nil?

      scope.visible.or(scope.where(owner_id: user.id))
    end
  end
end

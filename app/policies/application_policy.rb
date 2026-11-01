class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  # Super admins may do everything; everyone else is denied unless a policy grants more.
  # Overrides must still return true for a super admin, usually by starting with `super_admin? ||`
  # (spec/policies/super_admin_policy_spec.rb checks every policy).
  def index?   = super_admin?
  def show?    = super_admin?
  def create?  = super_admin?
  def update?  = super_admin?
  def destroy? = super_admin?

  private

  def super_admin?
    user&.super_admin? || false
  end

  # Admins and super admins: review firm and article submissions.
  def reviewer?
    user&.reviewer? || false
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope

    def super_admin?
      user&.super_admin? || false
    end

    def reviewer?
      user&.reviewer? || false
    end
  end
end

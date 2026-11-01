# Declares what ransack may filter and sort on, in two tiers chosen by who is asking.
#
# Ransack can filter on a field that never appears in a response, and whether a result comes
# back is itself the answer — so an allowlist that ignores the caller turns a public listing into
# a lookup service for private data. The rule here is that the public tier may only name fields
# the public response already shows, and no public association may lead to a User.
#
#   ransack_tiers public: %w[ name status ], admin: %w[ phone ],
#                 public_associations: %w[ category ], admin_associations: %w[ owner ]
#
# The admin tier is the public tier plus its extras. A model that declares nothing is not
# searchable at all. Sorting follows the same allowlist, since ransack sorts on ransackable
# attributes.
module RansackTiers
  extend ActiveSupport::Concern

  class_methods do
    def ransack_tiers(public: [], admin: [], public_associations: [], admin_associations: [])
      @ransack_tiers = {
        attributes: { public: public.freeze, admin: (public + admin).freeze },
        associations: { public: public_associations.freeze,
                        admin: (public_associations + admin_associations).freeze }
      }.freeze
    end

    def ransackable_attributes(auth_object = nil) = ransack_tier(:attributes, auth_object)
    def ransackable_associations(auth_object = nil) = ransack_tier(:associations, auth_object)
    def ransackable_scopes(_auth_object = nil) = []

    private

    def ransack_tier(kind, auth_object)
      return [] unless @ransack_tiers

      @ransack_tiers.fetch(kind).fetch(ransack_admin?(auth_object) ? :admin : :public)
    end

    # Reviewers (admins and super admins): admins already see owners and authors, phones included,
    # on the review pages, and every other model's listing stays closed to them by its policy.
    def ransack_admin?(auth_object)
      auth_object.respond_to?(:reviewer?) && auth_object.reviewer?
    end
  end
end

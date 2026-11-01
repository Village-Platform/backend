class FirmSerializer
  # Expects :category (and its icon attachment) to be preloaded on collections.
  # `can` tells the apps which controls to show for `user` (nil = guest); the policy still decides.
  def self.render(firm, user: nil)
    policy = FirmPolicy.new(user, firm)
    {
      id: firm.id,
      name: firm.name,
      description: firm.description,
      phone: firm.phone,
      whatsapp: firm.whatsapp,
      address: firm.address,
      latitude: firm.latitude&.to_f,
      longitude: firm.longitude&.to_f,
      working_hours: firm.working_hours,
      status: firm.status,
      rejection_reason: firm.rejection_reason,
      owner_id: firm.owner_id,
      category: { id: firm.category.id, name: firm.category.name, icon: firm.category.icon, icon_url: firm.category.icon_url },
      created_at: firm.created_at,
      can: { update: policy.update?, destroy: policy.destroy?, moderate: policy.moderate?, review: policy.review? }
    }
  end
end

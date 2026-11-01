class ArticleSerializer
  # Expects :author to be preloaded on collections.
  # `can` tells the apps which controls to show for `user` (nil = guest); the policy still decides.
  def self.render(article, user: nil)
    policy = ArticlePolicy.new(user, article)
    {
      id: article.id,
      title: article.title,
      body: article.body,
      kind: article.kind,
      published_at: article.published_at,
      review_status: article.review_status,
      rejection_reason: article.rejection_reason,
      author: { id: article.author.id, name: article.author.name },
      can: { update: policy.update?, destroy: policy.destroy?, review: policy.review? }
    }
  end
end

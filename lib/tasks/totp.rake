namespace :totp do
  # For a reviewer who lost their phone and their recovery codes, or whose authenticator locked after
  # too many wrong codes. Verify who is asking first (call them; ideally a second super admin agrees):
  # this is the step an attacker would try to talk their way through. Run it from the web pod:
  #   kubectl exec deploy/web -- bin/rails "totp:reset[USER_ID,your-name]"
  desc "Remove a reviewer's authenticator and recovery codes and sign them out everywhere"
  task :reset, %i[ user_id operator ] => :environment do |_task, args|
    user = User.with_deleted.find(Integer(args.fetch(:user_id), 10))
    operator = args[:operator].to_s.strip
    abort %(Name yourself as the operator: bin/rails "totp:reset[#{user.id},your-name]") if operator.empty?

    User.transaction do
      TotpCredential.where(user:).delete_all
      RecoveryCode.where(user:).delete_all
      user.increment!(:token_version) # ends their dashboard sessions and API tokens
    end

    Rails.logger.warn("[ReviewerMfa] reset user_id=#{user.id} operator=#{operator}")
    puts "Two-factor sign-in reset for user #{user.id} (#{user.name}) by #{operator}. " \
         "They set up a new authenticator at their next dashboard sign-in."
  end
end

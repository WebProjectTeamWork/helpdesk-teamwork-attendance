# Seeds a Zammad install with the project's accounts and tickets.
# Runs automatically in the one-shot `zammad-seed` service after `zammad-init`.
# Safe to run again: existing users are updated, existing tickets (same title) are skipped.
#
#   docker compose run --rm zammad-seed

require 'json'

dir = __dir__
users   = JSON.parse(File.read(File.join(dir, 'users.json')))
tickets = JSON.parse(File.read(File.join(dir, 'tickets.json')))

agent_password = ENV.fetch('SEED_AGENT_PASSWORD', 'Teamwork2026!')
admin_password = ENV.fetch('SEED_ADMIN_PASSWORD', 'Admin2026!Pass')

UserInfo.current_user_id = 1

def upsert_user(attrs, password, roles, groups)
  user = User.find_by(email: attrs['email'].downcase) || User.new(login: attrs['email'].downcase)
  is_new = user.new_record?
  user.assign_attributes(
    firstname: attrs['firstname'],
    lastname:  attrs['lastname'],
    email:     attrs['email'].downcase,
    active:    true,
    roles:     Role.where(name: roles).to_a,
  )
  # Only set the password on creation, so a password changed in the UI is kept.
  user.password = password if is_new
  user.save!
  user.group_names_access_map = groups.to_h { |g| [g, ['full']] } if groups.any?
  puts "#{is_new ? 'Created' : 'Updated'} #{roles.join('+')} #{user.email}"
  user
end

Transaction.execute(disable_notification: true, bulk: true) do
  # Group the tickets live in.
  group_names = (tickets.map { |t| t['group'] } + users.flat_map { |u| u['groups'] || [] }).compact.uniq
  group_names.each { |name| Group.find_by(name: name) || Group.create!(name: name, active: true) }

  # Admin account (replaces the first-run wizard on a fresh install).
  admin = users.find { |u| u['admin'] }
  upsert_user(admin, admin_password, %w[Admin Agent], group_names) if admin

  # Agent accounts for the people who solve the tickets.
  users.reject { |u| u['admin'] }.each do |u|
    upsert_user(u, agent_password, u['roles'] || %w[Agent], u['groups'] || group_names)
  end

  Setting.set('system_init_done', true)
  Setting.set('organization', ENV['SEED_ORGANIZATION']) if ENV['SEED_ORGANIZATION'].present?

  created = 0
  tickets.each do |t|
    next if Ticket.exists?(title: t['title'])

    customer = User.find_by(email: t['customer_email'].to_s.downcase) || User.find_by(email: admin&.dig('email')) || User.find(1)
    ticket = Ticket.create!(
      title:    t['title'],
      group:    Group.find_by!(name: t['group']),
      customer: customer,
      state:    Ticket::State.find_by!(name: t['state']),
      priority: Ticket::Priority.find_by!(name: t['priority']),
    )
    t['articles'].each do |a|
      Ticket::Article.create!(
        ticket:       ticket,
        type:         Ticket::Article::Type.find_by!(name: a['type']),
        sender:       Ticket::Article::Sender.find_by!(name: a['sender']),
        internal:     a['internal'],
        content_type: a['content_type'],
        subject:      a['subject'],
        body:         a['body'],
        from:         customer.fullname,
      )
    end
    t['tags'].each { |tag| Tag.tag_add(object: 'Ticket', o_id: ticket.id, item: tag, created_by_id: 1) }
    created += 1
  end
  puts "Tickets: #{created} created, #{tickets.size - created} already present"
end

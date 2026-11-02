# Dumps the tickets of the running Zammad into seed/tickets.json, so they are
# recreated on a fresh install by seed.rb.
#
# Usage (from the zammad/ directory, with the stack running):
#   docker compose run --rm zammad-seed bundle exec rails r /opt/zammad-seed/export.rb
#
# Only tickets tagged "teamwork-attendance" are exported (override with EXPORT_TAG=...,
# or EXPORT_TAG= to export everything).

require 'json'

tag = ENV.fetch('EXPORT_TAG', 'teamwork-attendance')
out = ENV.fetch('EXPORT_FILE', File.join(__dir__, 'tickets.json'))

tickets = Ticket.order(:id).to_a
tickets.select! { |t| t.tag_list.include?(tag) } if tag.present?

data = tickets.map do |t|
  {
    title:          t.title,
    group:          t.group&.name,
    state:          t.state.name,
    priority:       t.priority.name,
    customer_email: t.customer&.email,
    tags:           t.tag_list,
    articles:       t.articles.order(:id).map do |a|
      {
        type:         a.type.name,
        sender:       a.sender.name,
        internal:     a.internal,
        content_type: a.content_type,
        subject:      a.subject,
        body:         a.body,
      }
    end,
  }
end

File.write(out, JSON.pretty_generate(data) + "\n")
puts "Exported #{data.size} tickets to #{out}"

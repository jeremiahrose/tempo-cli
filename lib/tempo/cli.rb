require 'thor'
require_relative 'client'

module Tempo
  class CLI < Thor
    desc "view [DATE]", "View timesheet for a date or date range"
    option :from, type: :string, desc: "Start date (YYYY-MM-DD)"
    option :to, type: :string, desc: "End date (YYYY-MM-DD)"
    def view(date = nil)
      from = options[:from] || date || Date.today.to_s
      to = options[:to] || date || from

      worklogs = client.worklogs(from: from, to: to)

      if worklogs.empty?
        puts "No worklogs found for #{from == to ? from : "#{from} to #{to}"}"
        return
      end

      total_seconds = 0
      current_date = nil

      worklogs.sort_by { |l| [l['startDate'], l['startTime'] || ''] }.each do |log|
        if log['startDate'] != current_date
          current_date = log['startDate']
          puts "" if total_seconds > 0
          puts "#{current_date} (#{Date.parse(current_date).strftime('%A')})"
          puts "-" * 40
        end

        issue = client.issue_details(log.dig('issue', 'self'))
        hours = log['timeSpentSeconds'] / 3600.0

        puts "  #%-8s %-12s %5.1fh  %s" % [log['tempoWorklogId'], issue[:key], hours, log['description']]
        total_seconds += log['timeSpentSeconds']
      end

      puts ""
      puts "Total: %.1fh" % (total_seconds / 3600.0)
    end

    desc "projects", "List available Jira projects"
    def projects
      client.projects.each do |p|
        puts "  %-12s %s" % [p[:key], p[:name]]
      end
    end

    desc "issues PROJECT_KEY", "List Jira issues for a project"
    option :status, type: :string, desc: "Filter by status (e.g. 'In Progress')"
    option :max, type: :numeric, default: 20, desc: "Max results"
    def issues(project_key)
      issues = client.search_issues(project_key, max_results: options[:max], status: options[:status])

      if issues.empty?
        puts "No issues found for #{project_key}"
        return
      end

      issues.each do |issue|
        status = issue.dig('fields', 'status', 'name')
        type = issue.dig('fields', 'issuetype', 'name')
        summary = issue.dig('fields', 'summary')
        puts "  %-12s %-14s %-12s %s" % [issue['key'], "[#{status}]", type, summary]
      end
    end

    desc "log ISSUE_KEY HOURS", "Log time to a Jira issue"
    option :date, type: :string, desc: "Date (YYYY-MM-DD, default: today)"
    option :description, type: :string, desc: "Work description"
    option :start_time, type: :string, desc: "Start time (HH:MM:SS)"
    def log(issue_key, hours)
      date = options[:date] || Date.today.to_s

      # Resolve issue key to numeric ID via Jira
      issue_data = client.search_issues(issue_key.split('-').first, max_results: 50)
      issue = issue_data.find { |i| i['key'] == issue_key }
      abort "Issue #{issue_key} not found" unless issue

      client.create_worklog(
        issue_id: issue['id'],
        time_spent_seconds: (hours.to_f * 3600).to_i,
        start_date: date,
        start_time: options[:start_time],
        description: options[:description]
      )

      puts "Logged %.1fh to %s on %s" % [hours.to_f, issue_key, date]
    end

    desc "edit WORKLOG_ID", "Edit a worklog entry"
    option :hours, type: :numeric, desc: "New time in hours"
    option :description, type: :string, desc: "New description"
    option :date, type: :string, desc: "New date (YYYY-MM-DD)"
    def edit(worklog_id)
      attrs = {}
      attrs[:timeSpentSeconds] = (options[:hours] * 3600).to_i if options[:hours]
      attrs[:description] = options[:description] if options[:description]
      attrs[:startDate] = options[:date] if options[:date]

      if attrs.empty?
        abort "Specify at least one of: --hours, --description, --date"
      end

      client.update_worklog(worklog_id, attrs)
      puts "Updated worklog #{worklog_id}"
    end

    desc "delete WORKLOG_ID", "Delete a worklog entry"
    def delete(worklog_id)
      client.delete_worklog(worklog_id)
      puts "Deleted worklog #{worklog_id}"
    end

    desc "duplicate SOURCE_DATE TARGET_DATE", "Duplicate all worklogs from one day to another"
    option :skip_weekends, type: :boolean, default: true, desc: "Skip weekends when duplicating ranges"
    def duplicate(source_date, target_date)
      source_logs = client.worklogs(from: source_date)

      if source_logs.empty?
        puts "No worklogs found for #{source_date}"
        return
      end

      puts "Duplicating #{source_logs.length} worklog(s): #{source_date} -> #{target_date}"

      success = 0
      source_logs.each do |log|
        client.create_worklog(
          issue_id: log.dig('issue', 'id'),
          time_spent_seconds: log['timeSpentSeconds'],
          start_date: target_date,
          start_time: log['startTime'],
          description: log['description'],
          author_account_id: log.dig('author', 'accountId'),
          billable_seconds: log['billableSeconds']
        )
        success += 1
      rescue StandardError => e
        puts "  Failed: #{e.message}"
      end

      puts "Created #{success}/#{source_logs.length} worklogs"
    end

    desc "duplicate-week SOURCE_START_DATE [WEEKS_OFFSET]", "Duplicate an entire week of worklogs"
    def duplicate_week(start_date, weeks_offset = "1")
      source_start = Date.parse(start_date)
      target_start = source_start + (weeks_offset.to_i * 7)

      puts "Duplicating week: #{source_start} -> #{target_start}"
      puts "=" * 50

      total = 0
      5.times do |i|
        source = source_start + i
        target = target_start + i
        next if source.saturday? || source.sunday?

        logs = client.worklogs(from: source.to_s)
        next if logs.empty?

        puts "\n#{source} -> #{target}"
        count = 0
        logs.each do |log|
          client.create_worklog(
            issue_id: log.dig('issue', 'id'),
            time_spent_seconds: log['timeSpentSeconds'],
            start_date: target.to_s,
            start_time: log['startTime'],
            description: log['description'],
            author_account_id: log.dig('author', 'accountId'),
            billable_seconds: log['billableSeconds']
          )
          count += 1
        rescue StandardError => e
          puts "  Failed: #{e.message}"
        end
        puts "  Created #{count}/#{logs.length} worklogs"
        total += count
      end

      puts "\n#{"=" * 50}"
      puts "Total: #{total} worklogs duplicated"
    end

    desc "whoami", "Show current user info"
    def whoami
      user = client.current_user
      puts "Name:  #{user['displayName']}"
      puts "Email: #{user['emailAddress']}"
      puts "ID:    #{user['accountId']}"
    end

    private

    def client
      @client ||= Tempo::Client.new
    end
  end
end

require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'dotenv/load'

module Tempo
  class Client
    TEMPO_BASE_URL = 'https://api.tempo.io/4'
    REQUIRED_ENV_VARS = %w[TEMPO_API_TOKEN JIRA_API_TOKEN JIRA_EMAIL JIRA_BASE_URL].freeze

    def initialize
      missing = REQUIRED_ENV_VARS.select { |var| ENV[var].nil? || ENV[var].empty? }
      unless missing.empty?
        $stderr.puts "Error: Missing required environment variables:"
        missing.each { |var| $stderr.puts "  - #{var}" }
        $stderr.puts ""
        $stderr.puts "Create a .env file with these variables. See README.md for details."
        exit 1
      end

      @tempo_token = ENV['TEMPO_API_TOKEN']
      @jira_token = ENV['JIRA_API_TOKEN']
      @jira_email = ENV['JIRA_EMAIL']
      @jira_base_url = ENV['JIRA_BASE_URL']
    end

    def current_user
      @current_user ||= jira_get('/rest/api/3/myself')
    end

    def current_account_id
      current_user['accountId']
    end

    def worklogs(from:, to: from)
      data = tempo_get("/worklogs?from=#{from}&to=#{to}")
      all = data['results'] || data
      all.select { |log| log.dig('author', 'accountId') == current_account_id }
    end

    def create_worklog(issue_id:, time_spent_seconds:, start_date:, start_time: nil, description: nil, author_account_id: nil, billable_seconds: nil)
      body = {
        issueId: issue_id,
        timeSpentSeconds: time_spent_seconds,
        startDate: start_date,
        authorAccountId: author_account_id || current_account_id
      }
      body[:startTime] = start_time if start_time
      body[:description] = description if description
      body[:billableSeconds] = billable_seconds if billable_seconds

      tempo_post('/worklogs', body)
    end

    def delete_worklog(worklog_id)
      tempo_delete("/worklogs/#{worklog_id}")
    end

    def get_worklog(worklog_id)
      tempo_get("/worklogs/#{worklog_id}")
    end

    def update_worklog(worklog_id, attributes)
      existing = get_worklog(worklog_id)
      body = {
        issueId: existing.dig('issue', 'id'),
        timeSpentSeconds: existing['timeSpentSeconds'],
        startDate: existing['startDate'],
        startTime: existing['startTime'],
        description: existing['description'],
        authorAccountId: existing.dig('author', 'accountId')
      }
      body.merge!(attributes)
      tempo_put("/worklogs/#{worklog_id}", body)
    end

    def projects
      data = jira_get('/rest/api/3/project?orderBy=key')
      data.map { |p| { key: p['key'], name: p['name'] } }
    end

    def search_issues(project_key, max_results: 50, status: nil)
      jql = "project = #{project_key} ORDER BY updated DESC"
      jql = "project = #{project_key} AND status = \"#{status}\" ORDER BY updated DESC" if status

      body = { jql: jql, maxResults: max_results, fields: %w[summary status issuetype] }
      data = jira_post('/rest/api/3/search/jql', body)
      data['issues'] || []
    end

    def issue_details(issue_url)
      uri = URI(issue_url)
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(@jira_email, @jira_token)
      req['Accept'] = 'application/json'

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

      if res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body)
        { key: data['key'], summary: data.dig('fields', 'summary') }
      else
        { key: 'Unknown', summary: 'Unknown' }
      end
    end

    private

    def jira_post(path, body)
      uri = URI("#{@jira_base_url}#{path}")
      req = Net::HTTP::Post.new(uri)
      req.basic_auth(@jira_email, @jira_token)
      req['Accept'] = 'application/json'
      req['Content-Type'] = 'application/json'
      req.body = body.to_json

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      unless res.is_a?(Net::HTTPSuccess)
        abort_with_jira_api_error(response: res)
      end
      JSON.parse(res.body)
    end

    def jira_get(path)
      uri = URI("#{@jira_base_url}#{path}")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(@jira_email, @jira_token)
      req['Accept'] = 'application/json'

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      unless res.is_a?(Net::HTTPSuccess)
        abort_with_jira_api_error(response: res)
      end
      JSON.parse(res.body)
    end

    def tempo_get(path)
      uri = URI("#{TEMPO_BASE_URL}#{path}")
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{@tempo_token}"
      req['Accept'] = 'application/json'

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      unless res.is_a?(Net::HTTPSuccess)
        abort_with_tempo_api_error(response: res)
      end
      JSON.parse(res.body)
    end

    def tempo_post(path, body)
      uri = URI("#{TEMPO_BASE_URL}#{path}")
      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = "Bearer #{@tempo_token}"
      req['Content-Type'] = 'application/json'
      req.body = body.to_json

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      unless res.is_a?(Net::HTTPSuccess)
        abort_with_tempo_api_error(response: res)
      end
      JSON.parse(res.body)
    end

    def tempo_put(path, body)
      uri = URI("#{TEMPO_BASE_URL}#{path}")
      req = Net::HTTP::Put.new(uri)
      req['Authorization'] = "Bearer #{@tempo_token}"
      req['Content-Type'] = 'application/json'
      req.body = body.to_json

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      unless res.is_a?(Net::HTTPSuccess)
        abort_with_tempo_api_error(response: res)
      end
      JSON.parse(res.body)
    end

    def tempo_delete(path)
      uri = URI("#{TEMPO_BASE_URL}#{path}")
      req = Net::HTTP::Delete.new(uri)
      req['Authorization'] = "Bearer #{@tempo_token}"

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      unless res.is_a?(Net::HTTPSuccess)
        abort_with_tempo_api_error(response: res)
      end
      true
    end

    ATLASSIAN_API_TOKENS_URL = 'https://id.atlassian.com/manage-profile/security/api-tokens'

    # A 401 from Jira means it rejected JIRA_EMAIL and JIRA_API_TOKEN, and an expired token is the usual reason; any other failure is reported as Jira returned it.
    def abort_with_jira_api_error(response:)
      if response.code == '401'
        abort "Jira rejected the credentials in JIRA_EMAIL and JIRA_API_TOKEN. Atlassian API tokens expire: create a new one at #{ATLASSIAN_API_TOKENS_URL} and update JIRA_API_TOKEN."
      end
      abort "Jira API error: #{response.code} - #{response.message}\n#{response.body}"
    end

    # A 401 from Tempo means it rejected TEMPO_API_TOKEN; any other failure is reported as Tempo returned it.
    def abort_with_tempo_api_error(response:)
      if response.code == '401'
        abort 'Tempo rejected TEMPO_API_TOKEN. Generate a new one in Tempo > Settings > API Integration and update TEMPO_API_TOKEN.'
      end
      abort "Tempo API error: #{response.code} - #{response.message}\n#{response.body}"
    end
  end
end

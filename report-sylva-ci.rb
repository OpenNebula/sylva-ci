#!/usr/bin/env ruby

# frozen_string_literal: true

require 'json'
require 'net/https'
require 'singleton'
require 'uri'

GITLAB_URL     = ENV['GITLAB_URL']     || 'https://gitlab.com'
GITLAB_PROJECT = ENV['GITLAB_PROJECT'] || ARGV[0]
GITLAB_TOKEN   = ENV['GITLAB_TOKEN']   || ARGV[1]

raise 'GITLAB_PROJECT is nil' if GITLAB_PROJECT.nil?
raise 'GITLAB_TOKEN is nil'   if GITLAB_TOKEN.nil?

class Gitlab
    include Singleton

    def initialize
        @uri              = URI.parse(GITLAB_URL)
        @http             = Net::HTTP.new(@uri.host, @uri.port)
        @http.use_ssl     = @uri.scheme == 'https'
        @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    def finish
        @http.finish if @http.started?
    end

    def editpage(content, keep_alive: false)
        path     = "/api/v4/projects/#{GITLAB_PROJECT}/wikis/CAPONE-daily-tests-report"
        req      = Net::HTTP::Put.new(path)
        req.body = URI.encode_www_form('format' => 'markdown', 'content' => content)
        do_request req, keep_alive
    end

    private

    def do_request(req, keep_alive, expect_json: true)
        @http.start unless @http.started?
        req['PRIVATE-TOKEN'] = GITLAB_TOKEN
        expect_json ? JSON.parse(@http.request(req).body) : @http.request(req).body
    rescue StandardError => e
        $stderr.puts(e.full_message)
        nil
    ensure
        @http.finish unless keep_alive
    end
end

builds = Dir['/var/tmp/sylva-ci/logs/*/result.json'].each_with_object([]) do |p, acc|
    r = JSON.parse(File.read(p))

    next if r['name'].nil?
    next if r['ts'].nil?
    next if r['failed'].nil?

    next if (n = /^\.#checks\.(x86_64-linux\.sylva-ci-deploy-\w+)$/.match(r['name'])).nil?
    next if (t = /^(\d{4})(\d{2})(\d{2})-\d{2}\d{2}\d{2}$/.match(r['ts'])).nil?

    acc << {
        :job    => n[1],
        :ts     => r['ts'],
        :date   => t[1..3].join(%[-]),
        :status => r['failed'] ? %[❌] : %[✔],
    }
end

raise 'nothing to report' if builds.empty?

by_job = builds.group_by { |b| b[:job] }
               .to_h     { |j, bb| [j, bb.sort { |x, y| y[:ts] <=> x[:ts] }] }

results = by_job.to_h do |j, bb|
    status_by_date = bb.each_with_object({}) do |b, acc|
        acc[b[:date]] ||= b[:status]
    end
    [j, status_by_date]
end.then do |rr|
    jobs = rr.keys
             .sort
    dates = rr.values
              .map(&:keys)
              .flatten
              .uniq
              .sort { |x, y| y <=> x }
              .take(5)
    [rr, jobs, dates]
end

content = +'' << <<~HEADER
---
title: CAPONE daily tests report
---
CAPONE clusters are tested daily at [OpenNebula](https://github.com/OpenNebula/sylva-ci).

# Nightly - CAPONE
HEADER
content << %[|] << (h = (['job'] + results[2])).join(%[|]) << %[|] << %[\n]
content << %[|] << (['---'] * h.count).join(%[|])          << %[|] << %[\n]
results[1].each do |j|
    content << %[|] << ([j] + results[2].map { |d| (v = results[0][j][d]).nil? ? %[❔] : v }).join(%[|]) << %[|] << %[\n]
end

puts Gitlab.instance.editpage(content)

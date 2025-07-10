#!/usr/bin/env ruby

# frozen_string_literal: true

require 'date'
require 'json'
require 'net/https'
require 'singleton'
require 'uri'

HYDRA_URL      = ENV['HYDRA_URL']      || 'http://127.0.0.1:3000'
GITLAB_URL     = ENV['GITLAB_URL']     || 'https://gitlab.com'
GITLAB_PROJECT = ENV['GITLAB_PROJECT'] || ARGV[0]
GITLAB_TOKEN   = ENV['GITLAB_TOKEN']   || ARGV[1]

raise 'GITLAB_PROJECT is nil' if GITLAB_PROJECT.nil?
raise 'GITLAB_TOKEN is nil'   if GITLAB_TOKEN.nil?

class Hydra
    include Singleton

    def initialize
        @uri              = URI.parse(HYDRA_URL)
        @http             = Net::HTTP.new(@uri.host, @uri.port)
        @http.use_ssl     = @uri.scheme == 'https'
        @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    def finish
        @http.finish if @http.started?
    end

    def jobsets(keep_alive: false)
        path = '/api/jobsets?project=sylva-ci'
        req  = Net::HTTP::Get.new(path)
        do_request req, keep_alive
    end

    def evals(jobset_id, keep_alive: false)
        path = "/jobset/sylva-ci/#{jobset_id}/evals"
        req  = Net::HTTP::Get.new(path)
        do_request req, keep_alive
    end

    def builds(eval_id, keep_alive: false)
        path = "/eval/#{eval_id}/builds"
        req  = Net::HTTP::Get.new(path)
        do_request req, keep_alive
    end

    private

    def do_request(req, keep_alive, expect_json: true)
        @http.start unless @http.started?
        req['Content-Type'] = 'application/json' if expect_json
        expect_json ? JSON.parse(@http.request(req).body) : @http.request(req).body
    rescue StandardError => e
        $stderr.puts(e.full_message)
        nil
    ensure
        @http.finish unless keep_alive
    end
end

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

begin
    jobsets = Hydra.instance.jobsets(keep_alive: true).each_with_object([]) do |j, acc|
        acc << j if j['name'].start_with?('sylva-ci')
    end.flatten

    evals = jobsets.each_with_object([]) do |j, acc|
        Hydra.instance.evals(j['name'], keep_alive: true)['evals'].each do |e|
            acc << e
        end
    end.flatten

    builds = evals.each_with_object([]) do |e, acc|
        acc << Hydra.instance.builds(e['id'], keep_alive: true)
    end.flatten
ensure
    Hydra.instance.finish
end

by_job = builds.group_by { |b| b['job'] }
               .to_h     { |j, bb| [j, bb.sort { |x, y| y['id'].to_i <=> x['id'].to_i }] }

def to_date(timestamp)
    DateTime.strptime(timestamp.to_s, '%s').to_date.to_s
end

def to_status(finished, buildstatus)
    return %[⏩] if finished.to_i == 0
    return %[✔]  if buildstatus.to_i == 0
    return %[❌]
end

results = by_job.to_h do |j, bb|
    status_by_date = bb.each_with_object({}) do |b, acc|
        acc[to_date(b['timestamp'])] ||= to_status(b['finished'], b['buildstatus'])
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

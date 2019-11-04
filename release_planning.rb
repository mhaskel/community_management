#!/usr/bin/env ruby

require 'optparse'
require_relative 'octokit_utils'
require_relative 'release_planning/pupet_module'
require_relative 'release_planning/puppet_module_augmenter'

  options = {}
  options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
  parser = OptionParser.new do |opts|

  opts.banner = 'Usage: release_planning.rb [options]'
  opts.on('-c', '--commit-threshold NUM', 'Number of commits since release') { |v| options[:commits] = v.to_i }
  opts.on('-g', '--tag-regex REGEX', 'Tag regex') { |v| options[:tag_regex] = v }
  opts.on('-m', '--time-threshold DAYS', 'Days since release') { |v| options[:time] = v.to_i }
  opts.on('-n', '--namespace NAME', 'GitHub namespace. Required.') { |v| options[:namespace] = v }
  opts.on('-r', '--repo-regex REGEX', 'Repository regex') { |v| options[:repo_regex] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-v', '--verbose', 'More output') { options[:verbose] = true }
  opts.on('-o', '--output', 'Creates html+json output') { options[:output] = true }

  opts.on('--puppetlabs-supported', 'Select only Puppet Labs\' supported modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = OctokitUtils::SUPPORTED_MODULES_REGEX
  }
end

parser.parse!

missing = []
missing << '-n' if options[:namespace].nil?
missing << '-t' if options[:oauth].nil?
missing << '-m or -c' if options[:time].nil? and options[:commits].nil?
if not missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

options[:repo_regex] = '.*' if options[:repo_regex].nil?
options[:tag_regex] = '.*' if options[:tag_regex].nil?

util = OctokitUtils.new(options[:oauth])
repos = util.list_repos(options[:namespace], options)

puppet_modules = []
repo_data = []

repos.each do |repo|
  begin
    latest_tag = util.fetch_tags("#{options[:namespace]}/#{repo}", options).first
    tag_ref = util.ref_from_tag(latest_tag)
    date_of_tag = util.date_of_ref("#{options[:namespace]}/#{repo}", tag_ref)
    commits_since_tag = util.commits_since_date("#{options[:namespace]}/#{repo}", date_of_tag)


    repo_data << { 'repo' => "#{options[:namespace]}/#{repo}", 'date' => date_of_tag, 'commits' => commits_since_tag }
     puppet_modules << PuppetModule.new(repo , "#{options[:namespace]}/#{repo}", date_of_tag, commits_since_tag)
  rescue
    puts "Unable to fetch tags for #{options[:namespace]}/#{repo}" if options[:verbose]
  end
end

puppet_modules.each {|puppet_module| puts puppet_modules }

PuppetModuleAugmenter.new.augment!(puppet_modules)
puts puppet_modules

if options[:commits]
  due_by_commit = repo_data.select { |x| x['commits'] > options[:commits] }
end

if options[:time]
  threshold = Time.now - options[:time]
  due_by_time = repo_data.select { |x| x['date'] < threshold }
end

if due_by_commit and due_by_time
  due_for_release = due_by_commit & due_by_time
elsif due_by_commit
  due_for_release = due_by_commit
else
  due_for_release = due_by_time
end

due_for_release.each do |entry|
  puts "#{entry['repo']} is due_for_release. Last release was tagged on #{entry['date']} and there have been #{entry['commits']} commits since then."
end

html = []

html.push("<html>")
html.push("<head>")
html.push("<script src='http://ajax.googleapis.com/ajax/libs/jquery/3.4.1/jquery.min.js' type='text/javascript'></script>")
html.push("<script src='./web_libraries/sorttable.js'></script><link rel='stylesheet' href='./web_libraries/bootstrap.min.css'>")
html.push("<script src='https://cdn.datatables.net/1.10.20/js/jquery.dataTables.js'></script>") 
html.push("<link rel='stylesheet' type='text/css' href='https://cdn.datatables.net/1.10.20/css/jquery.dataTables.css'>")
html.push("<script type= 'text/javascript'> $(document).ready( function () {$('#id_table').DataTable();} ); </script>")
html.push("</head>")


html.push("<body>")
html.push("<h2>Modules Requiring Release</h2>")
html.push("<thead>")
html.push("<table border='1'  id = 'id_table' style='width:100%' class='sortable table table-hover'> <tr>")
html.push("<th>Module Name</th>")
html.push("<th>Last Release Tag Date</th>")
html.push("<th>Commits Since Then</th>")
html.push("<th>Number of downloads</th>")
html.push("</tr>")
html.push("</thead>")    
puppet_modules.each do |puppet_module|
  html.push("<tr>")
  html.push("<td>#{puppet_module.namespace}</td>")
  html.push("<td>#{puppet_module.tag_date}</td>")
  html.push("<td align=\"center\">#{puppet_module.commits}</td>")
  html.push("<td align=\"center\">#{puppet_module.downloads}</td>")
end
html.push("</body>")
html.push("</html>")

if options[:output]
  File.open("ModulesRelease.html", "w+") do |f|
    f.puts(html)
  end

  File.open("ModulesRelease.json", "w") do |f|
    JSON.dump(due_for_release, f)
  end
end  

#!/usr/bin/ruby
require_relative 'coursera_session.rb'
require_relative 'resource_downloader.rb'
require_relative 'password.rb'
require 'yaml'

include Password

def prompt(message, hide = false, default = nil)
  while true
    if hide
      result = ask(message)
    else
      print message
      result = gets.strip
    end
    break if result != '' || (result = default)
  end
  result.strip
end

config = {}
if File.readable?('.coursera.yaml')
  config = YAML.load(File.read('.coursera.yaml'))
  raise "Invalid configuration in .coursera.yaml" unless config.respond_to?(:[])
end

puts "------ Coursera Resource Downloader ------"
puts "\nProvide your username and password for Coursera. (The same values that you would enter at: https://accounts.coursera.org/signin)"
username = prompt("Username: ")
password = prompt("Password: ", true)


puts "\nProvide the \"URL\" name of the course whose resources you are wanting to download. \
For example, if the URL for the class home page is 'https://class.coursera.org/ml-003/class' \
then you would answer with 'ml-003' (without quotes)."
if config[:course]
  coursename = prompt("Course URL Name (#{config[:course]}): ", false, config[:course])
else
  coursename = prompt("Course URL Name: ")
end

config[:course] = coursename

File.open('.coursera.yaml', 'w') {|file| file.write(config.to_yaml) }

#Prompt for directory

session = CourseraSession.new username, password, coursename
downloader = ResourceDownloader.new session.cookies, session.resource_links
downloader.download


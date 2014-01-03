#!/usr/bin/ruby
require_relative 'coursera_session.rb'
require_relative 'resource_downloader.rb'
require_relative 'password.rb'

include Password

def prompt(message, hide = false)
  while true
    if hide
      result = ask(message)
    else
      print message
      result = gets.strip
    end
    break unless result == ''
  end
  result
end

puts "------ Coursera Resource Downloader ------"
puts "\nProvide your username and password for Coursera. (The same values that you would enter at: https://accounts.coursera.org/signin)"
username = prompt("Username: ")
password = prompt("Password: ", true)

puts "\nProvide the \"URL\" name of the course whose resources you are wanting to download. \
For example, if the URL for the class home page is 'https://class.coursera.org/ml-003/class' \
then you would answer with 'ml-003' (without quotes)."
coursename = prompt("Course (URL) Name: ")

#Prompt for directory

session = CourseraSession.new username, password, coursename
downloader = ResourceDownloader.new session.cookies, session.resource_links
downloader.download


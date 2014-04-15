#!/usr/bin/ruby

require_relative '../coursera_session.rb'
require_relative '../password.rb'
include Password

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
#       UPDATE WITH VALUES       #
#  APPROPRIATE FOR YOUR PROFILE  #
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
DFLT_USERNAME = '%s@gmail.com' % ('justin@w@smith'.gsub('@', '.'))
COURSES = ['dsp-002', 'ml-003']
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#

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

username = DFLT_USERNAME
puts "Username: #{username}"

password = prompt("Password: ", true)
puts

COURSES.each do |course|
	describe 'Coursera Session'  do

		before :all do
			@session = CourseraSession.new username, password, course
		end

		it 'should not show password from inspect' do
			@session.should respond_to(:inspect)
			@session.inspect.index('password').should be_nil
		end

		it 'should return authorization cookies' do
			@session.should respond_to(:cookies)
			@session.cookies.should respond_to(:[])
			@session.cookies.should respond_to(:each)
			@session.cookies.should respond_to(:any?)
			(@session.cookies.any? {|k,v| k.to_s.upcase == 'CAUTH'}).should be_true
		end

		it 'should return resource links' do
			@session.should respond_to(:resource_links)
			@session.resource_links.should respond_to(:[])
			@session.resource_links.should respond_to(:each)
			@session.resource_links.should respond_to(:any?)
			@session.resource_links.should have_at_least(1).items
		end
		
	end
end
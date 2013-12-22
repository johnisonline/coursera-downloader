#!/usr/bin/ruby

require "mechanize"
require "mechanize/http/content_disposition_parser"
require "uri"
require 'net/https'
require 'nokogiri'
require_relative 'password.rb'

class CourseraSession

  @@base_course_uri = 'https://class.coursera.org/%s'
  @@login_uri = 'https://accounts.coursera.org/api/v1/login'
  @@course_content_path = '/lecture/index'

  def CourseraSession.parse_value(key, string)
    regexp = Regexp.new("#{key}=([^;]+)")
    string.match(regexp)[1]
  end

  def initialize username, password, course_name
    @username = username
    @password = password
    @course_name = course_name
  end

  def course_uri
    @course_uri ||= URI(@@base_course_uri % @course_name)
  end

  def course_content_uri
    @course_content_uri ||= URI((@@base_course_uri % @course_name) + @@course_content_path)
  end


  def csrf_token
    unless @csrf_token
      http = Net::HTTP.new(course_uri.host, course_uri.port)
      http.use_ssl = (course_uri.scheme == 'https')
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      
      response = http.get(course_uri.path)
      raise "Unable to connect to course" unless response["Set-Cookie"]
      @csrf_token = response["Set-Cookie"].split(";")[0].split("=")[1]
    end
    @csrf_token
  end

  def cauth
    unless @cauth
      uri = URI(@@login_uri)

      Net::HTTP.start(uri.host, uri.port, 
                      :use_ssl => (uri.scheme == 'https'), 
                      :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

        request = Net::HTTP::Post.new( uri.path,
                                       'Cookie' =>  "csrftoken=#{csrf_token}",
                                       'X-CSRFToken' => csrf_token,
                                       'Referer' => 'https://accounts.coursera.org/signin'
                                        )
        request.set_form_data('email' => @username, 'password' => @password)

        response = http.request(request)
        raise "Unable to complete login." unless response["Set-Cookie"]
        cookies = response["Set-Cookie"]

        @cauth = CourseraSession.parse_value('CAUTH', cookies)
        @username = nil
        @password = nil
      end
    end
    @cauth
  end

  def cookies
    unless @cookies
      @cookies = { maestro_login_flag: 1, CAUTH: cauth }
    end
    @cookies
  end

  def cookie_string
    unless @cookie_string
      result = ''
      cookies.each do |key, val|
        result += "#{key}=#{val};"
      end
      @cookie_string = result[0...-1]
    end
    @cookie_string
  end

  def course_content
    #not cached
    uri = URI( course_content_uri )
    Net::HTTP.start(uri.host, uri.port, 
                    :use_ssl => (uri.scheme == 'https'),
                    :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|
      request = Net::HTTP::Get.new(
        uri.path,
        'Cookie' => cookie_string)

      response = http.request(request)
      raise "Unable to load course content" unless response.body
      response.body
    end
  end

  def get_resource_links
    #not cached
    page = Nokogiri::HTML(course_content)
    links = []

    page.css('div.course-lecture-item-resource').each do |div|
       div.css('a').each do |link|
        links << link.attributes['href'].value
       end
    end
    links
  end
end

class CourseraResourceDownloader

  @@default_extensions = ['.mp4', '.srt', '.pdf', '.pptx', '.ppt']
  @@default_filename_subs = { ':' => '', '_' => '', '/' => '_', '?' => '', "'" => '', '\\' => ''}

  def CourseraResourceDownloader.default_extensions
    @@default_extensions
  end

  def CourseraResourceDownloader.default_filename_subs
    @@default_extensions
  end

  def initialize session, options = {}
    options = { dest_folder: Dir.pwd,
                extensions: @@default_extensions,
                filename_subs: {} }.merge(options)
    @session = session

    @dest = options[:dest_folder]
    unless [:exists?, :directory?].all? {|method| File.send(method, @dest)}
      raise "Invalid destination folder: #{@dest}"
    end

    @extensions = options[:extensions]
    @filename_subs = @@default_filename_subs.merge(options[:filename_subs])
  end

  def download
    agent = create_agent

    links = @session.get_resource_links
    links.each do |link|
      next unless URI.regexp =~ link
      filename = substitute_filename(get_filename(agent, link))
      next unless valid_extension? filename

      if File.exists?(destination = File.join(@dest, filename))
        puts "#{filename} already exists. Skipping."
      end

      puts "Downloading '#{link}'' to '#{filename}' ..."
      begin
        gotten = agent.get(link)
        gotten.save(destination)
        puts "Finished."
      rescue Mechanize::ResponseCodeError => exception
        if exception.response_code == '403'
          $stderr.puts exception.message
          $stderr.puts "Failed to download #{filename} for #{exception}"
        else
          raise exception # Some other error, re-raise
        end
      end

    end
  end

  def create_agent
    agent = Mechanize.new
    @session.cookies.each do |key, val|
      cookie = Mechanize::Cookie.new(key.to_s, val.to_s)
      cookie.domain = "class.coursera.org"
      cookie.path = "/"
      agent.cookie_jar.add(cookie)
    end
    agent
  end

  def get_filename agent, link
    begin
      head = agent.head(link)
    rescue Mechanize::ResponseCodeError => exception
      if exception.response_code == '403'
        filename = URI.decode(exception.page.filename).gsub(/.*filename=\"(.*)\"+?.*/, '\1')
      else
        raise exception # Some other error, re-raise
      end
    else
      # First try to access direct the content-disposition header, because mechanize
      # split the file at "/" and "\" and only use the last part. So we get trouble
      # with "/" in filename.
      if head.response["Content-Disposition"] && 
        (content_disposition = Mechanize::HTTP::ContentDispositionParser.parse(head.response["Content-Disposition"]))
        filename = URI.decode(content_disposition.filename.gsub(/http.*\/\//,""))
      else
        # If we have no file found in the content disposition take the head filename
        filename = URI.decode(head.filename)
      end
    end
    filename
  end

  def valid_extension?(filename)
    extname = File.extname filename
    @extensions.any? {|ext| ext == extname}
  end

  def substitute_filename(filename)
    result = filename
    @filename_subs.each do |key, val|
      result = result.gsub(key, val)
    end
    result
  end

end

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
downloader = CourseraResourceDownloader.new session
downloader.download


require "mechanize"
require "mechanize/http/content_disposition_parser"
require "uri"
require 'net/https'
require 'cgi'
require 'nokogiri'

class CourseraSession

  @@base_course_uri = 'https://class.coursera.org/%s'
  @@login_uri = 'https://accounts.coursera.org/api/v1/login'
  @@course_content_path = '/lecture/index'

  def CourseraSession.parse_value(key, string)
    regexp = Regexp.new("#{key}=([^;]+)")
    string.match(/CAUTH=([^;]+)/)[1]
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



if ARGV.size != 3
  puts "coursera-downloader.rb <username> <password> <course>"
  exit 1
end

session = CourseraSession.new *ARGV

agent = Mechanize.new

session.cookies.each do |key, val|
  cookie = Mechanize::Cookie.new(key.to_s, val.to_s)
  cookie.domain = "class.coursera.org"
  cookie.path = "/"
  agent.cookie_jar.add(cookie)
end

# Download all files to the current directory
session.get_resource_links.each do |link|
  unless (link =~ URI::regexp).nil?
    uri = link
    if (uri =~ /\.mp4/) || (uri =~ /srt/) || (uri =~ /\.pdf/) || (uri =~ /\.pptx/)
      begin
        head = agent.head(uri)
      rescue Mechanize::ResponseCodeError => exception
        if exception.response_code == '403'
          filename = URI.decode(exception.page.filename).gsub(/.*filename=\"(.*)\"+?.*/, '\1')
#        elsif exception.response_code == '404'
#          $stderr.puts "Page not found: #{uri}"
#          next
        else
          raise exception # Some other error, re-raise
        end
      else
        # First try to access direct the content-disposition header, because mechanize
        # split the file at "/" and "\" and only use the last part. So we get trouble
        # with "/" in filename.
        if not head.response["Content-Disposition"].nil?
          content_disposition = Mechanize::HTTP::ContentDispositionParser.parse head.response["Content-Disposition"]
          filename = content_disposition.filename if content_disposition
        end

        # If we have no file found in the content disposition take the head filename
        filename ||= head.filename
        filename = URI.decode(filename.gsub(/http.*\/\//,""))
      end

      # Replace unwanted characters from the filename
      filename = filename.gsub(":","").gsub("_","").gsub("/","_").gsub('?', '').gsub("'", '').gsub('\\', '')

      if File.exists?(filename)
        p "Skipping #{filename} as it already exists"
      else
        p "Downloading #{uri} to #{filename}..."
        begin
          gotten = agent.get(uri)
          gotten.save(filename)
          p "Finished"
        rescue Mechanize::ResponseCodeError => exception
          if exception.response_code == '403'
            p "Failed to download #{filename} for #{exception}"
          else
            raise exception # Some other error, re-raise
          end
        end
      end
    end
  end
end

require "uri"
require 'net/https'
require 'nokogiri'

class CourseraSession

  @@base_course_uri = 'https://class.coursera.org/%s'
  @@login_uri = 'https://accounts.coursera.org/api/v1/login'
  @@course_content_path = '/lecture'

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

  def cookies
    unless @cookies
      @cookies = { maestro_login_flag: 1, CAUTH: cauth }
    end
    @cookies
  end

  def resource_links
    #not cached
    page = Nokogiri::HTML(course_content)
    links = []

    page.css('div.course-lecture-item-resource').each do |div|
       div.css('a').each do |link|
        links << link.attributes['href'].value
       end
    end
    links.delete_if {|link| link =~ /^forum:/ }
    links
  end

  # The password should not show up in debug
  def inspect
    str = super
    str.gsub(/\@password\=\"[^\"]+\"(, )?/, '')
  end

private

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

end

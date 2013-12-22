require "mechanize"
require "mechanize/http/content_disposition_parser"
require 'nokogiri'

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
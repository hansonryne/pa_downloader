# Author:  Ryne Hanson (@_hansonet_)
# Pentester Academy video download script.
#
# It is function-focused and not at all pretty
#
# Plans:
#   Add option parser
#


require 'rubygems'
require 'tty-progressbar'
require 'mechanize'
require 'cgi'
require 'typhoeus'
require 'open-uri'

NAVIGATOR = Mechanize.new { |agent|
  agent.user_agent_alias = "Windows Firefox"
}

# Need to build the cookie from a pasted value since you can't login via Mechanize or Selenium if you have MFA on your Google account.
def build_cookie(cookieValue)
#   httpCookie = CGI::Cookie.new("SACSID", cookieValue)
#   httpCookie.path = "/"
#   httpCookie.domain = "www.pentesteracademy.com"
#   httpCookie.expires = Time.now + (60*60*24)
#   httpCookie.secure = true
#   httpCookie.httponly = true
#   httpCookie.name.to_s + "=" + httpCookie.value.to_s
#   httpCookieReturned = httpCookie.to_s.split(";")[0]
  httpCookie = "SACSID=" + cookieValue
end


# Based on the provided course ID, there is a different list of videos
# This returns that list of videos as an Array
def scrape_course_links(courseID)
  #Thanks for the null byte in the html Vivek
  html = open('https://www.pentesteracademy.com/course?id=' + courseID).read.gsub("\u0000","")
  parsed = Nokogiri::HTML(html)
  links = parsed.xpath('//a')

  vidLinks = []
  
  # Unless....if...unless.  Sorry
  links.each do |l|
    unless l.attribute('href').nil?
      if l.attribute('href').value.match(/video\?id=\d+/)
        vidLinks << [l.attribute('href').value, l.inner_text.strip] unless l.inner_text.strip.empty?
      end
    end
  end
  return vidLinks
end


# Returns a hash with video number as a key and Mechanize link object as the value
def choose_videos(first, last, list)
  videoHash = Hash[Array(first..last).zip(list[first-1..last-1])]
end

# Navigates to each video page and finds the acutal download link
# Returns an Array of paths to download links
def scrape_download_links(videoList)
  downloadLinks = []
  videoList.each do |key, link|
    temp = NAVIGATOR.get('https://www.pentesteracademy.com' + link[0])
    downloadLinks << temp.link_with(:text => "Video").href
  end
  downloadLinks
end

# Writes the files with a easily searchable filename

# Threaded downloader with Typheous
# Where most of the magic happens
def download_videos(videoHash, cookie, concurrency)
  bars = TTY::ProgressBar::Multi.new("Overall [:bar] :percent")
  videoArray = videoHash.to_a
  hydra = Typhoeus::Hydra.new(max_concurrency: concurrency)

  barArray = Hash.new
  videoArray.map do |i|
    barArray[i[0]] = bars.register("#{i[1][0].to_s} [:bar]", total: 100)
  end

  fileLinks = videoArray.map do |i|
    'https://www.pentesteracademy.com' + i[1][1]
  end
  videoArray.each do |vid|
    filename = "%03d" % (vid[0]) + "_" + vid[1][0][1].to_s.tr(":", "").tr(",", "").strip.tr(" ", "_") + ".mp4"
    download_file = File.open filename, 'wb'
    link = 'https://www.pentesteracademy.com' + vid[1][1]
    request = Typhoeus::Request.new(link, headers: {'Cookie' => cookie}, followlocation: true)

    request.on_progress { |dltotal, dlnow, ultotal, ulnow|
      if dltotal.is_a? Integer
        percent = (dlnow.to_f / dltotal.to_f)
        if percent.nan?
          percent = 0
        end
        barArray[vid[0]].ratio = percent
      end
    }
    request.on_body do |chunk|
      download_file.write(chunk)
    end
    request.on_complete do |response|
      download_file.close
    end
    hydra.queue(request)
  end
  hydra.run

end

# Gathering information
# -----------------------
puts "Enter the course ID?"
course = gets.strip

puts "What is your session cookie?"
cookie = gets.strip

sessionCookie = build_cookie(cookie)
# -----------------------

# Presenting videos to user to select
# ------------------------
links = scrape_course_links(course.to_s)

links.each do |l|
  printf "#%-5s %-100s %s\n", (links.find_index(l)+1).to_s, l[1], l[0]
end
# -----------------------

# Make user select the range of videos they want
#  ----------------------
puts "Enter the range of videos you want to download."
puts "Which number do you want to start with?"
first = gets.strip.to_i
puts "Which number do you want to end with?"
last = gets.strip.to_i
# -----------------------

# Get final object ready to send to download function
# -----------------------
toDownload = choose_videos(first, last, links)

videoFileLinks = scrape_download_links(toDownload)

downloadHash = {}

toDownload.each do |key, value|
  downloadHash[key.to_s] = [value, videoFileLinks[key.to_i-first]]
end
# -----------------------

puts "Starting Download"
download_videos(downloadHash, sessionCookie, 5)

# Author:  Ryne Hanson (@_hansonet_)
# Pentester Academy video download script.
#
# It is function-focused and not at all pretty
#
# Plans:
#   Upgrade to selenium driver to handle sessions
#   Add option parser
#


require 'rubygems'
require 'mechanize'
require 'em-http'
require 'cgi'

NAVIGATOR = Mechanize.new { |agent|
  agent.user_agent_alias = "Windows Firefox"
}

# Need to build the cookie from a pasted value since you can't login via Mechanize.
# This will go away in a future version
def build_cookie(cookieValue)
  httpCookie = CGI::Cookie.new("SACSID", cookieValue)
  httpCookie.path = "/"
  httpCookie.domain = "www.pentesteracademy.com"
  httpCookie.expires = Time.now + (60*60*24)
  httpCookie.secure = true
  httpCookie.httponly = true
  httpCookie.to_s
end


# Based on the provided course ID, there is a different list of videos
# This returns that list of videos as an Array
def scrape_course_links(courseID)
  coursePage = NAVIGATOR.get('https://www.pentesteracademy.com/course?id=' + courseID)
  videoList = coursePage.links_with(:href => /video/)

  uniqueVideoList = videoList.reverse.uniq {|i| i.href}.reverse
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
    temp = NAVIGATOR.get('https://www.pentesteracademy.com' + link.href)
    downloadLinks << temp.link_with(:text => "Video").href
  end
  downloadLinks
end

# Writes the files with a easily searchable filename
def write_file(num, file, name)
  formattedName = "%03d" % (num) + "_" + name.tr(":", "").tr(",", "").strip.tr(" ", "_") + ".mp4"
  open(formattedName, "wb") do |f|
    f.write(file)
  end
end

# Threaded downloader with EventMachine
# Where most of the magic happens
def download_videos(videoHash, cookie, concurrency)
  EventMachine.run do
    multi = EventMachine::MultiRequest.new

    # Converts argument Hash from {"1" => [Link, path]} format to ["1", [Link, path]] format
    # Because I'm too lazy to OOP this
    videoArray = videoHash.to_a

    EM::Iterator.new(videoArray, concurrency).each do |url, iterator|
      downloadPath = url[1][1]
      # Yeah go ahead and hard-code that url you idi0t
      downloadURL = 'https://www.pentesteracademy.com' + downloadPath
      # Figuring out how to add the cookie to the request took way too long
      req = EventMachine::HttpRequest.new(downloadURL).get :redirects => 3, :head => {'cookie' => [cookie]} 
      req.callback do
        # This is disgusting
        write_file(url[0].to_i, req.response, url[1][0].to_s)
        iterator.next
      end
      multi.add url, req
      multi.callback { EventMachine.stop } if url == videoArray.last
    end
  end
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
  printf "#%-5s %-100s %s\n", (links.find_index(l)+1).to_s, l.text.strip, l.href
end
# -----------------------


# Make user selecte the range of videos they want
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
download_videos(downloadHash, sessionCookie, 10)

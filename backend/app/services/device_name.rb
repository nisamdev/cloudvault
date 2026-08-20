# frozen_string_literal: true

# Turns a user agent into something a person can recognise in a session list.
#
# Deliberately crude: the only question being answered is "is that one mine?",
# and for that "Safari on iPhone" beats a hundred characters of version soup. No
# gem for this — a stale UA database quietly mislabels new devices.
module DeviceName
  module_function

  BROWSERS = [
    [ /Edg\//,                      "Edge" ],
    [ /OPR\/|Opera/,                "Opera" ],
    [ /Chrome\/|CriOS/,             "Chrome" ],
    [ /Firefox\/|FxiOS/,            "Firefox" ],
    [ /Safari\//,                   "Safari" ]
  ].freeze

  PLATFORMS = [
    [ /iPhone/,                     "iPhone" ],
    [ /iPad/,                       "iPad" ],
    [ /Android/,                    "Android" ],
    [ /Windows/,                    "Windows" ],
    [ /Macintosh|Mac OS X/,         "Mac" ],
    [ /CrOS/,                       "ChromeOS" ],
    [ /Linux/,                      "Linux" ]
  ].freeze

  def for(user_agent)
    return "Unknown device" if user_agent.blank?

    browser = BROWSERS.find { |pattern, _| user_agent.match?(pattern) }&.last
    platform = PLATFORMS.find { |pattern, _| user_agent.match?(pattern) }&.last

    return "Unknown device" if browser.nil? && platform.nil?
    return platform if browser.nil?
    return browser if platform.nil?

    "#{browser} on #{platform}"
  end
end

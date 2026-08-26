# frozen_string_literal: true

# Pulls a capture date out of a filename when EXIF is missing.
#
# Messaging apps (WhatsApp especially) strip EXIF but leave the date in the
# name — "WhatsApp Image 2024-04-30 at 2.21.30 PM.jpeg". Without this the
# gallery would file the photo under the upload day instead.
class FilenameDateParser
  PATTERNS = [
    # WhatsApp Image 2024-04-30 at 2.21.30 PM
    /
      (?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})
      [ _]+at[ _]+
      (?<h>\d{1,2})[.:](?<min>\d{2})[.:](?<s>\d{2})
      (?:[ _]*(?<ampm>[AaPp][Mm]))?
    /x,
    # IMG_20240430_142130 / 20240430_142130
    /(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})[_-](?<h>\d{2})(?<min>\d{2})(?<s>\d{2})/,
    # 2024-04-30 anywhere in the name
    /(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})/
  ].freeze

  def self.call(name)
    new(name).call
  end

  def initialize(name)
    @name = name.to_s
  end

  def call
    PATTERNS.each do |pattern|
      match = @name.match(pattern)
      next unless match

      time = build(match)
      return time if time
    end

    nil
  end

  private

  def build(match)
    year = match[:y].to_i
    month = match[:m].to_i
    day = match[:d].to_i
    hour = match.names.include?("h") && match[:h] ? match[:h].to_i : 12
    minute = match.names.include?("min") && match[:min] ? match[:min].to_i : 0
    second = match.names.include?("s") && match[:s] ? match[:s].to_i : 0

    if match.names.include?("ampm") && match[:ampm]
      ampm = match[:ampm].upcase
      hour = 0 if ampm == "AM" && hour == 12
      hour += 12 if ampm == "PM" && hour < 12
    end

    time = Time.utc(year, month, day, hour, minute, second)
    return nil if time.year < 1990 || time > 1.day.from_now

    time
  rescue ArgumentError
    nil
  end
end

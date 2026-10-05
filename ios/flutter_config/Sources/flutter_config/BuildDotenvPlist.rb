#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'ReadDotEnv'

envs_root = ARGV[0]
plist_output = ARGV[1]
puts "reading env file from #{envs_root} and writing .plist to #{plist_output}"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

dotenv, custom_env = read_dot_env(envs_root)

def escape_xml(str)
  str.to_s
     .gsub('&', '&amp;')
     .gsub('<', '&lt;')
     .gsub('>', '&gt;')
     .gsub('"', '&quot;')
     .gsub("'", '&apos;')
end

plist_entries = dotenv.map do |k, v|
  "    <key>#{escape_xml(k)}</key>\n    <string>#{escape_xml(v)}</string>"
end.join("\n")

plist_content = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
#{plist_entries}
  </dict>
  </plist>
XML

File.open(plist_output, 'w') { |f| f.puts plist_content }
puts "Wrote to #{plist_output}"

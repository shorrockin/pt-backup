require 'rubygems'
require 'bundler'
Bundler.require

require 'fileutils'

@config = YAML::load_file('config.yml')
raise "api_token missing from config.yml" if @config['api_token'].nil? || @config['api_token'].empty?
PivotalTracker::Client.token = @config['api_token']

def tracker_get(url, path)
  uri = URI.parse url
  http = Net::HTTP.new uri.host, uri.port
  http.use_ssl = uri.is_a?(URI::HTTPS)
  http.request_get uri.request_uri, { 'X-TrackerToken' => @config['api_token'] } do |response|
    raise "#{response.code} #{response.message}" unless response.is_a? Net::HTTPSuccess
    File.open "#{path}.new", 'w' do |io|
      response.read_body do |segment|
        io.write segment
      end
    end
    FileUtils.mv "#{path}.new", path
  end
end

PivotalTracker::Project.all.each do |project|
  puts "Backing up #{project.name.inspect}..."
  FileUtils.mkdir_p "projects/#{project.name}"
  
  tracker_get \
    "https://www.pivotaltracker.com/services/v3/projects/#{project.id}/stories",
    "projects/#{project.name}/stories.xml"
end

dump_file = "pivotal.backup.#{Time.now.utc.strftime("%Y%m%d%H%M")}.tar.gz"
gpg_dump_file = "#{dump_file}.gpg"
begin
  puts "Compressing into: #{dump_file}"
  system("tar czvf #{dump_file} projects/")
  system("gpg --encrypt --recipient '#{@config['gpg_recipient']}' #{dump_file}")

  puts "Sending backup file to S3"
  AWS::S3::Base.establish_connection!(:access_key_id => @config['s3_access_key_id'], :secret_access_key => @config['s3_secret_access_key'], :use_ssl => true)
  AWS::S3::Bucket.create( @config['s3_bucket_name'] )
  AWS::S3::S3Object.store(File.basename(gpg_dump_file), open(gpg_dump_file), @config['s3_bucket_name'])
ensure
  system("rm -Rf projects")
  system("rm -f #{dump_file}")
  system("rm -f #{gpg_dump_file}")
end

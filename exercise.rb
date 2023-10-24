# There's probably a lot of choices in this exmample that I wouldn't do
# if this was a real script.
#
# I used only built in libraries to avoid dependencies
# I ignored potential of encoding issues in the data files
# The script halts on input error to allow the user to correct the error
# I changed the duplicate user id for a user in a company to a warn to make the
# example input work
# I added an additional sort field to make duplicate last names sort consistently
# Decided that users without an existing company are an error condition
# It wasn't specified what to do if a company had no topops so I still displayed the company

# Things I'd consider in a production script
#
# Handling errors in the input would have been determined by the use case,
#  * should the script try to repair common errors?
#  * halt and have the operator fix the imput data before continuing?
# If the script was intended to run unattended that would also change the method
# of error handling
# I probably would have considered if I had to worry about memory constraints/streaming
# the data to prevent memory exhaustion


require 'json'
require 'optparse'
require 'pathname'

class Company < Struct.new(:id,
                           :name,
                           :top_up,
                           :email_status,
                           :users,
                           :total_previous_top_up,
                           keyword_init: true)
  def initialize(hash)
    super(hash)
    self.users = []
  end

  def valid?
    self.id.integer? &&
    self.name.is_a?(String) &&
    self.top_up.integer? &&
    ((self.email_status == true) ^ (self.email_status == false))
  end

  def add_user(user)
    warn("Duplicated user: #{user}") if duplicate?(user)
    users << user
  end

  # No duplicate ids, no duplicate emails - per company
  def duplicate?(user)
    users.filter {|u| u.id == user.id || (u.email.casecmp(user.email) == 0)}
      .length > 0
  end

  def top_up_users
    change = active_users.map do |u|
      u.top_up_account(top_up)
    end
    self.total_previous_top_up = change.sum
  end

  def active_users
    users.filter { |u| u.active_status }
  end

  def report(dest = $stdout)
    dest << "\n"
    dest << "\tCompany Id: #{id}\n"
    dest << "\tCompany Name: #{name}\n"
    email_users_report(dest)
    no_email_users_report(dest)
    dest << "\t\tTotal amount of top ups for #{name}: #{total_previous_top_up}\n"
  end

  def email_users_report(dest = $stdout)
    dest << "\tUsers Emailed:\n"
    email_users.each {|u| u.report(dest)}
  end

  # No one gets email if the company doesn't send email
  def email_users
    return [] unless email_status
    active_users.filter {|u| u.email_status}
      .sort_by { |u| [u.last_name, u.first_name] }
  end

  def no_email_users_report(dest = $stdout)
    dest << "\tUsers Not Emailed:\n"
    no_email_users.each {|u| u.report(dest)}
  end

  # Only filter this list if the company allows email otherwise it is all users
  def no_email_users
    tmp = active_users.sort_by { |u| [u.last_name, u.first_name] }
    tmp = tmp.filter {|u| u.email_status == false} if email_status
    tmp
  end

  def active_users
    users.filter { |u| u.active_status }
  end
end

class User < Struct.new(:id,
                        :first_name,
                        :last_name,
                        :email,
                        :company_id,
                        :email_status,
                        :active_status,
                        :tokens,
                        :token_history,
                        keyword_init: true)
  def initialize(hash)
    super(hash)
    self.token_history = [ self.tokens ]
  end

  def valid?
    self.id.integer? &&
    self.first_name.is_a?(String) && !self.first_name.empty? &&
    self.last_name.is_a?(String) && !self.last_name.empty? &&
    self.email.is_a?(String) && !self.email.empty? &&
    self.company_id.integer? &&
    ((self.email_status == true) ^ (self.email_status == false)) &&
    ((self.active_status == true) ^ (self.active_status == false))
  end

  def top_up_account(amt)
    self.tokens = tokens + amt
    self.token_history << tokens
    amt
  end

  def report(dest = $stdout)
    dest << "\t\t#{last_name}, #{first_name}, #{email}\n"
    dest << "\t\t  Previous Token Balance, #{token_history[-2]}\n"
    dest << "\t\t  New Token Balance #{tokens}\n"
  end
end

class Report
  def initialize(companies)
    @companies = companies.sort.map(&:last)
  end

  def report(outfile = nil)
    output = $stdout
    output = File.open(outfile, "w") if outfile
    begin
      @companies.each do |c|
        c.report(output)
      end
    ensure
      output.close if outfile
    end
  end
end

# Both files share a format of Array of Hash objects.
def json_format_check(json)
  json.class == Array &&
  json.map(&:class).filter {|x| x != Hash}.length == 0
end

# SanityCheck/Document the original targeted runtime
SCRIPT_RUNTIME_TARGET = "3.2.2"
if Gem::Version.new(RUBY_VERSION) < Gem::Version.new(SCRIPT_RUNTIME_TARGET) then
  abort("Error: This script was written to run under #{SCRIPT_RUNTIME_TARGET}")
  exit(false)
end

options = {output: "output.txt"}
parser = OptionParser.new
parser.on("-c", "--companies COMPANY_LIST",
          "Provide a company list to generate the report") do |val|
  abort("Missing company file") unless Pathname.new(val).exist?
  options[:companies] = val
end
parser.on("-u", "--users USER_LIST",
          "Provided a user list to generate the report") do |val|
  abort("Missing user file") unless Pathname.new(val).exist?
  options[:users] = val
end
parser.on("-o", "--output OUTPUT_FILE",
         "Provide an optional output file")
parser.parse!(into: options)
required_options = [:companies, :users]
missing_options = required_options - options.keys
unless missing_options.empty?
  abort "Missing required options: #{missing_options}"
end
abort("Output file #{options[:output]} already exists") if Pathname.new(options[:output]).exist?

# If either of these throw exceptions the script will stop and the message should
# indicate enough for the operator to fix it, capturing the exception is redundant
#companies_file = File.open("companies.json")
companies_file = File.open(options[:companies])
companies_parse = JSON.load(companies_file)

#SanityCheck companies data
if !json_format_check(companies_parse) then
  abort("Companies file is not in the expected json format")
end
companies = {}
companies_parse.each do |company|
  c = Company.new(company)
  abort("Invaid company") unless c.valid?
  abort("Duplicate company entry") if companies.key?(c.id)
  companies[c.id] = c
end

#users_file = File.open("users.json")
users_file = File.open(options[:users])
users_parse = JSON.load(users_file)

#SanityCheck users data
if !json_format_check(users_parse) then
  abort("Users file is not in the expected json format")
end

users_parse.each do |user|
  u = User.new(user)
  abort("Invalid user: #{u}") unless u.valid?
  abort("Orphaned user: #{u}") if !companies.key?(u.company_id)
  companies[u.company_id].add_user(u)
end

# Generate Report
companies.values.map(&:top_up_users)
Report.new(companies).report(options[:output])

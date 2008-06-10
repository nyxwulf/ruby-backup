#! /usr/bin/env ruby

require 'time'
require 'net/ftp'
require 'rubygems'
require 'net/sftp'
require 'action_mailer'
require 'backup_config'
include BackupConfig
                                 

def time_it(&block)
  t1 = Time.now
  retval = block.call
  t2 = Time.now
  execution_time = (t2 - t1)
  puts "Execution time " + execution_time.to_s

  return execution_time
end


def main()
  begin
    Dir.chdir(BACKUP_DIR)
    total_time = time_it do
      backup_databases
    end
    BackupMailer.deliver_success_email(total_time) if SEND_EMAIL_ALERTS
  rescue Exception => e
    BackupMailer.deliver_error_email(e) if SEND_EMAIL_ALERTS
  end
end

def backup_databases()
  for db in DATABASES
    puts "Backing up #{db}"
    bak_file = "#{db}_#{Time.now.strftime("%Y%m%d_%H%M%S")}.bak"
    # --routines will backup stored routines
    # -q will backup each table one row at a time (innodb) making this backup suitable for hot backups
    # --single-transaction will capture a fully consistent snapshot of the database at the time the BEGIN statement is issued (innodb only)
    `#{MYSQLDUMP} --host #{DB_HOST} --user=#{DB_USERNAME} --password=#{DB_PASSWORD} --routines -q --single-transaction --databases #{db} > #{bak_file}`
    compressed_file = compress_file(bak_file)
    ftp_file(compressed_file) if FTP_FILES
  end
end

def compress_file(file_name)
  puts "Compressing #{file_name}"
  gzip_file = file_name.gsub(File.extname(file_name), '.tar.gz')
  `tar -czf #{gzip_file} #{file_name}`
  gzip_file
end

def ftp_file(file_name)
  if SFTP
    remote_path = FTP_BACKUP_DIR + "/#{file_name}"
    puts "SFTPing #{file_name} to #{remote_path}"
    
    Net::SFTP.start(FTP_SERVER, FTP_USER, :password => FTP_PASSWORD) do |sftp|
      sftp.upload!("./#{file_name}", remote_path)
    end
  else
    puts "FTPing #{file_name}"

    Net::FTP.open(FTP_SERVER) do |ftp|
      ftp.login(FTP_USER, FTP_PASSWORD)
      ftp.chdir(FTP_BACKUP_DIR)
      ftp.putbinaryfile(file_name)
    end
  end
  
  
end

class BackupMailer < ActionMailer::Base
  def error_email(exception)
    from EMAIL_FROM
    recipients EMAIL_NOTIFICATION
    subject %Q!Database backup failed on #{Time.now.strftime("%D")}!
    body <<-EOL
Error Message:
#{exception.message}
    
Backtrace:
#{exception.backtrace.inspect}
EOL
  end

  def success_email(execution_time)
    backup_date = Time.now.strftime("%D")
    from EMAIL_FROM
    recipients EMAIL_NOTIFICATION
    subject %Q!Database backup succeeded for #{backup_date}!
    body <<-EOL
Successfully backed up on #{backup_date}:
#{DATABASES.join("\n")}    
Total Execution Time: #{execution_time}
    EOL
  end
end

if __FILE__ == $0
    main
end

class APN::App < APN::Base
  
  has_many :groups, :class_name => 'APN::Group', :dependent => :destroy
  has_many :devices, :class_name => 'APN::Device', :dependent => :destroy
  has_many :notifications, :through => :devices, :dependent => :destroy
  has_many :unsent_notifications, :through => :devices
  has_many :group_notifications, :through => :groups
  has_many :unsent_group_notifications, :through => :groups
    
  def cert
    (Rails.env == 'production' ? apn_prod_cert : apn_dev_cert)
  end
  
  # Opens a connection to the Apple APN server and attempts to batch deliver
  # an Array of group notifications.
  # 
  # 
  # As each APN::GroupNotification is sent the <tt>sent_at</tt> column will be timestamped,
  # so as to not be sent again.
  # 
  def send_notifications
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    APN::App.send_notifications_for_cert(self.cert, self.id)
  end
  
  def self.send_notifications
    apps = APN::App.all 
    apps.each do |app|
    # puts "Analisando notificacoes da aplicacao de id = " + app.id.to_s
      app.send_notifications
    end
    if !configatron.apn.cert.blank?
      global_cert = File.read(configatron.apn.cert)
      send_notifications_for_cert(global_cert, nil)
    end
  end
  
  def self.send_notifications_for_cert(the_cert, app_id)
    # puts "send_notifications_for_cert - Entrada"
    # unless self.unsent_notifications.nil? || self.unsent_notifications.empty?
      if (app_id == nil)
        conditions = "app_id is null"
      else 
        conditions = ["app_id = ?", app_id]
      end
      # puts "send_notifications_for_cert - Ponto 0"
      begin
        APN::Connection.open_for_delivery({:cert => the_cert}) do |conn, sock|
          # puts "send_notifications_for_cert - Ponto 1"
          APN::Device.find_each(:conditions => conditions) do |dev|
            # puts "send_notifications_for_cert - Ponto 2"
            unsent_notifications = dev.unsent_notifications
            next if unsent_notifications.length == 0
            
            last = ""
            mark_as_sent = []
            unsent_notifications.map! do |noty| 
              unless noty.alert == last
                last = noty.alert
                noty
              else
                mark_as_sent.push noty.id
              end
            end
            
            unsent_notifications.each do |noty|
              next unless noty
              begin
                conn.write(noty.message_for_sending)
              rescue => e
                Rails.logger.error e.message
              end
              mark_as_sent.push noty.id
            end
            
            APN::Notification.mark_sent(mark_as_sent)
          end
        end
      rescue Exception => e
        puts e.message
      end
      # puts "send_notifications_for_cert - Saida"
    # end   
  end
  
  def send_group_notifications
    if self.cert.nil? 
      raise APN::Errors::MissingCertificateError.new
      return
    end
    unless self.unsent_group_notifications.nil? || self.unsent_group_notifications.empty? 
      APN::Connection.open_for_delivery({:cert => self.cert}) do |conn, sock|
        unsent_group_notifications.each do |gnoty|
          gnoty.devices.find_each do |device|
            conn.write(gnoty.message_for_sending(device))
          end
          gnoty.sent_at = Time.now
          gnoty.save
        end
      end
    end
  end
  
  def send_group_notification(gnoty)
    if self.cert.nil? 
      raise APN::Errors::MissingCertificateError.new
      return
    end
    unless gnoty.nil?
      APN::Connection.open_for_delivery({:cert => self.cert}) do |conn, sock|
        gnoty.devices.find_each do |device|
          conn.write(gnoty.message_for_sending(device))
        end
        gnoty.sent_at = Time.now
        gnoty.save
      end
    end
  end
  
  def self.send_group_notifications
    apps = APN::App.all
    apps.each do |app|
      app.send_group_notifications
    end
  end          
  
  # Retrieves a list of APN::Device instnces from Apple using
  # the <tt>devices</tt> method. It then checks to see if the
  # <tt>last_registered_at</tt> date of each APN::Device is
  # before the date that Apple says the device is no longer
  # accepting notifications then the device is deleted. Otherwise
  # it is assumed that the application has been re-installed
  # and is available for notifications.
  # 
  # This can be run from the following Rake task:
  #   $ rake apn:feedback:process
  def process_devices
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    APN::App.process_devices_for_cert(self.cert)
  end # process_devices
  
  def self.process_devices
    apps = APN::App.all
    apps.each do |app|
      app.process_devices
    end
    if !configatron.apn.cert.blank?
      global_cert = File.read(configatron.apn.cert)
      APN::App.process_devices_for_cert(global_cert)
    end
  end
  
  def self.process_devices_for_cert(the_cert)
    puts "in APN::App.process_devices_for_cert"
    APN::Feedback.devices(the_cert).each do |device|
      if device.last_registered_at < device.feedback_at
        # puts "device #{device.id} -> #{device.last_registered_at} < #{device.feedback_at}"
        device.destroy
      else 
        # puts "device #{device.id} -> #{device.last_registered_at} not < #{device.feedback_at}"
      end
    end 
  end
  
  
  # protected
  # def log_connection_exception(ex)
  #   puts ex.message
  # end
    
end

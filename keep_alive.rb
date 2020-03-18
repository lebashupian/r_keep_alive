#!/opt/ruby_2.4.0/bin/ruby -w
# coding: utf-8
# 
# 用来完成接受应用的报道信息，并主动发送报警信息。
begin
	require 'yaml'
	require 'socket'               # 获取socket标准库
########### 使用$配置文件
	YAML_FILE             ="#{__dir__}/config/config.yml"
	$配置文件               =YAML.load(File.open(YAML_FILE,'r'));
	######
	主机名                = $配置文件["hostname"]
	本地IP                = $配置文件["local_ip"]
	远端IP                = $配置文件["remote_ip"]
	本地端口              = $配置文件["local_port"]
	远端端口              = $配置文件["remote_port"]
	say_hello_log         = $配置文件["say_hello_log"]["say_hello"]
	包发送检查延迟         = $配置文件["packet_send_check_delay"].to_f
	say_hello延迟         = $配置文件["say_hello_delay"].to_f
	say_hello_重试次数    = $配置文件["say_hello_fails_retry"].to_i
	say_hello_最大超时    = $配置文件["say_hello_max_timeout"].to_i

	vip_role             = $配置文件["vip_role"]
	if vip_role == 'master'
		vip_is_config="Y"
	else
		vip_is_config="N"
	end 
########### 日志记录
	say_hello_log = File.new(say_hello_log,  "a+")
############
	线程list=[]



	##################

	def 删除vip
		虚拟ip=$配置文件["vip"]
		虚拟netmask=$配置文件["vip_netmask"]
		虚拟ip_dev=$配置文件["vip_dev"]
		`ip addr del "#{虚拟ip}"/"#{虚拟netmask}" dev "#{虚拟ip_dev}"`		
	end

	def 添加vip
		虚拟ip=$配置文件["vip"]
		虚拟netmask=$配置文件["vip_netmask"]
		虚拟ip_dev=$配置文件["vip_dev"]
		虚拟gateway=$配置文件["vip_gw"]
		`ip addr add "#{虚拟ip}"/"#{虚拟netmask}" dev "#{虚拟ip_dev}"`
		`arping -I "#{虚拟ip_dev}" -c 2 -s #{虚拟ip} #{虚拟gateway}`
	end

	添加vip if vip_is_config == "Y"

	udp对象 = UDPSocket.new
	udp对象.bind 本地IP,本地端口
	udp_hello_data = {"接力数字"=>"0","接力超时"=>Time.new}
	udp对象.send "#{udp_hello_data["接力数字"]}" ,0, 远端IP ,远端端口

	线程list << Thread.new {
		loop {
			begin
				abc = udp对象.recvfrom(1000)
				#正常情况下，每次重置一下变量
				say_hello_重试次数 = $配置文件["say_hello_fails_retry"].to_i
				
				abc = abc[0].to_i

				#puts "收到 #{abc}"
				say_hello_log.syswrite("#{主机名} 收到心跳包 #{abc}\n")
				if udp_hello_data["接力数字"].to_i >= abc and udp_hello_data["接力数字"].to_i != 0
					say_hello_log.syswrite("包重复\n")
					next
				else
					if vip_role != 'master' and vip_is_config == "Y"
						删除vip
						vip_is_config = "N"
					end				
				end
				udp_hello_data["接力数字"] = abc + 1
				udp_hello_data["接力超时"] = Time.new
				#puts "发送 #{udp_hello_data["接力数字"]}"	
				say_hello_log.syswrite("#{主机名} 发送心跳包 #{udp_hello_data["接力数字"]}\n")
				udp对象.send "#{udp_hello_data["接力数字"]}" ,0, 远端IP ,远端端口			
				sleep say_hello延迟
				puts Time.now.to_s + " loop"
			rescue Exception => e
	  			puts e.message
				retry 
			end
		}	
	}

	线程list << Thread.new {
		loop {
			sleep 包发送检查延迟
			落后时差 = Time.new - udp_hello_data["接力超时"]
			if 落后时差 > say_hello_最大超时 and say_hello_重试次数 > 0
				sleep say_hello_最大超时
				#puts "落后时差 -> #{落后时差}"
				say_hello_log.syswrite("落后时差 -> #{落后时差},重试\n")
				udp对象.send "#{udp_hello_data["接力数字"]}" ,0, 远端IP ,远端端口
				say_hello_重试次数 -= 1
			elsif 落后时差 > say_hello_最大超时 and say_hello_重试次数 <= 0
				#puts "重试完全失败"
				say_hello_log.syswrite("重试完全失败\n")

				if vip_is_config == "N"
					添加vip
					vip_is_config = "Y"
					say_hello_log.syswrite("添加vip\n")
				end
				
				udp对象.send "#{udp_hello_data["接力数字"]}" ,0, 远端IP ,远端端口
			end
		}
	}
	##############################
	# 等待所有线程的执行
	##############################
	线程list.each {|thr|
	  thr.join
	}
rescue Exception => e
	puts e.message
	删除vip
	vip_is_config = "N"
end
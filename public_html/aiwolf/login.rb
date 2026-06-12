# -*- coding: utf-8 -*-
class Login
	attr_reader :userid, :pass, :cookie, :login
 
	def set_cookie(cgi)
		if (!@userid)
			return
		end
		@cookie = CGI::Cookie.new({"name" => 'login', "value" => "#{@userid},#{@pass}"})
		@cookie.expires = Time.now + 60*60*24*30
		#@cookie.expires = Time.now + 15
		#@cookie.path = MY_PATH
	end

	def initialize(cgi)
		userdb = PStore.new('db/user.db')
		recorddb = PStore.new('db/record.db')
		cookie = cgi.cookies['login']
		@login = false

		if (cookie && cookie.size == 1)
			val_str = CGI.unescape(cookie[0].to_s)
			vals = val_str.split(/,/)
      		@userid = vals[0]
			@pass = vals[1]

			userdb.transaction do
				if (userdb.root?(@userid))
					if (@pass == userdb[@userid]['pass'])
						@login = true
					end
				end
			end
		end

		if(@login == true)
			set_cookie(cgi)
		end
			
		cmd = cgi['cmd']
	
		if (cmd == 'logout')
			@login = false
			@userid = ''
			@pass = ''
			set_cookie(cgi)

		elsif(cmd == 'login')
			userid = cgi['userid']
			@userid = CGI.escapeHTML(Kconv.toutf8(userid))
			@pass = Kconv.toutf8(cgi['pass'])
			if(@userid == '' || @pass == '')
				script_name = ENV['SCRIPT_NAME'] ? File.basename(ENV['SCRIPT_NAME']) : "index.cgi"
				print "Status: 302 Found\n"
	        	print "Location: #{script_name}\n\n"
				exit(0)
			end

			userdb.transaction do
				if (!userdb.root?(@userid))
					userdb[@userid] = Hash.new
					userdb[@userid]['userid'] = @userid
					userdb[@userid]['pass'] = @pass
				end
			end
=begin
			recorddb.transaction do
				if (!recorddb.root?(@userid))
					recorddb[@userid] = Array.new
				end
			end
=end
			set_cookie(cgi)
		end

		if (cmd == 'login' || cmd == 'logout')
			script_name = ENV['SCRIPT_NAME'] ? File.basename(ENV['SCRIPT_NAME']) : "index.cgi"
			print "Status: 302 Found\n"
			print "Set-Cookie: #{@cookie}\n"
        	print "Location: #{script_name}\n\n"
			exit(0)
		end
	end
end
